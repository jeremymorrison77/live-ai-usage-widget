import AppKit
import SwiftUI

/// Debug check for the Grok Bot account: reads the real Grok Bot usage file the way the app does (Collector, then the
/// shared store, written to a scratch file in build/), then draws every widget size in both styles and the Settings
/// window from the app's own views. Claude Code and ChatGPT Codex rows are made-up samples; nothing else is read.
/// Run: bash scripts/render_grokbot.sh
@main struct RenderGrokBot {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        let hour: TimeInterval = 3600
        // The real file, through the same path as a check in the app.
        let collected = Collector.collect(previous: [:], providers: ["grokbot"], now: now) { _ in try UsageReader.grokBot() }
        let payload = try JSONSerialization.data(withJSONObject: ["usage": collected], options: [.sortedKeys])
        let real = try StatusStore.publishUsage(input: payload, to: folder.appendingPathComponent("status.json"), enabled: ["grokbot"])
        guard let grok = real.usage?["grokbot"], let weekly = grok.windows.first else {
            print("Grok Bot: no reading (", (collected["grokbot"] as? [String: Any])?["failure_reason"] ?? "unknown", ")"); exit(1)
        }
        let format = ISO8601DateFormatter()
        print(String(format: "Grok Bot · %@: %.1f%% used, %.1f%% left", weekly.displayName, weekly.usedPercent, weekly.leftPercent),
              "· resets", weekly.resetsAt.map(format.string) ?? "unknown", "· updated", grok.observedAt.map(format.string) ?? "unknown",
              "· old reading:", grok.isStale(at: now) ? "yes" : "no")
        let ok = UsageRefresh(status: .ok, lastAttemptAt: now, lastSuccessAt: now, lastFailureAt: nil, failureReason: nil)
        let claude = [UsageWindow(window: "5-hour", usedPercent: 38, resetsAt: now.addingTimeInterval(2.2 * hour)),
                      UsageWindow(window: "weekly all", usedPercent: 76, resetsAt: now.addingTimeInterval(74 * hour)),
                      UsageWindow(window: "weekly Fable", usedPercent: 41, resetsAt: now.addingTimeInterval(74 * hour))]
        let codex = [UsageWindow(window: "5-hour", usedPercent: 18, resetsAt: now.addingTimeInterval(3.4 * hour)),
                     UsageWindow(window: "weekly", usedPercent: 92, resetsAt: now.addingTimeInterval(118 * hour))]
        let status = WidgetStatus(usage: ["claude": AgentUsage(observedAt: now, windows: claude, refresh: ok),
                                          "codex": AgentUsage(observedAt: now, windows: codex, refresh: ok), "grokbot": grok])
        var settings = WidgetSettings()
        settings.enabled = WidgetStatus.providers
        settings.autoDetected = true
        WidgetSettings.sample = settings
        SettingsView.sample = true

        func widget(_ style: String, _ size: String) -> some View {
            var copy = settings; copy.style = style
            let small = size == "small", large = size == "large"
            return StatusView(status: status, date: now, compact: small, large: large, settings: copy)
                .padding(16).frame(width: small ? 170 : 360, height: large ? 380 : 170)
                .background { WidgetPaper(style: style) }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        func save<V: View>(_ view: V, _ name: String) throws {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { fatalError("Picture unavailable") }
            try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
        }
        for style in ["clean", "solar"] { for size in ["small", "medium", "large"] { try save(widget(style, size), style + "-" + size + ".png") } }

        let model = UsageModel()
        model.timer?.invalidate()
        model.settings = settings
        model.status = status
        let height: CGFloat = 1500
        let host = NSHostingView(rootView: SettingsView(model: model).frame(width: 520, height: height))
        host.frame = NSRect(x: 0, y: 0, width: 520, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        for _ in 0..<20 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("settings.png"))
        let settingsImage = NSImage(size: host.bounds.size); settingsImage.addRepresentation(rep)

        let page = HStack(alignment: .top, spacing: 36) {
            ForEach([("Bars · shows what's left", "clean"), ("Solar · shows what's used", "solar")], id: \.1) { name, style in
                VStack(alignment: .leading, spacing: 24) {
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    widget(style, "small"); widget(style, "medium"); widget(style, "large")
                }.frame(width: 360, alignment: .leading)
            }
            Image(nsImage: settingsImage).resizable().frame(width: 520 * 0.8, height: height * 0.8)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(40).background(Color(red: 0.945, green: 0.945, blue: 0.957))
        try save(page, "grokbot-overview.png")
        _ = app
        print("Wrote", folder.path)
    }
}
