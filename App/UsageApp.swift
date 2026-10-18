import AppKit
import SwiftUI
import WidgetKit
import ServiceManagement
import Darwin
import Combine
import UniformTypeIdentifiers

@MainActor final class UsageModel: ObservableObject {
    @Published var settings = WidgetSettings.load()
    @Published var status = StatusStore.load()
    @Published var busy = false
    @Published var message = ""
    /// A newer release on GitHub, and what the update is doing right now ("" when idle).
    @Published var update: Updater.Release?
    @Published var updateStatus = ""
    private var lastUpdateCheck = Date.distantPast
    var timer: Timer?
    private var links: AnyCancellable?
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(); self?.checkForUpdates(); self?.lookUpTools() }
        }
        DispatchQueue.main.async { [weak self] in self?.checkForUpdates(); self?.lookUpTools() }
        watchForCheckRequests()
        UsageReader.onStall = { Diagnostics.log($0) }
        links = URLRouter.shared.$refresh.sink { [weak self] requested in
            guard requested else { return }
            DispatchQueue.main.async { URLRouter.shared.refresh = false; self?.refresh(force: true) }
        }
    }
    /// `reset` drops those accounts' readings too, for example after signing in again.
    func save(reset: Set<String> = []) {
        do {
            let previous = WidgetSettings.load()
            try settings.save()
            // Disabling a provider erases its cached reading and history immediately; accounts that stay on keep theirs.
            let keep = Set(settings.enabled).subtracting(reset)
                .intersection(settings.generation == previous.generation ? Set(settings.enabled) : Set(previous.enabled))
            let destination = try StatusStore.fileURL()
            try StatusStore.locked(destination) {
                var value = StatusStore.load() ?? WidgetStatus()
                value.usage = value.usage?.filter { keep.contains($0.key) }
                value.usageHistory = value.usageHistory?.filter { keep.contains(String($0.key.split(separator: ":")[0])) }
                try JSONEncoder().encode(value).write(to: destination, options: .atomic)
            }
            status = StatusStore.load()
            WidgetCenter.shared.reloadAllTimelines()
        } catch { message = "Couldn't save settings. Check the color percentages, or reinstall the app." }
    }
    /// Set only by the README picture renderer, which has no app bundle.
    nonisolated(unsafe) static var sampleVersion: String?
    private var requestWatcher: DispatchSourceFileSystemObject?
    /// The widget's refresh button writes a request into the shared folder; check usage the moment it appears.
    private func watchForCheckRequests() {
        guard let request = StatusStore.checkRequestURL else { return }
        let folder = open(request.deletingLastPathComponent().path, O_EVTONLY)
        guard folder >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: folder, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            guard FileManager.default.fileExists(atPath: request.path) else { return }
            try? FileManager.default.removeItem(at: request)
            Diagnostics.log("Widget refresh button pressed")
            self?.refresh(force: true)
        }
        source.setCancelHandler { close(folder) }
        source.resume()
        requestWatcher = source
    }
    static var version: String { sampleVersion ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    /// Checks GitHub at launch and then once a day when automatic checks are on; `manual` checks right away.
    func checkForUpdates(manual: Bool = false) {
        // After an update, the widget stops mentioning the version now installed.
        if let shown = settings.availableUpdate, !Updater.isNewer(shown, than: Self.version) { settings.availableUpdate = nil; save() }
        guard !SettingsView.sample, manual || (settings.autoUpdates && Date().timeIntervalSince(lastUpdateCheck) >= 86400) else { return }
        guard updateStatus != "Downloading…" else { return }
        lastUpdateCheck = Date()
        if manual { updateStatus = "Checking…" }
        Task {
            let latest = try? await Updater.latest()
            Diagnostics.log("Update check: " + (latest.map { "latest " + $0.version } ?? "couldn't reach GitHub"))
            if let latest, Updater.isNewer(latest.version, than: Self.version) { update = latest; updateStatus = "" }
            else if manual { update = nil; updateStatus = latest == nil ? "Couldn't check. Try again later." : "Up to date" }
            // The widget's status line says a new version is available (shown only while automatic checks are on).
            let available = latest.flatMap { Updater.isNewer($0.version, than: Self.version) ? $0.version : nil }
            if latest != nil, settings.availableUpdate != available { settings.availableUpdate = available; save() }
        }
    }
    /// Downloads and checks the new version, then quits so it can replace this one and reopen.
    func installUpdate() {
        guard let update else { return }
        updateStatus = "Downloading…"
        Diagnostics.log("Update to " + update.version + " started")
        Task {
            do {
                try await Updater.install(update)
                // Settings comes back after the update if it was open when Update was clicked.
                UserDefaults.standard.set(SettingsView.settingsWindows.contains { $0.isVisible }, forKey: "reopenSettingsAfterUpdate")
                Updater.stopWidgetHelpers()
                NSApp.terminate(nil)
            } catch {
                Diagnostics.log("Update failed: \(error)")
                updateStatus = "Couldn't update. Opening the download page instead."
                NSWorkspace.shared.open(URL(string: "https://github.com/jeremymorrison77/live-ai-usage-widget/releases/latest")!)
            }
        }
    }
    /// A plain-text report of the app's state and recent activity, for the user to send if something goes wrong.
    func diagnosticReport() async -> String {
        let settings = self.settings, status = self.status
        let tools: [String] = await Task.detached {
            ["claude", "codex"].map { provider in
                let name = WidgetStatus.name(provider)
                guard let binary = try? UsageReader.find(provider) else { return name + ": not installed" }
                let signed = UsageReader.signedIn(provider, directory: FileManager.default.temporaryDirectory)
                return name + ": " + Diagnostics.clean(binary) + " · " + Diagnostics.toolVersion(binary) + " · signed in " + (signed.map { $0 ? "yes" : "no" } ?? "unknown")
            }
        }.value
        let accounts = ["claude", "codex"].map { provider -> String in
            let name = WidgetStatus.name(provider)
            guard settings.enabled.contains(provider) else { return name + ": not connected" }
            let usage = status?.usage?[provider]
            let refresh = usage?.refresh
            let result = refresh?.status == .failed ? "last check failed (\(refresh?.failureReason?.rawValue ?? "unknown"))" : "ok"
            let readings = usage?.windows.map(\.window).joined(separator: ", ") ?? "none"
            let reading = usage?.observedAt.map(Diagnostics.stamp) ?? "never"
            let attempt = refresh?.lastAttemptAt.map(Diagnostics.stamp) ?? "never"
            return "\(name): \(result) · readings \(readings) · last reading \(reading) · last try \(attempt)"
        }
        let path = Bundle.main.bundlePath
        let hidden = path.contains("/AppTranslocation/") ? " (hidden copy: move to Applications)" : ""
        let login = SMAppService.mainApp.status == .enabled ? "on" : "off"
        let updates = settings.autoUpdates ? "on" : "off"
        let dates = settings.usDates ? "US" : "European"
        var lines: [String] = []
        lines.append("Live AI Usage Widget diagnostic report · \(Diagnostics.stamp(Date()))")
        lines.append("No account names, emails, passwords or sign-in codes are included.")
        lines.append("")
        lines.append("App: version \(Self.version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Running from: \(Diagnostics.clean(path))\(hidden)")
        lines.append("Open at login: \(login) · automatic updates: \(updates)")
        lines.append("Settings: style \(settings.style) · check every \(settings.refreshMinutes) min · \(dates) dates")
        lines.append("")
        lines.append("Tools:")
        lines += tools
        lines.append("")
        lines.append("Accounts:")
        lines += accounts
        lines.append("")
        lines.append("Activity (past 3 days):")
        lines.append(Diagnostics.contents())
        return lines.joined(separator: "\n")
    }
    /// Asks where to save the report (the Desktop by default) and writes it there.
    func saveDiagnosticReport() {
        Task {
            let report = await diagnosticReport()
            let panel = NSSavePanel()
            let day = DateFormatter(); day.dateFormat = "MM-dd-yyyy"
            panel.nameFieldStringValue = "Live AI Usage Widget report " + day.string(from: Date()) + ".txt"
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            panel.allowedContentTypes = [.plainText]
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try report.write(to: url, atomically: true, encoding: .utf8); NSWorkspace.shared.activateFileViewerSelecting([url]) }
            catch { message = "Couldn't save the report. Try another folder." }
        }
    }
    static func changed(_ old: WidgetStatus?, _ new: WidgetStatus?) -> Bool {
        ["claude", "codex"].contains { provider in
            let a = old?.usage?[provider], b = new?.usage?[provider]
            return a?.observedAt != b?.observedAt || a?.refresh?.status != b?.refresh?.status || a?.refresh?.lastAttemptAt != b?.refresh?.lastAttemptAt
        }
    }
    /// Screens never wait on Terminal: they use the common places plus the last background answer.
    func installed(_ provider: String) -> Bool { (try? UsageReader.find(provider, askShell: false)) != nil }
    /// Asks Terminal in the background where each tool lives, then redraws.
    func lookUpTools() {
        Task.detached {
            for provider in ["claude", "codex"] { _ = try? UsageReader.find(provider) }
            await MainActor.run { self.objectWillChange.send() }
        }
    }
    /// The one name used for each account everywhere: menus, buttons, settings, widget and docs.
    func toolName(_ provider: String) -> String { WidgetStatus.name(provider) }
    /// Turns an account on and does whatever is missing: install, browser sign-in, then a fresh reading.
    func connect(_ provider: String) {
        Diagnostics.log(toolName(provider) + ": Connect clicked")
        connecting.insert(provider)
        if !settings.enabled.contains(provider) {
            settings.enabled = ["claude", "codex"].filter { $0 == provider || settings.enabled.contains($0) }
            settings.generation = UUID().uuidString
            save()
        }
        let probe = self.probe
        Task {
            if !installed(provider) {
                await installNow(provider)
                guard installed(provider) else { connecting.remove(provider); return }
            }
            working[provider] = "Checking sign-in…"
            try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            let signed = await Task.detached { UsageReader.signedIn(provider, directory: probe) }.value
            working[provider] = nil
            signedIn[provider] = signed
            Diagnostics.log(toolName(provider) + ": signed in " + (signed.map { $0 ? "yes" : "no" } ?? "unknown"))
            if signed == true { checkConnection([provider]) } else { signIn(provider) }
        }
    }
    /// Only stops showing this account; the official tool stays signed in.
    func disconnect(_ provider: String) {
        Diagnostics.log(toolName(provider) + ": Disconnect clicked")
        settings.enabled.removeAll { $0 == provider }
        save()
        message = ""
    }
    /// First launch: turn on and connect any account whose official tool is installed and signed in.
    func autoDetect() {
        guard !settings.autoDetected, !autoDetecting else { return }
        autoDetecting = true
        let probe = self.probe
        Task {
            defer { autoDetecting = false }
            try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            var found: [String] = []
            for provider in ["claude", "codex"] where installed(provider) {
                connecting.insert(provider)
                working[provider] = "Checking sign-in…"
                if await Task.detached(operation: { UsageReader.signedIn(provider, directory: probe) }).value == true { found.append(provider) }
                working[provider] = nil
            }
            connecting.subtract(["claude", "codex"].filter { !found.contains($0) })
            Diagnostics.log("First launch: found signed in " + (found.isEmpty ? "none" : found.map(toolName).joined(separator: ", ")))
            // Marked done only once finished: a copy that quits mid-check (Move to Applications) leaves it to the moved copy.
            settings.autoDetected = true
            if !found.isEmpty { settings.enabled = found }
            save()
            guard !found.isEmpty else { return }
            checkConnection(found)
        }
    }
    private var autoDetecting = false
    func isConnected(_ provider: String) -> Bool {
        // A rate-limited check still counts as connected while the last reading is fresh.
        let usage = status?.usage?[provider]
        return (usage?.refresh?.status == .ok || usage?.refresh?.failureReason == .rateLimited) && usage?.isStale(at: Date()) == false
    }
    /// Provider → what is happening right now, shown in the Connect window.
    @Published var working: [String: String] = [:]
    /// Accounts between a Connect click and the reading that follows it.
    @Published var connecting: Set<String> = []
    private var refreshAgain = false
    private var forceAgain = false
    @Published var checkingUsage = false
    private var checkStarted = Date.distantPast
    private var pendingSave: Task<Void, Never>?
    /// Settings apply as they change; a short pause lets a color drag or typing finish first.
    func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }
    private var lastSummary = ""
    @Published var signInLink: [String: URL] = [:]
    @Published var signedIn: [String: Bool] = [:]
    private var probe: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveAIUsageWidget").appendingPathComponent("probe")
    }
    func updateSignedIn(_ provider: String) {
        let probe = self.probe
        Task {
            try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            let value = await Task.detached { UsageReader.signedIn(provider, directory: probe) }.value
            signedIn[provider] = value
        }
    }
    func install(_ provider: String) { Task { await installNow(provider) } }
    func installNow(_ provider: String) async {
        // Never add a second copy: look again everywhere, including the person's Terminal setup, first.
        UsageReader.forgetLookups()
        if await Task.detached(operation: { (try? UsageReader.find(provider)) != nil }).value {
            Diagnostics.log(toolName(provider) + ": already installed, install skipped")
            objectWillChange.send()
            return
        }
        let claude = provider == "claude"
        working[provider] = "Installing…"
        Diagnostics.log(toolName(provider) + ": install started")
        // Claude's official installer, or OpenAI's signed Codex release for Apple Silicon, run in the background.
        let command = claude ? "curl -fsSL https://claude.ai/install.sh | bash"
            : "set -e; d=$(mktemp -d); curl -fsSL https://github.com/openai/codex/releases/latest/download/codex-aarch64-apple-darwin.tar.gz -o \"$d/codex.tgz\"; tar -xzf \"$d/codex.tgz\" -C \"$d\"; mkdir -p \"$HOME/.local/bin\"; mv \"$d/codex-aarch64-apple-darwin\" \"$HOME/.local/bin/codex\"; chmod 755 \"$HOME/.local/bin/codex\"; rm -rf \"$d\""
        let ok = await Task.detached { () -> Bool in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
        }.value
        working[provider] = nil
        let place = (try? UsageReader.find(provider, askShell: false)).map { ", found at " + $0 } ?? ", not found"
        Diagnostics.log("\(toolName(provider)): install \(ok ? "finished" : "failed")\(place)")
        message = ok ? "" : "Couldn't install " + toolName(provider) + ". Check your internet connection and try again."
        objectWillChange.send()
    }
    func signIn(_ provider: String) {
        working[provider] = "Finish signing in in your browser…"
        signInLink[provider] = nil
        Diagnostics.log(toolName(provider) + ": browser sign-in started")
        let probe = self.probe
        Task {
            try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            let failure: String? = await Task.detached {
                do {
                    try UsageReader.signIn(provider, directory: probe) { url in
                        Diagnostics.log(WidgetStatus.name(provider) + ": sign-in page " + (url.host ?? "unknown"))
                        Task { @MainActor in self.signInLink[provider] = url }
                    }
                    return nil
                } catch { return (error as? ReaderFailure)?.reason ?? "unavailable" }
            }.value
            working[provider] = nil
            signInLink[provider] = nil
            Diagnostics.log(toolName(provider) + ": browser sign-in " + (failure.map { "failed (" + $0 + ")" } ?? "finished"))
            if failure != nil {
                connecting.remove(provider)
                message = failure == "usage_read_timed_out" ? "Sign-in timed out. Try again." : "Sign-in didn't finish. Try again."
                return
            }
            updateSignedIn(provider)
            checkConnection([provider], reset: [provider])
        }
    }
    /// Reads usage again for every account, after preparing the ones just connected.
    func checkConnection(_ providers: [String], reset: Set<String> = []) {
        let probe = self.probe
        let claude = providers.contains("claude") && settings.enabled.contains("claude")
        Task {
            // Claude Code asks once whether to trust the folder it runs in; answer it for the app's own empty folder.
            if claude && (try? UsageReader.find("claude", askShell: false)) != nil {
                working["claude"] = "Checking…"
                try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
                let trust: String = await Task.detached {
                    do { try UsageReader.trustProbe(directory: probe); return "ok" } catch { return (error as? ReaderFailure)?.reason ?? "unavailable" }
                }.value
                Diagnostics.log("Claude Code: folder trust " + trust)
                working["claude"] = nil
            }
            // An explicit check starts a new collection generation; timer retries keep their backoff.
            settings.generation = UUID().uuidString
            save(reset: reset)
            refresh()
        }
    }
    func refresh(force: Bool = false) {
        // A check the user asked for shows on the widget at once, even if a regular check is still running.
        if force && !checkingUsage {
            checkingUsage = true
            checkStarted = Date()
            // The widget's own button already marked the check and redrew itself; only the menu needs to.
            if StatusStore.load()?.checking(at: Date()) != true {
                try? StatusStore.setChecking(Date())
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        // A request during a check runs once that check ends, so a new connection is never skipped.
        guard !busy else { refreshAgain = true; forceAgain = forceAgain || force; return }
        let settings = self.settings
        // Nothing to check until an account is turned on; stay quiet instead of reporting.
        guard !settings.enabled.isEmpty else { message = ""; connecting = []; return }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveAIUsageWidget")
        // Background checks stay quiet so the window never shifts while it is open.
        busy = true
        Task {
            let payload: Data? = await Task.detached {
                try? Collector.run(root: root, generation: settings.generation, providers: settings.enabled, interval: Double(settings.refreshMinutes) * 60, force: force)
            }.value
            defer {
                busy = false
                if force {
                    // Keep "Checking…" up for at least two seconds so a quick check is still seen.
                    let wait = max(0, 2 - Date().timeIntervalSince(checkStarted))
                    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                        guard let self else { return }
                        self.checkingUsage = false
                        try? StatusStore.setChecking(nil)
                        self.status = StatusStore.load()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
                if refreshAgain { refreshAgain = false; let again = forceAgain; forceAgain = false; refresh(force: again) }
            }
            guard settings.generation == self.settings.generation else { refreshAgain = true; return }
            connecting.subtract(settings.enabled)
            guard let payload else { Diagnostics.log("Check: couldn't run"); message = "Couldn't check usage. Make sure Claude Code or ChatGPT Codex is installed and signed in."; return }
            do {
                let before = status
                status = try StatusStore.publishUsage(input: payload)
                let summary = settings.enabled.map { provider -> String in
                    let usage = status?.usage?[provider]
                    let result = usage?.refresh?.status == .failed ? "failed (\(usage?.refresh?.failureReason?.rawValue ?? "unknown"))" : "ok"
                    let readings = usage?.windows.map(\.window).joined(separator: ", ") ?? "no readings"
                    return "\(toolName(provider)) \(result) · \(readings)"
                }.joined(separator: " | ")
                // Only changes are written, so a quiet day adds a line or two, not hundreds.
                if summary != lastSummary { Diagnostics.log("Check: " + summary); lastSummary = summary }
                // macOS limits how often a background app may redraw widgets; spend that only on real changes.
                if !force && Self.changed(before, status) { WidgetCenter.shared.reloadAllTimelines() }
                message = status?.usageFailureText() ?? status?.pausedText() ?? ""
            } catch { message = "Couldn't save the readings. Try reinstalling the app." }
        }
    }
}

@main struct UsageApp: App {
    init() {
        if CommandLine.arguments.contains("--self-check") {
            do {
                let file = try StatusStore.fileURL().deletingLastPathComponent().appendingPathComponent("self-check-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: file) }
                try Data("ok".utf8).write(to: file, options: .atomic)
                guard try Data(contentsOf: file) == Data("ok".utf8) else { exit(1) }
                print("Shared app-group read/write passed")
                exit(0)
            } catch { print("Shared app-group unavailable"); exit(1) }
        }
    }
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = UsageModel()
    var body: some Scene {
        // The setup window is the app's only window; closing it leaves collection running.
        Window("Live AI Usage Widget Settings", id: "main") {
            SettingsView(model: model)
                .onAppear { model.refresh() }
                .modifier(WidgetLinks())
                .handlesExternalEvents(preferring: ["settings"], allowing: ["settings"])
        }
        // Only the widget's gear opens this window; its refresh button checks usage quietly.
        .handlesExternalEvents(matching: ["settings"])
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .appSettings) { SettingsCommand() } }
        // Menu bar icon instead of a Dock icon. Its label stays alive, so it also opens the window on request.
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: MenuIcon.image).modifier(WidgetLinks())
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: UsageModel
    @Environment(\.openWindow) private var openWindow
    private func open(connecting provider: String? = nil) {
        URLRouter.shared.connect = provider
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
    var body: some View {
        if let update = model.update {
            Button { model.installUpdate() } label: { Label(model.updateStatus == "Downloading…" ? "Updating…" : "Update to version " + update.version, systemImage: "arrow.down.circle.fill") }
                .disabled(model.updateStatus == "Downloading…")
            Divider()
        }
        // One line per account in the settings window's words. Every line has an icon so all text lines up.
        ForEach(["claude", "codex"], id: \.self) { provider in
            let name = WidgetStatus.name(provider)
            let installed = model.installed(provider)
            let connected = model.settings.enabled.contains(provider) && model.isConnected(provider)
            if let busy = model.working[provider] ?? (model.connecting.contains(provider) ? "Connecting…" : nil) {
                Button { open() } label: { Label(name + " · " + busy, systemImage: "hourglass") }
            } else if !installed {
                Button { model.install(provider) } label: { Label(name + " · Install", systemImage: "arrow.down.circle") }
            } else if connected {
                Button { open() } label: { Label { Text(name + " · Connected") } icon: { Image(nsImage: MenuIcon.check) } }
            } else {
                Button { open(); model.connect(provider) } label: { Label(name + " · Connect", systemImage: "person.crop.circle") }
            }
        }
        Divider()
        Button { open() } label: { Label("Settings…", systemImage: "gearshape") }
        Button { model.refresh(force: true) } label: { Label(model.checkingUsage ? "Checking usage…" : "Check usage now", systemImage: model.checkingUsage ? "hourglass" : "arrow.clockwise") }
            .disabled(model.settings.enabled.isEmpty || model.checkingUsage)
        Divider()
        Button { NSApp.terminate(nil) } label: { Label("Quit Live AI Usage Widget", systemImage: "power") }
    }
}

/// The app icon's ring and pulse line, drawn as a template so macOS tints it for the menu bar.
enum MenuIcon {
    /// A green check that keeps its color in the menu (not a template image).
    static let check: NSImage = {
        let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemGreen])
        let image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Connected")?.withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }()
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 7.5, startAngle: 120, endAngle: 60, clockwise: false)
            ring.lineWidth = 1.6; ring.lineCapStyle = .round; ring.stroke()
            let pulse = NSBezierPath()
            pulse.move(to: NSPoint(x: 3.6, y: 9.4)); pulse.line(to: NSPoint(x: 6.6, y: 9.4)); pulse.line(to: NSPoint(x: 7.8, y: 6.9))
            pulse.line(to: NSPoint(x: 9.6, y: 11.6)); pulse.line(to: NSPoint(x: 11.0, y: 8.5)); pulse.line(to: NSPoint(x: 14.4, y: 8.5))
            pulse.lineWidth = 1.5; pulse.lineCapStyle = .round; pulse.lineJoinStyle = .round; pulse.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// One account: its state as plain text, then one standard button for the next step, as in System Settings.
struct AccountRow: View {
    @ObservedObject var model: UsageModel
    let provider: String
    var body: some View {
        let name = WidgetStatus.name(provider)
        let installed = model.installed(provider)
        let connected = model.settings.enabled.contains(provider) && model.isConnected(provider)
        let busy = model.working[provider] ?? (model.connecting.contains(provider) ? "Connecting…" : nil)
        let link = busy != nil ? model.signInLink[provider] : nil
        // Why the last check failed, shown beside the button that fixes it.
        let problem = busy == nil && installed && !connected && model.settings.enabled.contains(provider) ? model.status?.usage?[provider]?.refresh?.failureReason : nil
        HStack {
            Text(name)
            Spacer()
            // The spinner sits beside the account that is working.
            if busy != nil {
                ProgressView().controlSize(.small)
                Text(installed ? "Connecting…" : "Installing…").foregroundStyle(.secondary)
            } else if connected {
                Label("Connected", systemImage: "checkmark.circle.fill").labelStyle(StatusLabel(color: .green))
            } else if let problem {
                Label(Self.status(problem), systemImage: "exclamationmark.circle.fill").labelStyle(StatusLabel(color: .orange))
            } else if !installed {
                Text("Not installed").foregroundStyle(.secondary)
            }
            if link != nil || busy == nil {
                Button {
                    if let link { NSWorkspace.shared.open(link) }
                    else if !installed { model.install(provider) }
                    else if problem == .cliUpdateRequired { Task { await model.installNow(provider); model.connect(provider) } }
                    else if connected { model.disconnect(provider) } else { model.connect(provider) }
                } label: {
                    if link != nil { Text("Open Sign-In Page") }
                    else if !installed { Text("Install") }
                    else if connected { Text("Disconnect") }
                    else if let problem { Text(Self.title(problem)) }
                    else { Text("Connect") }
                }
            }
        }
    }
    /// Short reason shown beside the button.
    private static func status(_ problem: UsageFailureReason) -> String {
        switch problem {
        case .cliUpdateRequired: return "Needs update"
        case .signInRequired: return "Signed out"
        case .interactiveSetupRequired: return "Setup unfinished"
        default: return "Couldn't connect"
        }
    }
    private static func title(_ problem: UsageFailureReason) -> String {
        switch problem {
        case .cliUpdateRequired: return "Update"
        case .signInRequired: return "Sign In"
        case .interactiveSetupRequired: return "Finish Setup"
        default: return "Try Again"
        }
    }
}

/// Colored symbol, plain secondary text: how System Settings shows a state.
struct StatusLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.foregroundStyle(color); configuration.title.foregroundStyle(.secondary) }
    }
}

struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Settings…") { openWindow(id: "main") }.keyboardShortcut(",") }
}

struct SettingsView: View {
    @ObservedObject var model: UsageModel
    /// Set only by the README picture renderer: shows the defaults instead of this Mac's login state.
    nonisolated(unsafe) static var sample = false
    @State private var launchAtLogin = SettingsView.sample || SMAppService.mainApp.status == .enabled
    @State private var widgetsPlaced: Int?
    @State private var showWidgetHelp = false
    @State private var showSetupHelp = false
    @Environment(\.dismissWindow) private var dismissWindow
    private static var launchHandled = false
    // Setup help hides itself once every step is done; Setup help brings it back.
    private var setupDone: Bool { anyConnected && (widgetsPlaced ?? 0) > 0 }
    private var anyConnected: Bool {
        model.settings.enabled.contains { model.status?.usage?[$0]?.refresh?.status == .ok && model.status?.usage?[$0]?.isStale(at: Date()) == false }
    }
    static var settingsWindows: [NSWindow] { NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true } }
    private func checkWidgets() {
        guard !Self.sample else { return }
        WidgetCenter.shared.getCurrentConfigurations { result in
            let count = (try? result.get())?.count
            DispatchQueue.main.async {
                widgetsPlaced = count
                // Once fully set up, a fresh launch (such as at login, or after an update started from the menu) stays in
                // the menu bar. The window is kept invisible until this is decided, so it never flashes.
                guard !Self.launchHandled else { return }
                Self.launchHandled = true
                let reopen = UserDefaults.standard.bool(forKey: "reopenSettingsAfterUpdate")
                UserDefaults.standard.removeObject(forKey: "reopenSettingsAfterUpdate")
                if !reopen && !model.settings.enabled.isEmpty && (count ?? 0) > 0 && !URLRouter.shared.settingsRequested {
                    dismissWindow(id: "main")
                }
                Self.settingsWindows.forEach { $0.alphaValue = 1 }
            }
        }
    }
    private func step(_ number: Int, _ title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? Color.green : Color.secondary).font(.title3)
            Text(title)
        }
    }
    var body: some View {
        Form {
            if !setupDone || showSetupHelp {
            Section {
                HStack {
                    step(1, "Connect your accounts", done: anyConnected)
                    Spacer()
                }
                HStack {
                    step(2, "Add “Live AI Usage Widget” to your desktop", done: (widgetsPlaced ?? 0) > 0)
                    Spacer()
                    if (widgetsPlaced ?? 0) > 0 { Text("On desktop").foregroundStyle(.secondary) }
                    else { Button("Show Me How") { showWidgetHelp = true } }
                }
            } header: { Text("Setup help") }
            }
            Section("General") {
                HStack {
                    Text("Version " + UsageModel.version)
                    Spacer()
                    if !model.updateStatus.isEmpty { Text(model.updateStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Button {
                        if model.update != nil { model.installUpdate() } else { model.checkForUpdates(manual: true) }
                    } label: {
                        Group {
                            if let update = model.update { Text("Update to " + update.version) }
                            else { Text("Check for Updates") }
                        }
                    }
                    .disabled(model.updateStatus == "Downloading…" || model.updateStatus == "Checking…")
                }
                Toggle("Check for updates automatically", isOn: $model.settings.autoUpdates)
                Toggle("Open at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { model.message = "Couldn't change Open at login. Check Login Items in System Settings."; launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            }
            Section("Accounts") {
                ForEach(["claude", "codex"], id: \.self) { provider in
                    AccountRow(model: model, provider: provider)
                }
            }
            Section("Appearance") {
                Picker("Style", selection: $model.settings.style) {
                    Text("Clean").tag("clean"); Text("Solar").tag("solar")
                }
                Picker("Date format", selection: $model.settings.usDates) { Text("US").tag(true); Text("European").tag(false) }
                Toggle("Usage colors", isOn: $model.settings.usageColors)
                HStack {
                    percentField(model.settings.highThreshold) { model.settings.highThreshold = min(100, max(model.settings.lowThreshold+1, $0)) }
                    Text("or more remaining"); Spacer(); colorPicker($model.settings.highColor)
                }
                HStack {
                    percentField(model.settings.lowThreshold+1) { model.settings.lowThreshold = max(0, min(model.settings.highThreshold-1, $0-1)) }
                    Text("to \(Int(model.settings.highThreshold)-1)% remaining"); Spacer(); colorPicker($model.settings.middleColor)
                }
                HStack {
                    percentField(model.settings.lowThreshold) { model.settings.lowThreshold = max(0, min(model.settings.highThreshold-1, $0)) }
                    Text("or less remaining"); Spacer(); colorPicker($model.settings.lowColor)
                }
            }
            Section("Updates") {
                HStack {
                    Text("Check every")
                    Spacer()
                    NumberField(value: Double(model.settings.refreshMinutes), suffix: "", width: 56) {
                        model.settings.refreshMinutes = Int(min(1440, max(1, $0)))
                    }
                    Stepper("", value: $model.settings.refreshMinutes, in: 1...1440).labelsHidden()
                    Text(model.settings.refreshMinutes == 1 ? "minute" : "minutes")
                }
            }
            if !metricChoices.isEmpty {
            Section("Small widget readings") {
                ForEach(metricChoices, id: \.self) { key in
                    Toggle(metricTitle(key), isOn: Binding(get: { !model.settings.hiddenSmallMetrics.contains(key) }, set: { on in
                        model.settings.hiddenSmallMetrics.removeAll { $0 == key }
                        if !on { model.settings.hiddenSmallMetrics.append(key) }
                    }))
                }
                // Limits the account's plan doesn't have stay listed, grayed out, so nothing seems to be missing.
                ForEach(missingChoices, id: \.self) { key in
                    Toggle(isOn: .constant(false)) {
                        HStack { Text(metricTitle(key)); Spacer(); Text("Not included in your plan").font(.caption) }
                    }.disabled(true)
                }
                Text("Up to five readings, in provider order. Medium and large show every available reading.").font(.caption).foregroundStyle(.secondary)
            }
            }
            Section("Troubleshooting") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Something not working?")
                        Text("Save a report and send it to the developer. It has no account names, emails or passwords.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Save report…") { model.saveDiagnosticReport() }
                }
            }
        }.formStyle(.grouped)
            .safeAreaInset(edge: .bottom, spacing: 0) {
            // Settings apply as they change, so there is no Save button.
            if setupDone || !model.message.isEmpty {
            VStack(spacing: 6) {
                if setupDone {
                    Button { showSetupHelp.toggle() } label: { Text(showSetupHelp ? "Hide Setup Help" : "Setup Help") }
                }
                if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.padding(.vertical, 12).frame(maxWidth: .infinity).background(.bar)
            }
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 640)
            .onChange(of: model.settings) { old, new in
                model.saveSoon()
                // A new check interval or account choice takes effect right away.
                if old.refreshMinutes != new.refreshMinutes { model.refresh() }
            }
            .background(WindowSizeMemory(name: "Settings"))
            .onAppear {
                // Until the launch decides whether to show Settings, keep the window invisible (no flash at login or after updates).
                if !Self.launchHandled { Self.settingsWindows.forEach { $0.alphaValue = 0 } }
                Diagnostics.log("Settings opened (windows: \(NSApp.windows.compactMap { $0.identifier?.rawValue }.joined(separator: ", ")))")
                NSApp.activate(ignoringOtherApps: true); checkWidgets()
                // Nothing is selected when the window opens, not even the first percentage field.
                // macOS puts the cursor in the first text box and scrolls down to it; undo both so the window opens at the top.
                for delay in [0.05, 0.25, 0.6] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        for window in NSApp.windows where window.isVisible {
                            window.makeFirstResponder(nil)
                            if let content = window.contentView { Self.scrollToTop(content) }
                        }
                    }
                }
                // Open at login starts on; after the first launch it follows the user's choice.
                if !model.settings.autoDetected && SMAppService.mainApp.status != .enabled {
                    try? SMAppService.mainApp.register(); launchAtLogin = SMAppService.mainApp.status == .enabled
                }
                model.autoDetect()
            }
            .onReceive(URLRouter.shared.$connect) { provider in
                guard let provider else { return }
                URLRouter.shared.connect = nil
                model.connect(provider)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkWidgets() }
            .sheet(isPresented: $showWidgetHelp) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        // The name comes first, so it is still in view when the widget gallery covers the rest.
                        Text("Search for “Live AI Usage Widget”").font(.headline)
                        Text("macOS doesn't let apps place widgets themselves, so this step is yours.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.bottom, 8)
                    Text("1. Right-click an empty spot on your desktop and choose Edit Widgets.")
                    Text("2. Type Live AI Usage Widget in the search box.")
                    Text("3. Pick a size and drag it onto your desktop, then click Done.")
                    HStack { Spacer(); Button("Done") { showWidgetHelp = false; checkWidgets() }.keyboardShortcut(.defaultAction) }
                }.padding(24).frame(width: 400)
            }
    }
    /// Scrolls the settings list (the window's tallest scroll area) back to its top.
    static func scrollToTop(_ view: NSView) {
        func scrollAreas(_ view: NSView) -> [NSScrollView] { ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollAreas) }
        guard let area = scrollAreas(view).max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }),
              let document = area.documentView else { return }
        let clip = area.contentView
        let top = document.isFlipped ? -area.contentInsets.top : document.bounds.height - clip.bounds.height + area.contentInsets.top
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: top))
        area.reflectScrolledClipView(clip)
    }
    private func percentField(_ value: Double, set: @escaping (Double) -> Void) -> some View {
        PercentField(value: value, commit: set)
    }
    private var metricChoices: [String] {
        model.settings.enabled.flatMap { provider in
            let names = model.status?.usage?[provider]?.windows.map(\.window) ?? WidgetStatus.expectedWindows(provider)
            return names.map { UsageHistory.key(provider, $0) }
        }
    }
    private var missingChoices: [String] {
        model.settings.enabled.flatMap { provider in
            WidgetStatus.notInPlan(provider, have: model.status?.usage?[provider]?.windows.map(\.window) ?? []).map { UsageHistory.key(provider, $0) }
        }
    }
    private func metricTitle(_ key: String) -> String {
        key.replacingOccurrences(of: "claude:", with: WidgetStatus.name("claude") + " · ").replacingOccurrences(of: "codex:", with: WidgetStatus.name("codex") + " · ")
    }
    private func colorPicker(_ hex: Binding<String>) -> some View {
        ColorPicker("Color", selection: Binding(get: { WidgetSettings.color(hex: hex.wrappedValue) }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
            hex.wrappedValue = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
        }), supportsOpacity: false).labelsHidden()
    }
}

