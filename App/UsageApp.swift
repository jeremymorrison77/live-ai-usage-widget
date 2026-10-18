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
    func install(_ provider: String) {
        let claude = provider == "claude"
        working[provider] = claude ? "Installing Claude Code…" : "Installing Codex…"
        // Claude's official installer, or OpenAI's signed Codex release for Apple Silicon, run in the background.
        let command = claude ? "curl -fsSL https://claude.ai/install.sh | bash"
            : "set -e; d=$(mktemp -d); curl -fsSL https://github.com/openai/codex/releases/latest/download/codex-aarch64-apple-darwin.tar.gz -o \"$d/codex.tgz\"; tar -xzf \"$d/codex.tgz\" -C \"$d\"; mkdir -p \"$HOME/.local/bin\"; mv \"$d/codex-aarch64-apple-darwin\" \"$HOME/.local/bin/codex\"; chmod 755 \"$HOME/.local/bin/codex\"; rm -rf \"$d\""
        Task {
            let ok = await Task.detached { () -> Bool in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
            }.value
            working[provider] = nil
            message = ok ? (claude ? "Claude Code" : "Codex") + " is installed. Next, sign in." : "Couldn't install it. Use the install link instead."
            objectWillChange.send()
        }
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
        Window("Live AI Usage Widget", id: "main") {
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
        // Each account with its status; anything not connected opens its Connect window.
        ForEach(["claude", "codex"], id: \.self) { provider in
            let name = provider == "claude" ? "Claude" : "ChatGPT"
            if !model.settings.enabled.contains(provider) {
                Button(name + " · Off — Turn on…") { open() }
            } else if model.isConnected(provider) {
                Button { open() } label: { Label(name + " · Connected", systemImage: "checkmark.circle.fill") }
            } else {
                Button { open(connecting: provider) } label: { Label(name + " · Not connected — Connect…", systemImage: "exclamationmark.circle") }
            }
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
    @Environment(\.dismissWindow) private var dismissWindow
    private static var launchHandled = false
    // Get started hides itself once every step is done; Setup help brings it back.
    private var setupDone: Bool { anyConnected && (widgetsPlaced ?? 0) > 0 && launchAtLogin }
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
                if !model.settings.enabled.isEmpty && (count ?? 0) > 0 && launchAtLogin && !URLRouter.shared.settingsRequested {
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
                Text("You can close this window. The widget keeps updating while the app is running. Reopen this window from the menu bar icon or the widget's gear button.").font(.caption).foregroundStyle(.secondary)
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
                        let connected = model.isConnected(provider)
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
            .onAppear { NSApp.activate(ignoringOtherApps: true); checkWidgets() }
            .onReceive(URLRouter.shared.$connect) { provider in
                guard let provider else { return }
                URLRouter.shared.connect = nil
                login = provider
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
            .sheet(item: Binding(get: { login.map(Login.init) }, set: { login = $0?.id })) { item in
                let claude = item.id == "claude"
                let name = claude ? "Claude" : "ChatGPT"
                // Skip the install step when the official tool is already on this Mac.
                let installed = (try? UsageReader.find(item.id)) != nil
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect " + name).font(.headline)
                        Text("Uses your own account through the official " + (claude ? "Claude Code" : "Codex") + " tool. You never type a password into this app.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let reason = model.status?.usage?[item.id]?.refresh?.failureReason {
                        Text(reason.actionLabel(agent: name)).foregroundStyle(.orange)
                    }
                    let busy = model.working[item.id]
                    if installed {
                        connectRow(1, done: true, title: (claude ? "Claude Code" : "Codex") + " is installed", detail: "Found on this Mac.") { EmptyView() }
                    } else {
                        connectRow(1, title: "Install the official tool",
                                   detail: "Not found on this Mac. Install downloads the official " + (claude ? "Claude Code" : "Codex") + " tool in the background.",
                                   link: claude ? "https://code.claude.com/docs/en/setup" : "https://learn.chatgpt.com/docs/codex/cli#getting-started") {
                            Button("Install") { model.install(item.id) }.disabled(busy != nil)
                        }
                    }
                    let signed = model.signedIn[item.id] == true
                    connectRow(2, done: signed, title: signed ? "Signed in" : "Sign in",
                               detail: signed ? "Your account is signed in to the official tool." : "Opens your browser to sign in to your own " + name + " account.") {
                        if !signed { Button("Sign in") { model.signIn(item.id) }.disabled(!installed || busy != nil) }
                    }
                    connectRow(3, title: "Check connection", detail: "A green check appears in Accounts once a fresh reading arrives.") {
                        Button("Check connection") { login = nil; model.checkConnection() }.keyboardShortcut(.defaultAction).disabled(!installed || busy != nil)
                    }
                    if let busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(busy).font(.callout)
                            if let link = model.signInLink[item.id] { Link("Open sign-in page", destination: link).font(.callout) }
                        }
                    }
                    HStack { Spacer(); Button("Cancel") { login = nil }.keyboardShortcut(.cancelAction) }
                }.padding(24).frame(width: 460)
                .onAppear { model.updateSignedIn(item.id) }
            }
    }
    private func connectRow<Action: View>(_ number: Int, done: Bool = false, title: String, detail: String, link: String? = nil, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle").foregroundStyle(done ? Color.green : Color.secondary).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                if let link, let url = URL(string: link) { Link(title, destination: url).fontWeight(.medium) } else { Text(title).fontWeight(.medium) }
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
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
