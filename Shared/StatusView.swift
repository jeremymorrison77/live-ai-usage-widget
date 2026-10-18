import SwiftUI
import WidgetKit

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
        TrendsStatusView(status: status, date: date, compact: compact, large: large, settings: settings)
    }

}

/// A single native renderer shared by every widget family and the companion.
/// Sparklines encode observed consumption rate, while numbers remain allowance left.
struct TrendsStatusView: View {
    let status: WidgetStatus?
    let date: Date
    let compact: Bool
    let large: Bool
    let settings: WidgetSettings

    private var agents: [String] {
        ["claude", "codex"].filter { settings.enabled.contains($0) && !(status?.usage?[$0]?.windows.isEmpty ?? true) }
    }
    private func shown(_ agent: String) -> [UsageWindow] {
        let windows = status?.usage?[agent]?.windows ?? []
        if !compact { return windows }
        let all = agents.flatMap { a in (status?.usage?[a]?.windows ?? []).map { (a, $0) } }
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
                Text("Waiting for readings").font(.system(size: 11)).foregroundStyle(.secondary)
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
            let stale = status?.usage?[agent]?.isStale(at: date) == true || (window.resetsAt.map { $0 <= date } ?? false)
            let history = status?.usageHistory?[UsageHistory.key(agent, window.window)] ?? []
            let activity = UsageHistory.activity(history, at: date)
            let color = settings.color(for: window.leftPercent)
            HStack(spacing: compact ? 5 : 8) {
                if settings.style == "solar" {
                    ZStack {
                        Circle().stroke(color.opacity(0.15), lineWidth: compact ? 2 : 3)
                        Circle().trim(from: 0, to: window.leftPercent / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: compact ? 2 : 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }.frame(width: compact ? (roomy ? 19 : 14) : 24, height: compact ? (roomy ? 19 : 14) : 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(WidgetStatus.name(agent) + " · " + shortName(window.window))
                        .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 1)
                    Text("\(Int(window.leftPercent.rounded()))%")
                        .foregroundStyle(color).monospacedDigit().fontWeight(.medium)
                }.font(.system(size: large ? 13 : compact ? 10 : 11))
                if settings.style == "trends" {
                    UsageSparkline(activity: activity, date: date, color: color)
                        .frame(height: large ? 18 : roomy ? 14 : 8)
                } else if settings.style == "clean" {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(color.opacity(0.12))
                            Capsule().fill(color).frame(width: geometry.size.width * window.leftPercent / 100)
                        }
                    }.frame(height: large ? 5 : 3).padding(.top, 2)
                }
                if large || !compact || roomy {
                    Text(stale ? "Old reading" : window.resetText(at: date) ?? "")
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
            Text(failed ? (status?.usageFailureText() ?? "Failed to load") : (compact ? "" : "Last refresh ") + WidgetStatus.updateDateLabel(status?.usageObservedAt))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Link(destination: URL(string: "live-ai-usage-widget://refresh")!) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh widget")
            Link(destination: URL(string: "live-ai-usage-widget://settings")!) { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .accessibilityLabel("Open settings")
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

struct UsageSparkline: View {
    let activity: [UsageActivity]
    let date: Date
    let color: Color
    @State private var hovered: UsageActivity?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let start = date.addingTimeInterval(-UsageHistory.span)
            let ceiling = max(activity.map(\.perMinute).max() ?? 0, 0.01)
            ZStack {
                // Join missing intervals to the measured trace, rather than drawing a second line underneath it.
                // Vertical connectors mark entry/exit from unknown coverage, not measured usage spikes.
                Path { path in
                    let baseline = max(1, geometry.size.height - 1)
                    var previous: UsageActivity?
                    var lastPoint = CGPoint(x: 0, y: baseline)
                    for item in activity {
                        let fromX = max(0, item.start.timeIntervalSince(start) / UsageHistory.span * geometry.size.width)
                        let x = item.end.timeIntervalSince(start) / UsageHistory.span * geometry.size.width
                        let y = (1 - item.perMinute / ceiling) * max(0, geometry.size.height - 2) + 1
                        if previous == nil || abs(item.start.timeIntervalSince(previous!.end)) >= 1 {
                            path.move(to: lastPoint)
                            path.addLine(to: CGPoint(x: lastPoint.x, y: baseline))
                            path.addLine(to: CGPoint(x: fromX, y: baseline))
                            path.addLine(to: CGPoint(x: fromX, y: y))
                        }
                        lastPoint = CGPoint(x: x, y: y)
                        previous = item
                    }
                    path.move(to: lastPoint)
                    path.addLine(to: CGPoint(x: lastPoint.x, y: baseline))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: baseline))
                }.stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                .widgetAccentable()
                Path { path in
                var previous: UsageActivity?
                for item in activity {
                    let x = item.end.timeIntervalSince(start) / UsageHistory.span * geometry.size.width
                    let y = (1 - item.perMinute / ceiling) * max(0, geometry.size.height - 2) + 1
                    let point = CGPoint(x: x, y: y)
                    if let previous, abs(item.start.timeIntervalSince(previous.end)) < 1 {
                        path.addLine(to: point)
                    } else {
                        // This first interval itself is measured; give even a solitary interval a visible line.
                        let fromX = max(0, item.start.timeIntervalSince(start) / UsageHistory.span * geometry.size.width)
                        path.move(to: CGPoint(x: fromX, y: y))
                        path.addLine(to: point)
                    }
                    previous = item
                }
                }.stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                .widgetAccentable()
            }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovering = true
                        let time = start.addingTimeInterval(location.x / max(1, geometry.size.width) * UsageHistory.span)
                        hovered = activity.first { $0.start <= time && time <= $0.end }
                    case .ended: hovered = nil; hovering = false
                    }
                }
        }
        .help(detail)
        .accessibilityLabel(detail)
    }

    private var detail: String {
        guard let point = hovering ? hovered : activity.last else {
            return "No recorded data. The flat line is a placeholder, not measured zero usage."
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "Past 6 hours · usage rate · scale per row. " + formatter.string(from: point.start) + "–" +
            formatter.string(from: point.end) + String(format: ": %.2f percentage points used, %.3f per minute average. Missing intervals use a flat placeholder, not measured zero usage.", point.percentagePoints, point.perMinute)
    }
}


struct WidgetPaper: View {
    var style: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if style == "solar" { (scheme == .dark ? Color(red: 0.157, green: 0.141, blue: 0.122) : Color(red: 1, green: 0.976, blue: 0.933)) }
        else { Color(nsColor: .windowBackgroundColor) }
    }
}
