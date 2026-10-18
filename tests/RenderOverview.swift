import AppKit
import SwiftUI

/// Draws docs/images/overview.png from the app's real views with made-up readings; never touches account state.
/// Run: bash scripts/render_overview.sh
@main struct RenderOverview {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .aqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        // Readings must be fresh for accounts to show as connected.
        let now = Date()
        let hour: TimeInterval = 3600
        let ok = UsageRefresh(status: .ok, lastAttemptAt: now, lastSuccessAt: now, lastFailureAt: nil, failureReason: nil)
        let claude = [UsageWindow(window: "5-hour", usedPercent: 38, resetsAt: now.addingTimeInterval(2.2 * hour)),
                      UsageWindow(window: "weekly all", usedPercent: 76, resetsAt: now.addingTimeInterval(74 * hour)),
                      UsageWindow(window: "weekly Fable", usedPercent: 41, resetsAt: now.addingTimeInterval(74 * hour))]
        let codex = [UsageWindow(window: "5-hour", usedPercent: 18, resetsAt: now.addingTimeInterval(3.4 * hour)),
                     UsageWindow(window: "weekly", usedPercent: 92, resetsAt: now.addingTimeInterval(118 * hour))]
        // Six hours of steady sample use with a few busy spells, so Trends has a line to draw.
        var history: [String: [UsageObservation]] = [:]
        for (agent, windows) in [("claude", claude), ("codex", codex)] {
            for window in windows {
                var used = max(0, window.usedPercent - 14)
                history[UsageHistory.key(agent, window.window)] = (0...36).map { step in
                    let date = now.addingTimeInterval(Double(step - 36) * 600)
                    if step > 0 { used = min(window.usedPercent, used + (step % 6 < 2 ? 1.2 : 0.15)) }
                    return UsageObservation(date: date, usedPercent: step == 36 ? window.usedPercent : used, resetsAt: window.resetsAt)
                }
            }
        }
        let status = WidgetStatus(usage: ["claude": AgentUsage(observedAt: now, windows: claude, refresh: ok),
                                          "codex": AgentUsage(observedAt: now, windows: codex, refresh: ok)], usageHistory: history)
        var settings = WidgetSettings()
        settings.enabled = ["claude", "codex"]
        settings.usDates = true
        settings.autoDetected = true
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
        let settingsHeight: CGFloat = 1300
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
            VStack(alignment: .leading, spacing: 30) {
                labeled("Clean · small", widget("clean", "small"))
                labeled("Clean · large", widget("clean", "large"))
                HStack(alignment: .top, spacing: 20) {
                    labeled("Solar · small", widget("solar", "small"))
                    labeled("Trends · small", widget("trends", "small"))
                }
            }.frame(width: 360, alignment: .leading)
            VStack(alignment: .leading, spacing: 30) {
                labeled("Clean · medium", widget("clean", "medium"))
                labeled("Solar · medium", widget("solar", "medium"))
                labeled("Trends · medium", widget("trends", "medium"))
                labeled("Solar · large", widget("solar", "large"))
            }
            labeled("Settings", Image(nsImage: settingsImage).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
