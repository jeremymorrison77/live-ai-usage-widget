import SwiftUI
import WidgetKit
import AppIntents

/// Widget body. No padding of its own: WidgetKit supplies the content margins around `containerBackground`.
/// Desktop widgets usually render tinted, so hierarchy comes from size, weight and opacity, and every state
/// (low, almost out, old reading, unavailable, overdue) is also spelled out in words or a symbol.
struct StatusView: View {
    let status: WidgetStatus?
    let date: Date
    var compact = false
    var large = false
    var settings = WidgetSettings.load()

    var body: some View {
        UsageStatusView(status: status, date: date, compact: compact, large: large, settings: settings)
    }

}

/// A single native renderer shared by every widget family and the companion.
struct UsageStatusView: View {
    let status: WidgetStatus?
    let date: Date
    let compact: Bool
    let large: Bool
    let settings: WidgetSettings

    /// Every connected account shows at once; one without a reading yet shows empty "Loading…" rows.
    private var agents: [String] {
        ["claude", "codex"].filter { settings.enabled.contains($0) }
    }
    private func loading(_ agent: String) -> Bool { status?.usage?[agent]?.windows.isEmpty ?? true }
    private func windows(_ agent: String) -> [UsageWindow] {
        guard loading(agent) else { return status?.usage?[agent]?.windows ?? [] }
        return WidgetStatus.expectedWindows(agent).map { UsageWindow(window: $0, usedPercent: 100, resetsAt: nil) }
    }
    private func shown(_ agent: String) -> [UsageWindow] {
        let windows = windows(agent)
        if !compact { return windows }
        let all = agents.flatMap { a in self.windows(a).map { (a, $0) } }
            .filter { !settings.hiddenSmallMetrics.contains(UsageHistory.key($0.0, $0.1.window)) }
            .prefix(5)
        return all.filter { $0.0 == agent }.map { $0.1 }
    }
    private var count: Int { agents.reduce(0) { $0 + shown($1).count } }
    private var roomy: Bool { compact && count <= 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            if count == 0 {
                Spacer(minLength: 0)
                Text("Connect an account in Settings").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if !compact && !large {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(agents, id: \.self) { agent in
                        VStack(alignment: .leading, spacing: 4) { rows(agent) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: large ? 6 : 2) {
                    ForEach(agents, id: \.self) { agent in rows(agent) }
                }.frame(maxHeight: compact || large ? .infinity : nil, alignment: .top)
            }
            Spacer(minLength: 0)
            if !compact { Divider() }
            footer
        }
    }

    @ViewBuilder private func rows(_ agent: String) -> some View {
        ForEach(shown(agent), id: \.window) { window in
            let waiting = loading(agent)
            let stale = waiting || status?.usage?[agent]?.isStale(at: date) == true || (window.resetsAt.map { $0 <= date } ?? false)
            let color = waiting ? Color.secondary : settings.color(for: window.leftPercent)
            // While a requested check runs everything sits at zero; the new reading then grows in and eases to a stop.
            // A check the user asked for: the old reading fades away in place (the click's reload animates that), a second
            // later it is quietly reset to empty while invisible, and the reload that brings the new reading grows it in.
            // Mac animates changes between reloads, not between planned moments, which is why the steps fall this way.
            let since = status?.checkingSince ?? date
            let phase: Phase = status?.checking(at: date) == true ? (date.timeIntervalSince(since) < 0.9 ? .fading : .empty) : .shown
            let checking = phase != .shown
            let left = waiting ? 0 : phase == .fading ? window.leftPercent : phase == .empty ? 0 : window.leftPercent
            let visible = phase == .shown ? 1.0 : 0.0
            // Widgets allow up to two seconds of animation; growth uses all of it, slowing to a stop. Only growth moves.
            let grow: Animation? = phase == .shown ? .easeOut(duration: 2) : nil
            let fade = Animation.easeOut(duration: 0.25)
            HStack(spacing: compact ? 5 : 8) {
                if settings.style == "solar" {
                    ZStack {
                        Circle().stroke(color.opacity(0.15), lineWidth: compact ? 2 : 3)
                        Circle().trim(from: 0, to: left / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: compact ? 2 : 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(grow, value: left)
                            .opacity(visible).animation(fade, value: visible)
                    }.frame(width: compact ? (roomy ? 19 : 14) : 24, height: compact ? (roomy ? 19 : 14) : 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(WidgetStatus.name(agent) + " · " + shortName(window.window))
                        .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 1)
                    Text(waiting || checking ? "…" : "\(Int(window.leftPercent.rounded()))%")
                        .foregroundStyle(color).monospacedDigit().fontWeight(.medium)
                        .contentTransition(.numericText(value: left)).animation(grow ?? fade, value: left)
                }.font(.system(size: large ? 13 : compact ? 10 : 11))
                if settings.style == "clean" {
                    // The fill is revealed by a mask that stretches from the left: a scale, which widgets animate.
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.12))
                        Capsule().fill(color)
                            .mask(alignment: .leading) {
                                Capsule().scaleEffect(x: max(0.001, left / 100), y: 1, anchor: .leading)
                                    .animation(grow, value: left)
                            }
                            .opacity(visible).animation(fade, value: visible)
                    }.frame(height: large ? 5 : 3).padding(.top, 2)
                }
                if large || !compact || roomy {
                    Text(waiting ? (status?.usage?[agent]?.refresh?.status == .failed ? "Couldn't load · see Settings" : "Loading…") : stale ? "Old reading" : window.resetText(at: date) ?? "")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            }
            .opacity(stale ? 0.55 : 1)
            .frame(maxHeight: compact || large ? .infinity : nil)
            .accessibilityElement(children: .combine)
        }
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "5-hour": return "5h"
        case "weekly", "weekly all": return "week"
        case "weekly Fable": return "Fable"
        default: return name
        }
    }

    private var footer: some View {
        let failed = status?.usageWarning(at: date) != nil
        return HStack(spacing: 3) {
            if failed { Image(systemName: "exclamationmark.triangle.fill") }
            // Only a real failed check says "Failed"; otherwise the time of the last reading, with the warning sign when it is old.
            let checking = status?.emptied(at: date) == true
            if !checking, status?.usageFailureText() == nil, let retry = status?.pausedUntil(at: date) {
                // A live countdown to the automatic retry.
                (Text(compact ? "Refresh timed out.\nWaiting " : "Too many refreshes. Waiting ")
                    + Text(timerInterval: date...max(date, retry), countsDown: true).monospacedDigit()
                    + Text(compact ? "." : " to try again."))
                    // Two slightly smaller lines on the small widget so the whole message fits.
                    .font(.system(size: compact ? 9 : 10))
                    .lineLimit(compact ? 2 : 1).minimumScaleFactor(0.9).fixedSize(horizontal: false, vertical: true)
            } else if !checking, status?.usageFailureText() == nil, settings.autoUpdates, let version = settings.availableUpdate {
                // A new version: tapping it opens Settings, where Update is one click.
                Link(destination: URL(string: "live-ai-usage-widget://settings")!) {
                    Text("Version " + version + " available" + (compact ? "" : " · " + WidgetStatus.updateDateLabel(status?.usageObservedAt)))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }.buttonStyle(.plain)
            } else {
            Text(checking ? "Checking…" : status?.usageFailureText() ?? (compact ? "" : "Last refresh ") + WidgetStatus.updateDateLabel(status?.usageObservedAt))
                .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 2)
            if checking {
                // Widgets can't run a spinner, so a centered arc turns a step with each one-second entry, animated in between.
                let angle = (date.timeIntervalSinceReferenceDate.rounded()).truncatingRemainder(dividingBy: 360) * 180
                Circle().trim(from: 0, to: 0.7)
                    .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 9, height: 9)
                    .rotationEffect(.degrees(angle)).animation(.linear(duration: 1), value: angle)
                    .frame(width: 11, height: 11)
                    .accessibilityLabel("Checking usage")
            } else {
                RefreshButton()
            }
            Link(destination: URL(string: "live-ai-usage-widget://settings")!) { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .accessibilityLabel("Open settings")
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

private enum Phase { case fading, empty, shown }

/// In the widget a button that checks at once; elsewhere (pictures, gallery) the same arrow as a link.
struct RefreshButton: View {
    var body: some View {
        if #available(macOS 14.0, *), let intent = RefreshButton.intent {
            Button(intent: intent) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).accessibilityLabel("Check usage now")
        } else {
            Link(destination: URL(string: "live-ai-usage-widget://refresh")!) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).accessibilityLabel("Check usage now")
        }
    }
    /// Set by the widget so the shared view can use its intent without the app knowing about it.
    nonisolated(unsafe) static var intent: (any AppIntent)?
}

struct WidgetPaper: View {
    var style: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if style == "solar" { (scheme == .dark ? Color(red: 0.157, green: 0.141, blue: 0.122) : Color(red: 1, green: 0.976, blue: 0.933)) }
        else { Color(nsColor: .windowBackgroundColor) }
    }
}
