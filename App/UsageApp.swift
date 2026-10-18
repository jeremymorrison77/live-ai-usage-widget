import AppKit
import SwiftUI
import WidgetKit
import ServiceManagement
import Darwin
import Combine

@MainActor final class UsageModel: ObservableObject {
    @Published var settings = WidgetSettings.load()
    @Published var status = StatusStore.load()
    @Published var busy = false
    @Published var message = ""
    var timer: Timer?
    private var links: AnyCancellable?
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        links = URLRouter.shared.$refresh.sink { [weak self] requested in
            guard requested else { return }
            DispatchQueue.main.async { URLRouter.shared.refresh = false; self?.refresh() }
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
            message = "Saved"
        } catch { message = "Couldn't save settings. Check the color percentages, or reinstall the app." }
    }
    func installed(_ provider: String) -> Bool { (try? UsageReader.find(provider)) != nil }
    /// The one name used for each account everywhere: menus, buttons, settings, widget and docs.
    func toolName(_ provider: String) -> String { WidgetStatus.name(provider) }
    /// Turns an account on and does whatever is missing: install, browser sign-in, then a fresh reading.
    func connect(_ provider: String) {
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
            if signed == true { checkConnection([provider]) } else { signIn(provider) }
        }
    }
    /// Only stops showing this account; the official tool stays signed in.
    func disconnect(_ provider: String) {
        settings.enabled.removeAll { $0 == provider }
        save()
        message = ""
    }
    /// First launch: turn on and connect any account whose official tool is installed and signed in.
    func autoDetect() {
        guard !settings.autoDetected else { return }
        settings.autoDetected = true
        save()
        let probe = self.probe
        Task {
            try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            var found: [String] = []
            for provider in ["claude", "codex"] where installed(provider) {
                connecting.insert(provider)
                working[provider] = "Checking sign-in…"
                if await Task.detached(operation: { UsageReader.signedIn(provider, directory: probe) }).value == true { found.append(provider) }
                working[provider] = nil
            }
            connecting.subtract(["claude", "codex"].filter { !found.contains($0) })
            guard !found.isEmpty else { return }
            settings.enabled = found
            checkConnection(found)
        }
    }
    func isConnected(_ provider: String) -> Bool {
        status?.usage?[provider]?.refresh?.status == .ok && status?.usage?[provider]?.isStale(at: Date()) == false
    }
    /// Provider → what is happening right now, shown in the Connect window.
    @Published var working: [String: String] = [:]
    /// Accounts between a Connect click and the reading that follows it.
    @Published var connecting: Set<String> = []
    private var refreshAgain = false
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
        let claude = provider == "claude"
        working[provider] = "Installing…"
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
        message = ok ? "" : "Couldn't install " + toolName(provider) + ". Check your internet connection and try again."
        objectWillChange.send()
    }
    func signIn(_ provider: String) {
        working[provider] = "Finish signing in in your browser…"
        signInLink[provider] = nil
        let probe = self.probe
        Task {
            try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            let failure: String? = await Task.detached {
                do {
                    try UsageReader.signIn(provider, directory: probe) { url in Task { @MainActor in self.signInLink[provider] = url } }
                    return nil
                } catch { return (error as? ReaderFailure)?.reason ?? "unavailable" }
            }.value
            working[provider] = nil
            signInLink[provider] = nil
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
            if claude && (try? UsageReader.find("claude")) != nil {
                working["claude"] = "Checking…"
                try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
                _ = await Task.detached { try? UsageReader.trustProbe(directory: probe) }.value
                working["claude"] = nil
            }
            // An explicit check starts a new collection generation; timer retries keep their backoff.
            settings.generation = UUID().uuidString
            save(reset: reset)
            refresh()
        }
    }
    func refresh(force: Bool = false) {
        // A request during a check runs once that check ends, so a new connection is never skipped.
        guard !busy else { refreshAgain = true; return }
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
                if refreshAgain { refreshAgain = false; refresh() }
            }
            guard settings.generation == self.settings.generation else { refreshAgain = true; return }
            connecting.subtract(settings.enabled)
            guard let payload else { message = "Couldn't check usage. Make sure Claude Code or ChatGPT Codex is installed and signed in."; return }
            do {
                status = try StatusStore.publishUsage(input: payload)
                WidgetCenter.shared.reloadAllTimelines()
                message = status?.usageFailureText() ?? ""
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
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
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
        Button { model.refresh(force: true) } label: { Label("Check now", systemImage: "arrow.clockwise") }.disabled(model.settings.enabled.isEmpty)
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

/// One account: install state beside a single Connect / Connected button that turns it on and off.
struct AccountRow: View {
    @ObservedObject var model: UsageModel
    let provider: String
    @State private var hovering = false
    var body: some View {
        let name = WidgetStatus.name(provider)
        let installed = model.installed(provider)
        let connected = model.settings.enabled.contains(provider) && model.isConnected(provider)
        let busy = model.working[provider] ?? (model.connecting.contains(provider) ? "Connecting…" : nil)
        let link = busy != nil ? model.signInLink[provider] : nil
        // Why the last check failed, shown as the button itself.
        let problem = busy == nil && installed && !connected && model.settings.enabled.contains(provider) ? model.status?.usage?[provider]?.refresh?.failureReason : nil
        // One line only: every state, including install, problems and the sign-in link, is the button.
        HStack {
                Text(name)
                Spacer()
                Button {
                    if let link { NSWorkspace.shared.open(link) }
                    else if !installed { model.install(provider) }
                    else if problem == .cliUpdateRequired { Task { await model.installNow(provider); model.connect(provider) } }
                    else if connected { model.disconnect(provider) } else { model.connect(provider) }
                } label: {
                    Group {
                        if link != nil { Label("Open sign-in page", systemImage: "safari") }
                        // The spinner sits inside the button of the account that is working.
                        else if busy != nil {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                                Text(installed ? "Connecting…" : "Installing…")
                            }
                        }
                        else if !installed { Label("Install", systemImage: "arrow.down.circle") }
                        else if connected && hovering { Label("Disconnect", systemImage: "xmark.circle").foregroundStyle(.red) }
                        else if connected { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        else if let problem { Label(Self.title(problem), systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                        else { Label("Connect", systemImage: "person.crop.circle") }
                    // Wide enough for the longest state, "Open sign-in page" with its icon.
                    }.frame(width: 150)
                }
                .disabled(busy != nil && link == nil)
                .onHover { hovering = $0 }
        }
    }
    private static func title(_ problem: UsageFailureReason) -> String {
        switch problem {
        case .cliUpdateRequired: return "Update"
        case .signInRequired: return "Sign in"
        case .interactiveSetupRequired: return "Finish setup"
        default: return "Try again"
        }
    }
}

struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Settings…") { openWindow(id: "main") }.keyboardShortcut(",") }
}

struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var widgetsPlaced: Int?
    @State private var showWidgetHelp = false
    @State private var showSetupHelp = false
    @Environment(\.dismissWindow) private var dismissWindow
    private static var launchHandled = false
    // Get started hides itself once every step is done; Setup help brings it back.
    private var setupDone: Bool { anyConnected && (widgetsPlaced ?? 0) > 0 }
    private var anyConnected: Bool {
        model.settings.enabled.contains { model.status?.usage?[$0]?.refresh?.status == .ok && model.status?.usage?[$0]?.isStale(at: Date()) == false }
    }
    private func checkWidgets() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let count = (try? result.get())?.count
            DispatchQueue.main.async {
                widgetsPlaced = count
                // Once fully set up, a fresh launch (such as at login) stays in the menu bar.
                guard !Self.launchHandled else { return }
                Self.launchHandled = true
                if !model.settings.enabled.isEmpty && (count ?? 0) > 0 && !URLRouter.shared.settingsRequested {
                    dismissWindow(id: "main")
                }
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
                    step(2, "Add the widget to your desktop", done: (widgetsPlaced ?? 0) > 0)
                    Spacer()
                    if (widgetsPlaced ?? 0) > 0 { Text("On desktop").foregroundStyle(.secondary) }
                    else { Button("Show me how") { showWidgetHelp = true } }
                }
            } header: { Text("Get started") }
            }
            Section("General") {
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
                    Text("Clean").tag("clean"); Text("Solar").tag("solar"); Text("Trends").tag("trends")
                }
                Picker("Date format", selection: $model.settings.usDates) { Text("European").tag(false); Text("US").tag(true) }
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
                    TextField("Minutes", value: Binding(get: { model.settings.refreshMinutes }, set: { model.settings.refreshMinutes = min(1440, max(1, $0)) }), format: .number)
                        .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 56).multilineTextAlignment(.center)
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
                Text("Up to five readings, in provider order. Medium and large show every available reading.").font(.caption).foregroundStyle(.secondary)
            }
            }
        }.formStyle(.grouped)
            .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    if setupDone {
                        Button { showSetupHelp.toggle() } label: { Text(showSetupHelp ? "Hide setup help" : "Setup help").frame(width: 130) }
                    }
                    Button {
                        // Finish any number still being typed, then save it with everything else.
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        DispatchQueue.main.async { model.save(); model.refresh() }
                    } label: { Text("Save settings").frame(width: 130) }
                        .keyboardShortcut(.defaultAction)
                }
                // The line keeps its space when empty so messages never move the window's contents.
                Text(model.message.isEmpty ? " " : model.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.padding(.vertical, 14).frame(maxWidth: .infinity).background(.bar)
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 640)
            .background(WindowSizeMemory(name: "Settings"))
            .onAppear {
                NSApp.activate(ignoringOtherApps: true); checkWidgets()
                // Nothing is selected when the window opens, not even the first percentage field.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.windows.filter(\.isVisible).forEach { $0.makeFirstResponder(nil) } }
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
                        Text("Add the widget to your desktop").font(.headline)
                        Text("macOS doesn't let apps place widgets themselves, so this step is yours.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.bottom, 8)
                    Text("1. Right-click an empty spot on your desktop and choose Edit Widgets.")
                    Text("2. Search for Live AI Usage Widget.")
                    Text("3. Pick a size and drag it onto your desktop, then click Done.")
                    HStack { Spacer(); Button("Done") { showWidgetHelp = false; checkWidgets() }.keyboardShortcut(.defaultAction) }
                }.padding(24).frame(width: 400)
            }
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
    func applicationDidFinishLaunching(_ notification: Notification) { signal(SIGPIPE, SIG_IGN) }
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
    @State private var text = ""
    @FocusState private var focused: Bool
    private func finish() {
        if let number = Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)), number.isFinite { commit(number.rounded()) }
        text = "\(Int(value))%"
    }
    var body: some View {
        TextField("%", text: $text).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 42).multilineTextAlignment(.center).focused($focused)
            .onAppear { text = "\(Int(value))%" }.onSubmit { finish() }
            .onChange(of: focused) { _, active in if !active { finish() } }
            .onChange(of: value) { _, new in if !focused { text = "\(Int(new))%" } }
    }
}
