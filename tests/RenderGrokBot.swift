import AppKit
import SwiftUI

/// Draws every widget size and Settings from current installed readings and the real Grok Bot feed.
/// All writes stay in the build folder; account state is read-only.
/// Run: bash scripts/render_grokbot.sh
@main struct RenderGrokBot {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        let store = URL(fileURLWithPath: CommandLine.arguments[3])
        guard var status = StatusStore.load(from: store.appendingPathComponent("status.json")) else {
            fatalError("A current installed-app snapshot is required; no sample data is substituted")
        }
        let settings = try JSONDecoder().decode(WidgetSettings.self, from: Data(contentsOf: store.appendingPathComponent("settings.json")))
        // Verify the current local feed through the production reader without writing account state.
        let collected = Collector.collect(previous: [:], providers: ["grokbot"], now: now) { _ in try UsageReader.grokBot() }
        let payload = try JSONSerialization.data(withJSONObject: ["usage": collected], options: [.sortedKeys])
        let real = try StatusStore.publishUsage(input: payload, to: folder.appendingPathComponent("status.json"), enabled: ["grokbot"])
        guard let grok = real.usage?["grokbot"], !grok.windows.isEmpty else { fatalError("Grok Bot feed has no reading") }
        status.usage?["grokbot"] = grok
        WidgetSettings.sample = settings
        SettingsView.sample = true
        UsageModel.sampleVersion = CommandLine.arguments[2]

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
