import AppKit
import SwiftUI
import WidgetKit
import ServiceManagement
import Darwin

@MainActor final class UsageModel: ObservableObject {
    @Published var settings = WidgetSettings.load()
    @Published var status = StatusStore.load()
    @Published var busy = false
    @Published var message = ""
    var timer: Timer?
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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
        } catch { message = "Could not save. Check the app-group signing setup and threshold values." }
    }
    func connect(_ provider: String) {
        do {
            let binary = try UsageReader.find(provider)
            settings.generation = UUID().uuidString
            save()
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveUsageWidget")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let script = root.appendingPathComponent("connect-" + provider + ".command")
            func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let arguments = provider == "claude" ? " auth login" : " login"
            try ("#!/bin/sh\nunset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CLAUDECODE\nexec " + quote(binary) + arguments + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
            message = "Complete sign-in in Terminal, then return and refresh."
        } catch { message = "Provider tool not found. Install it using the official setup link." }
    }
    func finishClaudeSetup() {
        do {
            let binary = try UsageReader.find("claude")
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "LiveUsageWidget")
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
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "UsageWidget")
        busy = true
        message = "Refreshing…"
        Task {
            let payload: Data? = await Task.detached {
                try? Collector.run(root: root, generation: settings.generation, providers: settings.enabled)
            }.value
            defer { busy = false }
            guard settings.generation == self.settings.generation else { message = "Accounts changed; refresh again."; return }
            guard let payload else { message = "Collection failed. Check the official provider tools and storage access."; return }
            do {
                status = try StatusStore.publishUsage(input: payload)
                WidgetCenter.shared.reloadAllTimelines()
                message = status?.usageFailureText() ?? "Readings checked. Automatic retries respect provider backoff."
            } catch { message = "Could not publish. Check app-group signing and storage access." }
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
        WindowGroup("Live Usage Widget", id: "main") {
            VStack(spacing: 16) {
                StatusView(status: model.status, date: Date(), large: true, settings: model.settings)
                    .padding(12).frame(width: 344, height: 344)
                    .background { WidgetPaper(style: model.settings.style).clipShape(RoundedRectangle(cornerRadius: 20)) }
                Text(model.message).font(.caption).foregroundStyle(.secondary)
                HStack { Button("Refresh") { model.refresh() }; SettingsLink() }
            }.padding().onAppear { model.refresh() }
                .modifier(WidgetLinks(model: model))
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        Settings { SettingsView(model: model) }
    }
}

struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @State private var login: String?
    @State private var previewRemaining = 65.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        Form {
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
            Section("Preview usage") {
                Slider(value: $previewRemaining, in: 0...100, step: 1)
                HStack {
                    Text("Sample"); Spacer()
                    Text("\(Int(previewRemaining))% remaining").foregroundStyle(model.settings.color(for: previewRemaining)).monospacedDigit()
                }
                StatusView(status: previewStatus, date: Date(), compact: true, settings: previewSettings)
                    .padding(12).frame(width: 164, height: 164)
                    .background(model.settings.style == "solar" ? Color.orange.opacity(0.06) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
                    .allowsHitTesting(false)
            }

            Section("Background collection") {
                Toggle("Open at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { model.message = "Login-item change failed. Check macOS Login Items settings."; launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
                Text("Keep the app running for automatic refresh. Closing its window is fine; quitting stops collection. Connect an existing official provider tool, or install it using the link in Accounts.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Save settings") { model.save(); model.refresh() }
            Text(model.message).font(.caption)
        }.formStyle(.grouped).frame(width: 520, height: 700)
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
    private var previewSettings: WidgetSettings {
        var value = model.settings; value.enabled = ["claude", "codex"]; value.hiddenSmallMetrics = []; return value
    }
    private var previewStatus: WidgetStatus {
        let reading = UsageWindow(window: "5-hour", usedPercent: 100-previewRemaining, resetsAt: Date().addingTimeInterval(3600))
        return WidgetStatus(usage: ["claude": AgentUsage(observedAt: Date(), windows: [reading]), "codex": AgentUsage(observedAt: Date(), windows: [reading])])
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
    @Published var url: URL?
}

struct WidgetLinks: ViewModifier {
    @Environment(\.openSettings) private var openSettings
    let model: UsageModel
    func body(content: Content) -> some View {
        content.onOpenURL { URLRouter.shared.url = $0 }
            .onReceive(URLRouter.shared.$url) { url in
                guard let url else { return }
                URLRouter.shared.url = nil
                if url.host == "refresh" { model.refresh() }
                else if url.host == "settings" {
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
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