@MainActor final class URLRouter: ObservableObject {
    static let shared = URLRouter()
    @Published var url: URL? {
        didSet {
            guard let url else { return }
            if url.host == "settings" { settings = true } else if url.host == "refresh" { refresh = true }
        }
    }
    @Published var settings = false { didSet { if settings { settingsRequested = true } } }
    /// Set once anything asks for the window, so a quiet start never hides a window the user wanted.
    var settingsRequested = false
    @Published var refresh = false
    /// A provider whose Connect window should open next time the settings window shows.
    @Published var connect: String?
}

struct WidgetLinks: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onOpenURL { URLRouter.shared.url = $0 }
            .onReceive(URLRouter.shared.$settings) { requested in
                guard requested else { return }
                URLRouter.shared.settings = false
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        let path = Bundle.main.bundlePath
        let hidden = path.contains("/AppTranslocation/") ? " (hidden copy)" : ""
        Diagnostics.startLaunch("version \(UsageModel.version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · running from \(path)\(hidden)")
        guard Mover.shouldOffer() else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Move to Applications?"
            alert.informativeText = "Live AI Usage Widget works best from your Applications folder. Opened from Downloads, sign-in, Open at login and updates may not work. Any older copy in Applications goes to the Trash."
            alert.addButton(withTitle: "Move to Applications")
            alert.addButton(withTitle: "Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do { _ = try Mover.moveToApplications(); Diagnostics.log("Moved to Applications"); NSApp.terminate(nil) }
            catch {
                Diagnostics.log("Move to Applications failed: \(error)")
                let failed = NSAlert()
                failed.messageText = "Couldn't move the app"
                failed.informativeText = "Quit it from the menu bar, drag Live AI Usage Widget into Applications in Finder, then open it from there."
                failed.runModal()
            }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) { URLRouter.shared.url = urls.first }
    func applicationWillTerminate(_ notification: Notification) { ChildProcess.stopAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    // Opening the app again from Applications shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        URLRouter.shared.settings = true
        return true
    }
}

