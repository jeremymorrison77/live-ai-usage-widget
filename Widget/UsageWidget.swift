import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: WidgetStatus?
    var sample = false
}
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { StatusEntry(date: Date(), status: .preview, sample: true) }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(context.isPreview ? StatusEntry(date: Date(), status: .preview, sample: true) : StatusEntry(date: Date(), status: StatusStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date()
        let status = StatusStore.load()
        try? StatusStore.recordTimelineRead(status: status, at: now)
        // Future entries age the visible snapshot even if collection stops.
        var entries = (Array(0...30) + Array(stride(from: 35, through: 180, by: 5))).map {
            StatusEntry(date: now.addingTimeInterval(Double($0) * 60), status: status)
        }
        // While a requested check runs, one entry a second turns the refresh arrow (for at most two minutes).
        if let since = status?.checkingSince, status?.checking(at: now) == true {
            let start = max(now, since).timeIntervalSince(since).rounded(.up)
            let ticks = stride(from: start, to: 120, by: 1).map { StatusEntry(date: since.addingTimeInterval($0), status: status) }
            entries = ticks + entries.filter { $0.date >= since.addingTimeInterval(120) }
            entries.insert(StatusEntry(date: now, status: status), at: 0)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(300))))
    }
}
struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: StatusEntry
    // The gallery preview shows both providers with sample readings, even before setup.
    private var settings: WidgetSettings {
        var value = WidgetSettings.load()
        if entry.sample { value.enabled = ["claude", "codex"]; value.hiddenSmallMetrics = [] }
        return value
    }
    var body: some View {
        StatusView(status: entry.status, date: entry.date, compact: family == .systemSmall, large: family == .systemLarge, settings: settings)
            .containerBackground(for: .widget) { WidgetPaper(style: WidgetSettings.load().style) }
    }
}
@main
struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StatusStore.kind, provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName("Live AI Usage Widget")
            .description("Claude Code and ChatGPT Codex usage remaining.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
