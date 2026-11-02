import AppKit
import SwiftUI

/// Draws docs/images/overview.png from the installed app's readings and settings, read-only.
/// Run: bash scripts/render_overview.sh
@main struct RenderOverview {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        // Readings must be fresh for accounts to show as connected.
        let now = Date()
        let store = URL(fileURLWithPath: CommandLine.arguments[3])
        guard let status = StatusStore.load(from: store.appendingPathComponent("status.json")) else {
            fatalError("A current installed-app snapshot is required; no sample data is substituted")
        }
        let settings = try JSONDecoder().decode(WidgetSettings.self, from: Data(contentsOf: store.appendingPathComponent("settings.json")))
        WidgetSettings.sample = settings
        SettingsView.sample = true
        UsageModel.sampleVersion = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

        func widget(_ style: String, _ size: String) -> some View {
            var copy = settings; copy.style = style
            let small = size == "small", large = size == "large"
            return StatusView(status: status, date: now, compact: small, large: large, settings: copy)
                .padding(16).frame(width: small ? 170 : 360, height: large ? 380 : 170)
                .background { WidgetPaper(style: style) }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        func labeled<V: View>(_ title: String, _ content: V) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.black.opacity(0.06)))
                content
            }
        }

        // The settings window, drawn by AppKit so its native controls render exactly as on screen.
        let model = UsageModel()
        model.timer?.invalidate()
        model.settings = settings
        model.status = status
        let settingsHeight: CGFloat = 1400
        let host = NSHostingView(rootView: SettingsView(model: model).frame(width: 520, height: settingsHeight))
        host.frame = NSRect(x: 0, y: 0, width: 520, height: settingsHeight)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        for _ in 0..<20 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let settingsImage = NSImage(size: host.bounds.size); settingsImage.addRepresentation(rep)

        let page = HStack(alignment: .top, spacing: 36) {
            // One column per style: small, medium, large.
            ForEach([("Bars", "clean"), ("Solar", "solar")], id: \.1) { name, style in
                VStack(alignment: .leading, spacing: 30) {
                    labeled(name + " · small", widget(style, "small"))
                    labeled(name + " · medium", widget(style, "medium"))
                    labeled(name + " · large", widget(style, "large"))
                }.frame(width: 360, alignment: .leading)
            }
            labeled("Settings", Image(nsImage: settingsImage).resizable().frame(width: 520 * 0.8, height: settingsHeight * 0.8).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2))
        }
        .padding(40)
        .background(Color(red: 0.945, green: 0.945, blue: 0.957))
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: page)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { fatalError("Overview unavailable") }
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: output)
        _ = app
        print("Wrote", output.path)
    }
}