/// Remembers the settings window's size and position between openings and launches.
struct WindowSizeMemory: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView { Tracker(name: name) }
    func updateNSView(_ view: NSView, context: Context) {}
    final class Tracker: NSView {
        let name: String
        init(name: String) { self.name = name; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.frameAutosaveName != name else { return }
            // Restore after SwiftUI's own first layout, then keep saving every change.
            DispatchQueue.main.async { [name] in
                window.setFrameUsingName(name)
                window.setFrameAutosaveName(name)
            }
        }
    }
}

struct PercentField: View {
    let value: Double
    let commit: (Double) -> Void
    var body: some View { NumberField(value: value, suffix: "%", width: 42, commit: commit) }
}

/// A number box that never takes the cursor by itself: it shows the value, and becomes editable only when clicked.
/// (macOS otherwise puts the cursor in the first box when the window opens and scrolls down to it.)
struct NumberField: View {
    let value: Double
    let suffix: String
    let width: CGFloat
    let commit: (Double) -> Void
    @State private var text = ""
    @State private var editing = false
    @FocusState private var focused: Bool
    private var shown: String { "\(Int(value))" + suffix }
    private func finish() {
        if let number = Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)), number.isFinite { commit(number.rounded()) }
        editing = false
    }
    var body: some View {
        if editing {
            TextField(suffix, text: $text).labelsHidden().textFieldStyle(.roundedBorder).frame(width: width).multilineTextAlignment(.center)
                .focused($focused)
                .onAppear { text = shown; DispatchQueue.main.async { focused = true } }
                .onSubmit { finish() }
                .onChange(of: focused) { _, active in if !active { finish() } }
        } else {
            Text(shown).frame(width: width - 6, height: 18).padding(.horizontal, 3).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
                .contentShape(Rectangle())
                .onTapGesture { editing = true }
                .accessibilityAddTraits(.isButton)
        }
    }
}
