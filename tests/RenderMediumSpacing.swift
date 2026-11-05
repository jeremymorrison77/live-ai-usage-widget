import AppKit
import SwiftUI

/// Synthetic-only visual check; never loads account state.
@main struct RenderMediumSpacing {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let reset = now.addingTimeInterval(7200)
        let balance = GrokCredits(creditsAvailableUSD: 295.64, creditsPurchasedUSD: 300, usedThisMonthUSD: 4.36, monthlyLimitUSD: nil, burn24hUSD: 12.34, updatedAt: ISO8601DateFormatter().string(from: now))
        let usage = [
            "claude": AgentUsage(observedAt: now, windows: ["weekly all", "weekly Fable"].map { UsageWindow(window: $0, usedPercent: 30, resetsAt: reset) }),
            "codex": AgentUsage(observedAt: now, windows: [UsageWindow(window: "weekly", usedPercent: 40, resetsAt: reset)]),
            "grokbot": AgentUsage(observedAt: now, windows: [UsageWindow(window: "weekly", usedPercent: 100, resetsAt: reset)], maximumAge: 10800, creditsUSD: 295.64, grokCredits: balance)
        ]
        let status = WidgetStatus(usage: usage)
        var settings = WidgetSettings()
        settings.enabled = ["claude", "codex", "grokbot"]
        for style in ["clean", "solar"] {
        settings.style = style
        for (name, small, large) in [("medium", false, false)] {
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
