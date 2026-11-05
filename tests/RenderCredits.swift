import AppKit
import SwiftUI

/// Synthetic layout checks only; never reads or changes installed account state.
/// Compile with Shared/Status.swift, Shared/Settings.swift and Shared/StatusView.swift.
@main struct RenderCredits {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: "build/grok-credits-1.3.7")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        for scenario in ["below-limit", "exhausted-with-purchased", "under-100", "under-25", "stale", "no-purchased"] {
        for used in [false, true] {
            let page = HStack(alignment: .top, spacing: 20) {
                ForEach(["clean", "solar"], id: \.self) { style in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(style + (used ? " · used" : " · left"))
                        ForEach(["small", "medium", "large"], id: \.self) { size in
                            widget(style, size, used: used, now: now, scenario: scenario)
                        }
                    }
                }
            }.padding(20).background(Color.white)
            let renderer = ImageRenderer(content: page.environment(\.colorScheme, .light))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { fatalError("Render unavailable") }
            try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
                .write(to: folder.appendingPathComponent(scenario + (used ? "-used.png" : "-left.png")))
        }
    }
    }
    static func widget(_ style: String, _ size: String, used: Bool, now: Date, scenario: String) -> some View {
        var settings = WidgetSettings()
        settings.enabled = ["claude", "codex", "grokbot"]
        settings.style = style
        settings.showUsed[style] = used
        settings.hiddenSmallMetrics = []
        var status = WidgetStatus.preview
        status.usage?["claude"] = AgentUsage(observedAt: now, windows: ["5-hour", "weekly all", "weekly Fable"].map { UsageWindow(window: $0, usedPercent: 30, resetsAt: now.addingTimeInterval(86400)) })
        let amount = scenario == "under-100" ? 75.0 : scenario == "under-25" ? 12.5 : 295.64
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(scenario == "stale" ? -28801 : 0))
        let balance = GrokCredits(creditsAvailableUSD: amount, creditsPurchasedUSD: scenario == "no-purchased" ? nil : 300, usedThisMonthUSD: 304.37, monthlyLimitUSD: nil, burn24hUSD: 12.34, updatedAt: stamp)
        status.usage?["grokbot"] = AgentUsage(observedAt: now, windows: [UsageWindow(window: "weekly", usedPercent: scenario == "below-limit" ? 80 : 100, resetsAt: now.addingTimeInterval(86400))], maximumAge: 10800, creditsUSD: amount, grokCredits: balance)
        return StatusView(status: status, date: now, compact: size == "small", large: size == "large", settings: settings)
            .padding(16).frame(width: size == "small" ? 170 : 360, height: size == "large" ? 380 : 170)
            .background { WidgetPaper(style: style) }
    }
}
