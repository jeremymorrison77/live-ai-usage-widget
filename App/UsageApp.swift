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
    func connect(_ provider: String) {
        do {
            let binary = try UsageReader.find(provider)
            settings.generation = UUID().uuidString
            save()
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveAIUsageWidget")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let script = root.appendingPathComponent("connect-" + provider + ".command")
            func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let arguments = provider == "claude" ? " auth login" : " login"
            try ("#!/bin/sh\nunset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CLAUDECODE\nexec " + quote(binary) + arguments + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
            message = "Finish signing in in Terminal, then choose Check connection."
        } catch { message = "That app's command-line tool isn't installed. Use Install official tool first." }
    }
    func finishClaudeSetup() {
        do {
            let binary = try UsageReader.find("claude")
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveAIUsageWidget")
            let probe = root.appendingPathComponent("probe")
            try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
            func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let script = root.appendingPathComponent("setup-claude.command")
            let command = "#!/bin/sh\nunset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CLAUDECODE\ncd " + quote(probe.path) + " || exit 1\nexec " + quote(binary) + " " + UsageReader.claudeArguments.map(quote).joined(separator: " ") + "\n"
            try command.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch { message = "Install or update the official Claude tool first." }
    }
    func checkConnection() {
        // An explicit post-setup check starts a new collection generation; timer retries keep their backoff.
        settings.generation = UUID().uuidString
        save()
        refresh()
    }
    func refresh() {
        guard !busy else { return }
        let settings = self.settings
        // Nothing to check until an account is turned on; stay quiet instead of reporting.
        guard !settings.enabled.isEmpty else { message = ""; return }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveAIUsageWidget")
        busy = true
        message = "Checking usage…"
        Task {
            let payload: Data? = await Task.detached {
                try? Collector.run(root: root, generation: settings.generation, providers: settings.enabled, interval: Double(settings.refreshMinutes) * 60)
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
        Window("Live AI Usage Widget", id: "main") {
            SettingsView(model: model)
                .onAppear { model.refresh() }
                .modifier(WidgetLinks())
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .appSettings) { SettingsCommand() } }
    }
}

struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View { Button("Settings…") { openWindow(id: "main") }.keyboardShortcut(",") }
}

struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @State private var login: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var widgetsPlaced: Int?
    @State private var showWidgetHelp = false
    @State private var showSetupHelp = false
    // Get started hides itself once every step is done; Setup help brings it back.
    private var setupDone: Bool { anyConnected && (widgetsPlaced ?? 0) > 0 && launchAtLogin }
    private var anyConnected: Bool {
        model.settings.enabled.contains { model.status?.usage?[$0]?.refresh?.status == .ok && model.status?.usage?[$0]?.isStale(at: Date()) == false }
    }
    private func checkWidgets() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let count = (try? result.get())?.count
            DispatchQueue.main.async { widgetsPlaced = count }
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
                    step(1, "Turn on Claude, ChatGPT or both, then connect", done: anyConnected)
                    Spacer()
                }
                HStack {
                    step(2, "Add the widget to your desktop", done: (widgetsPlaced ?? 0) > 0)
                    Spacer()
                    if (widgetsPlaced ?? 0) > 0 { Text("On desktop").foregroundStyle(.secondary) }
                    else { Button("Show me how") { showWidgetHelp = true } }
                }
                HStack {
                    step(3, "Open at login so it keeps running", done: launchAtLogin)
                    Spacer()
                    Toggle("Open at login", isOn: $launchAtLogin).labelsHidden().onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { model.message = "Couldn't change Open at login. Check Login Items in System Settings."; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                }
                Text("You can close this window. The widget keeps updating while the app is running. Reopen this window from the Dock or the widget's gear button.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Get started") }
            }
            Section("Accounts") {
                ForEach(["claude", "codex"], id: \.self) { provider in
                    HStack {
                        Toggle(provider == "claude" ? "Claude" : "ChatGPT", isOn: Binding(
                            get: { model.settings.enabled.contains(provider) },
                            set: { on in
                                model.settings.generation = UUID().uuidString
                                model.settings.enabled.removeAll { $0 == provider }
                                if on { model.settings.enabled.append(provider) }
                                model.save()
                            })).toggleStyle(.checkbox)
                        Spacer()
                        let connected = model.status?.usage?[provider]?.refresh?.status == .ok && model.status?.usage?[provider]?.isStale(at: Date()) == false
                        Button { login = provider } label: {
                            Label(connected ? "Connected" : "Connect", systemImage: connected ? "checkmark.circle.fill" : "person.crop.circle")
                                .foregroundStyle(connected ? Color.green : Color.primary).frame(width: 110)
                        }.disabled(!model.settings.enabled.contains(provider))
                    }
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
                Text("Default is 5 minutes. After a failed check the app waits at least 15 minutes. Save settings to apply.").font(.caption).foregroundStyle(.secondary)
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
            .onAppear { checkWidgets() }
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
            .sheet(item: Binding(get: { login.map(Login.init) }, set: { login = $0?.id })) { item in
                VStack(alignment: .leading, spacing: 14) {
                    Text("Connect your own account").font(.headline)
                    Text("Install the official tool, then run this command in Terminal and complete its sign-in:")
                    Text(item.id == "claude" ? "claude auth login" : "codex login").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    if let reason = model.status?.usage?[item.id]?.refresh?.failureReason {
                        Text(reason.actionLabel(agent: item.id == "claude" ? "Claude" : "ChatGPT")).foregroundStyle(.orange)
                    }
                    if item.id == "claude" {
                        Text("Requires Claude Code 2.1.301 or newer. Run claude update if needed. Finish setup opens only the widget working folder; approve its trust prompt there, then close that Terminal window.").font(.caption)
                        Button("Finish Claude setup") { model.finishClaudeSetup(); login = nil }
                    }
                    Text("After sign-in and setup, choose Check connection. A green check appears only after fresh usage is received.").font(.caption)
                    HStack {
                        Link("Install official tool", destination: URL(string: item.id == "claude" ? "https://code.claude.com/docs/en/setup" : "https://developers.openai.com/codex/cli/")!)
                        Spacer()
                        Button("Sign in") { model.connect(item.id); login = nil }
                        Button("Check connection") { login = nil; model.checkConnection() }
                    }
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
    struct Login: Identifiable { let id: String }
}

@MainActor final class URLRouter: ObservableObject {
    static let shared = URLRouter()
    @Published var url: URL? {
        didSet {
            guard let url else { return }
            if url.host == "settings" { settings = true } else if url.host == "refresh" { refresh = true }
        }
    }
    @Published var settings = false
    @Published var refresh = false
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
