import AppKit
import SwiftUI

/// Synthetic-only visual check; never loads account state.
@main struct RenderPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let reset = now.addingTimeInterval(7200)
        let usage = ["claude": AgentUsage(observedAt: now, windows: [UsageWindow(window: "5-hour", usedPercent: 12, resetsAt: reset), UsageWindow(window: "weekly all", usedPercent: 78, resetsAt: reset), UsageWindow(window: "weekly Fable", usedPercent: 35, resetsAt: reset)]), "codex": AgentUsage(observedAt: now, windows: [UsageWindow(window: "5-hour", usedPercent: 50, resetsAt: reset), UsageWindow(window: "weekly", usedPercent: 91, resetsAt: reset)])]
        let status = WidgetStatus(usage: usage)
        var settings = WidgetSettings()
        settings.enabled = ["claude", "codex"]
        for style in ["clean", "solar"] {
        settings.style = style
        for (name, small, large) in [("small", true, false), ("medium", false, false), ("large", false, true)] {
            let view = StatusView(status: status, date: now, compact: small, large: large, settings: settings)
                .padding(12).frame(width: small ? 164 : 344, height: large ? 344 : 164)
                .background { WidgetPaper(style: style) }
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage else { fatalError("Preview unavailable") }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(style + "-" + name + ".png"))
        }
        }
    }
}
