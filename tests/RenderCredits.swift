import AppKit
import SwiftUI

/// Synthetic layout checks only; never reads or changes installed account state.
/// Compile with Shared/Status.swift, Shared/Settings.swift and Shared/StatusView.swift.
@main struct RenderCredits {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: "build/credits-preview")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        for used in [false, true] {
            let page = HStack(alignment: .top, spacing: 20) {
                ForEach(["clean", "solar"], id: \.self) { style in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(style + (used ? " · used" : " · left"))
                        ForEach(["small", "medium", "large"], id: \.self) { size in
                            widget(style, size, used: used, now: now)
                        }
                    }
                }
            }.padding(20).background(Color.white)
            let renderer = ImageRenderer(content: page.environment(\.colorScheme, .light))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { fatalError("Render unavailable") }
            try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
                .write(to: folder.appendingPathComponent(used ? "used.png" : "left.png"))
        }
    }
    static func widget(_ style: String, _ size: String, used: Bool, now: Date) -> some View {
        var settings = WidgetSettings()
        settings.enabled = ["claude", "codex", "grokbot"]
        settings.style = style
        settings.showUsed[style] = used
        settings.hiddenSmallMetrics = []
        var status = WidgetStatus.preview
        status.usage?["claude"] = AgentUsage(observedAt: now, windows: ["5-hour", "weekly all", "weekly Fable"].map { UsageWindow(window: $0, usedPercent: 30, resetsAt: now.addingTimeInterval(86400)) })
        status.usage?["grokbot"] = AgentUsage(observedAt: now, windows: [UsageWindow(window: "weekly", usedPercent: 100, resetsAt: now.addingTimeInterval(86400))], maximumAge: 10800, creditsUSD: 300)
        return StatusView(status: status, date: now, compact: size == "small", large: size == "large", settings: settings)
            .padding(16).frame(width: size == "small" ? 170 : 360, height: size == "large" ? 380 : 170)
            .background { WidgetPaper(style: style) }
    }
}
