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
    func save() {
        do {
            let changedAccounts = settings.generation != WidgetSettings.load().generation
            try settings.save()
            // Disabling a provider erases its cached reading and history immediately.
            let destination = try StatusStore.fileURL()
            try StatusStore.locked(destination) {
                var value = StatusStore.load() ?? WidgetStatus()
                if changedAccounts { value = WidgetStatus() }
                value.usage = value.usage?.filter { settings.enabled.contains($0.key) }
                value.usageHistory = value.usageHistory?.filter { settings.enabled.contains(String($0.key.split(separator: ":")[0])) }
                try JSONEncoder().encode(value).write(to: destination, options: .atomic)
            }
            status = StatusStore.load()
            WidgetCenter.shared.reloadAllTimelines()
            message = "Saved"
        } catch { message = "Couldn't save settings. Check the color percentages, or reinstall the app." }
    }
    func installed(_ provider: String) -> Bool { (try? UsageReader.find(provider)) != nil }
    func toolName(_ provider: String) -> String { provider == "claude" ? "Claude Code" : "Codex" }
    /// Turns an account on and does whatever is missing: install, browser sign-in, then a fresh reading.
    func connect(_ provider: String) {
        if !settings.enabled.contains(provider) {
            settings.enabled = ["claude", "codex"].filter { $0 == provider || settings.enabled.contains($0) }
            settings.generation = UUID().uuidString
            save()
        }
        let probe = self.probe
        Task {
            if !installed(provider) {
                await installNow(provider)
                guard installed(provider) else { return }
            }
            working[provider] = "Checking sign-in…"
            try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            let signed = await Task.detached { UsageReader.signedIn(provider, directory: probe) }.value
            working[provider] = nil
            signedIn[provider] = signed
            if signed == true { checkConnection() } else { signIn(provider) }
        }
    }
    /// Only stops showing this account; the official tool stays signed in.
    func disconnect(_ provider: String) {
        settings.enabled.removeAll { $0 == provider }
        settings.generation = UUID().uuidString
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
                working[provider] = "Checking sign-in…"
                if await Task.detached(operation: { UsageReader.signedIn(provider, directory: probe) }).value == true { found.append(provider) }
                working[provider] = nil
            }
            guard !found.isEmpty else { return }
            settings.enabled = found
            checkConnection()
        }
    }
    func isConnected(_ provider: String) -> Bool {
        status?.usage?[provider]?.refresh?.status == .ok && status?.usage?[provider]?.isStale(at: Date()) == false
    }
    /// Provider → what is happening right now, shown in the Connect window.
    @Published var working: [String: String] = [:]
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
        working[provider] = claude ? "Installing Claude Code…" : "Installing Codex…"
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
            if failure == "usage_read_timed_out" { message = "Sign-in timed out. Try again."; return }
            if failure != nil { message = "Sign-in didn't finish. Try again."; return }
            settings.generation = UUID().uuidString
            updateSignedIn(provider)
            checkConnection()
        }
    }
    func checkConnection() {
        let probe = self.probe
        let claude = settings.enabled.contains("claude")
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
            save()
            refresh()
        }
    }
    func refresh(force: Bool = false) {
        guard !busy else { return }
        let settings = self.settings
        // Nothing to check until an account is turned on; stay quiet instead of reporting.
        guard !settings.enabled.isEmpty else { message = ""; return }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveAIUsageWidget")
        busy = true
        message = "Checking usage…"
        Task {
            let payload: Data? = await Task.detached {
                try? Collector.run(root: root, generation: settings.generation, providers: settings.enabled, interval: Double(settings.refreshMinutes) * 60, force: force)
            }.value
            defer { busy = false }
            guard settings.generation == self.settings.generation else { message = "Accounts changed. Checking again shortly."; return }
            guard let payload else { message = "Couldn't check usage. Make sure the Claude or ChatGPT command-line tool is installed and signed in."; return }
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
        .windowResizability(.contentSize)
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
        // Same words as the Accounts rows in the settings window; disconnecting is only offered there.
        ForEach(["claude", "codex"], id: \.self) { provider in
            let name = provider == "claude" ? "Claude" : "ChatGPT"
            let installed = model.installed(provider)
            let connected = model.settings.enabled.contains(provider) && model.isConnected(provider)
            Button(name + " · " + (installed ? "Installed" : "Not installed")) { open() }
            if let busy = model.working[provider] { Text(busy) }
            else if !installed { Button("Install " + model.toolName(provider)) { model.install(provider) } }
            else if connected { Button { open() } label: { Label { Text("Connected") } icon: { Image(nsImage: MenuIcon.check) } } }
            else { Button("Connect") { open(); model.connect(provider) } }
        }
        Divider()
        Button("Settings…") { open() }
        Button("Check now") { model.refresh(force: true) }.disabled(model.settings.enabled.isEmpty)
        Divider()
        Button("Quit Live AI Usage Widget") { NSApp.terminate(nil) }
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
        let name = provider == "claude" ? "Claude" : "ChatGPT"
        let installed = model.installed(provider)
        let connected = model.settings.enabled.contains(provider) && model.isConnected(provider)
        let busy = model.working[provider]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                if busy != nil { ProgressView().controlSize(.small) }
                Text(installed ? "Installed" : "Not installed").foregroundStyle(.secondary)
                Button {
                    if !installed { model.install(provider) } else if connected { model.disconnect(provider) } else { model.connect(provider) }
                } label: {
                    Group {
                        if !installed { Text(busy != nil ? "Installing…" : "Install " + model.toolName(provider)) }
                        else if connected && hovering { Label("Disconnect", systemImage: "xmark.circle").foregroundStyle(.red) }
                        else if connected { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        else if busy != nil { Text("Connecting…") }
                        else { Label("Connect", systemImage: "person.crop.circle") }
                    }.frame(width: 140)
                }
                .disabled(busy != nil)
                .onHover { hovering = $0 }
            }
            if let busy {
                HStack(spacing: 6) {
                    Text(busy).font(.caption).foregroundStyle(.secondary)
                    if let link = model.signInLink[provider] { Link("Open sign-in page", destination: link).font(.caption) }
                }
            } else if model.settings.enabled.contains(provider) && !connected, let reason = model.status?.usage?[provider]?.refresh?.failureReason {
                Text(reason.actionLabel(agent: name)).font(.caption).foregroundStyle(.orange)
            }
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
                    Button { model.save(); model.refresh() } label: { Text("Save settings").frame(width: 130) }
                        .keyboardShortcut(.defaultAction)
                }
                if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 14).frame(maxWidth: .infinity).background(.bar)
            }
            .frame(width: 520, height: 640)
            .onAppear {
                NSApp.activate(ignoringOtherApps: true); checkWidgets()
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
            let names = model.status?.usage?[provider]?.windows.map(\.window) ?? (provider == "claude" ? ["5-hour", "weekly all", "weekly Fable"] : ["5-hour", "weekly"])
            return names.map { UsageHistory.key(provider, $0) }
        }
    }
    private func metricTitle(_ key: String) -> String {
        key.replacingOccurrences(of: "claude:", with: "Claude · ").replacingOccurrences(of: "codex:", with: "ChatGPT · ")
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
