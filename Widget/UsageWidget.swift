import SwiftUI
import WidgetKit
import AppIntents

/// The widget's refresh button. It runs inside the widget, so "Checking…" shows the moment it is clicked;
/// the app, watching for the request, then checks usage.
struct CheckUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Check usage now"
    func perform() async throws -> some IntentResult {
        try? StatusStore.setChecking(Date())
        try? StatusStore.requestCheck()
        return .result()
    }
}

/// Clicking a reading on the small widget shows its reset time for a few seconds.
struct ShowResetIntent: AppIntent {
    static var title: LocalizedStringResource = "Show when a limit resets"
    static var isDiscoverable = false
    @Parameter(title: "Reading") var key: String
    init() {}
    init(key: String) { self.key = key }
    func perform() async throws -> some IntentResult {
        try? StatusStore.reveal(key)
        return .result()
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: WidgetStatus?
    var sample = false
    var reveal: String? = nil
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
        var entries = Array(stride(from: 0, through: 180, by: 5)).map {
            StatusEntry(date: now.addingTimeInterval(Double($0) * 60), status: status)
        }
        // While a requested check runs, one entry a second turns the spinner. Mac draws every entry before showing
        // the first, so only a few seconds are planned at a time; the widget asks again when they run out.
        // A clicked reading shows its reset time, then the widget goes back to normal. Only two entries: Mac draws
        // every planned entry before showing the first, so a long plan here delays the click by seconds.
        if let reveal = StatusStore.reveal(at: now) {
            completion(Timeline(entries: [StatusEntry(date: now, status: status, reveal: reveal.key), StatusEntry(date: reveal.until, status: status)],
                                policy: .after(reveal.until)))
            return
        }
        if status?.checking(at: now) == true {
            let ticks = (1...3).map { StatusEntry(date: now.addingTimeInterval(Double($0)), status: status) }
            completion(Timeline(entries: [StatusEntry(date: now, status: status)] + ticks, policy: .after(now.addingTimeInterval(3))))
            return
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
        StatusView(status: entry.status, date: entry.date, compact: family == .systemSmall, large: family == .systemLarge, settings: settings, reveal: entry.reveal)
            .containerBackground(for: .widget) { WidgetPaper(style: WidgetSettings.load().style) }
    }
}
@main
struct UsageWidget: Widget {
    init() { RefreshButton.intent = CheckUsageIntent(); RevealButton<EmptyView>.intent = { ShowResetIntent(key: $0) } }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StatusStore.kind, provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName("Live AI Usage Widget")
            .description("How much of your Claude Code and ChatGPT Codex limits is left or used.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
