import Foundation

@main
struct UsageHistoryTests {
    static func main() throws {
        let now = Date()
        let reset = now.addingTimeInterval(3600)
        func observation(_ minutes: Double, _ used: Double, resetAt: Date? = nil) -> UsageObservation {
            UsageObservation(date: now.addingTimeInterval(minutes * 60), usedPercent: used, resetsAt: resetAt ?? reset)
        }
        let real = [observation(-15, 10), observation(-10, 12), observation(-5, 12), observation(0, 15)]
        let activity = UsageHistory.activity(real, at: now)
        precondition(activity.count == 3)
        precondition(abs(activity[0].perMinute - 0.4) < 0.0001)
        precondition(activity[1].perMinute == 0) // measured quiet interval remains flat
        precondition(abs(activity[2].perMinute - 0.6) < 0.0001)
        precondition(UsageHistory.activity([real[0], real[0]], at: now).isEmpty)
        precondition(UsageHistory.activity([observation(-30, 10), real[3]], at: now).isEmpty)
        precondition(UsageHistory.activity([real[0], observation(-10, 2)], at: now).isEmpty)
        precondition(UsageHistory.activity([real[0], observation(-10, 14, resetAt: reset.addingTimeInterval(3600))], at: now).isEmpty)
        precondition(UsageHistory.activity([real[3], observation(5, 16)], at: now).isEmpty)
        precondition(UsageHistory.activity([observation(-5, 10), observation(0, 12, resetAt: now)], at: now).isEmpty)
        precondition(UsageHistory.activity([UsageObservation(date: real[0].date, usedPercent: 1, resetsAt: nil), real[1]], at: now).isEmpty)
        precondition(UsageHistory.activity([observation(-5, .nan), real[3]], at: now).isEmpty)
        let id = UsageHistory.key("claude", "5-hour")
        let source = AgentUsage(observedAt: now, windows: [UsageWindow(window: "5-hour", usedPercent: 15, resetsAt: reset)])
        let recorded = UsageHistory.recording([id: Array(real.prefix(3))], usage: ["claude": source], at: now)
        precondition(recorded[id]?.count == 4)
        let duplicate = UsageHistory.recording(recorded, usage: ["claude": source], at: now.addingTimeInterval(60))
        precondition(duplicate[id]?.count == 4)
        let late = AgentUsage(observedAt: now.addingTimeInterval(-600), windows: source.windows)
        precondition(UsageHistory.recording(recorded, usage: ["claude": late], at: now)[id]?.count == 4)
        let aged = UsageHistory.recording(recorded, usage: [:], at: now.addingTimeInterval(7 * 3600))
        precondition(aged.isEmpty)
        let crowded = (0..<1000).map { observation(-Double(1000 - $0) / 3, 10) }
        precondition(UsageHistory.recording([id: crowded], usage: [:], at: now)[id]?.count == UsageHistory.maximumPoints)
        let maximumHistory = Dictionary(uniqueKeysWithValues: ["claude:5-hour", "claude:weekly all", "claude:weekly Fable", "codex:5-hour", "codex:weekly"].map {
            ($0, Array(crowded.suffix(UsageHistory.maximumPoints)))
        })
        let encodedHistory = try JSONEncoder().encode(maximumHistory)
        precondition(encodedHistory.count < 240000) // leave room for usage and health metadata

        // Exercise persistence and both publishers, including a failed refresh carrying cached data.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("status.json")
        let iso = ISO8601DateFormatter()
        func payload(_ time: Date, _ used: Double, failed: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["usage": ["claude": [
                "status": "ok", "observed_at": iso.string(from: time),
                "refresh_status": failed ? "failed" : "ok",
                "last_attempt_at": iso.string(from: now),
                "last_failure_at": iso.string(from: now),
                "windows": [["window": "5-hour", "used_percent": used, "resets_at": iso.string(from: reset)]]
            ]]])
        }
        _ = try StatusStore.publishUsage(input: payload(now.addingTimeInterval(-300), 10), to: destination, enabled: ["claude"])
        let second = try StatusStore.publishUsage(input: payload(now, 12), to: destination, enabled: ["claude"])
        precondition(second.usageHistory?[id]?.count == 2)
        let third = try StatusStore.publishUsage(input: payload(now, 12, failed: true), to: destination, enabled: ["claude"])
        precondition(third.usageHistory?[id]?.count == 2)
        precondition(StatusStore.load(from: destination)?.usageHistory?[id]?.count == 2)
        let saved = try Data(contentsOf: destination)
        precondition(saved.count < 262144)
        // Limits a plan doesn't have: ChatGPT Pro has no 5-hour limit; Claude Pro has no model-specific weekly limit.
        precondition(WidgetStatus.notInPlan("codex", have: ["weekly"]) == ["5-hour"])
        precondition(WidgetStatus.notInPlan("codex", have: ["5-hour", "weekly"]).isEmpty)
        precondition(WidgetStatus.notInPlan("claude", have: ["5-hour", "weekly all"]) == ["weekly Fable"])
        precondition(WidgetStatus.notInPlan("claude", have: ["5-hour", "weekly all", "weekly Opus"]).isEmpty)
        precondition(WidgetStatus.notInPlan("claude", have: []).isEmpty)
        // Grok Bot: one weekly reading, published like the others, fading after 3 hours instead of 45 minutes.
        let grokDestination = directory.appendingPathComponent("grok-status.json")
        func grok(_ updated: Date, _ used: Double, shared: Bool = true) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["usage": ["grokbot": [
                "status": "ok", "observed_at": iso.string(from: updated), "refresh_status": "ok",
                "last_attempt_at": iso.string(from: now), "last_success_at": iso.string(from: updated),
                "shared_with_other_apps": shared, "maximum_age_seconds": 10800,
                "windows": [["window": "weekly", "used_percent": used, "resets_at": iso.string(from: now.addingTimeInterval(6 * 86400))]]
            ]]])
        }
        let grokStatus = try StatusStore.publishUsage(input: grok(now.addingTimeInterval(-3600), 7.2), to: grokDestination, enabled: ["claude", "grokbot"])
        let grokUsage = grokStatus.usage!["grokbot"]!
        precondition(grokUsage.windows.count == 1 && grokUsage.windows[0].usedPercent == 7.2 && grokUsage.sharedWithOtherApps == true)
        precondition(abs(grokUsage.windows[0].leftPercent - 92.8) < 0.0001 && grokUsage.windows[0].displayName == "Weekly")
        precondition(!grokUsage.isStale(at: now) && !grokUsage.isStale(at: now.addingTimeInterval(7100)))
        precondition(grokUsage.isStale(at: now.addingTimeInterval(7200)), "Older than 3 hours fades")
        precondition(grokStatus.usageHistory?[UsageHistory.key("grokbot", "weekly")]?.count == 1)
        // The 3-hour allowance and the shared note survive a later failed check.
        let missing = try JSONSerialization.data(withJSONObject: ["usage": ["grokbot": ["status": "ok", "refresh_status": "failed",
            "last_attempt_at": iso.string(from: now.addingTimeInterval(5)), "last_failure_at": iso.string(from: now.addingTimeInterval(5)), "failure_reason": "feed_missing", "windows": []]]])
        let grokFailed = try StatusStore.publishUsage(input: missing, to: grokDestination, enabled: ["grokbot"]).usage!["grokbot"]!
        precondition(grokFailed.refresh?.failureReason == .feedMissing && grokFailed.maximumAge == 10800 && grokFailed.sharedWithOtherApps == true)
        precondition(grokFailed.windows.count == 1)
        let unshared = try StatusStore.publishUsage(input: grok(now, 9, shared: false), to: grokDestination, enabled: ["grokbot"])
        precondition(unshared.usage!["grokbot"]!.sharedWithOtherApps == false)
        // Turning Grok Bot off hides it; unknown accounts are still dropped from settings.
        let hidden = try StatusStore.publishUsage(input: grok(now, 9), to: grokDestination, enabled: ["claude"])
        precondition(hidden.usage?["grokbot"] == nil)
        let decoded = try JSONDecoder().decode(WidgetSettings.self, from: Data(#"{"enabled":["claude","grokbot","other"]}"#.utf8))
        precondition(decoded.enabled == ["claude", "grokbot"])
        precondition(WidgetStatus.name("grokbot") == "Grok Bot" && WidgetStatus.expectedWindows("grokbot") == ["weekly"])
        precondition(WidgetStatus.notInPlan("grokbot", have: ["weekly"]).isEmpty)
        // The footer time follows the tool accounts; Grok Bot's hourly file sets it only when it is the only account.
        let mixed = WidgetStatus(usage: ["codex": AgentUsage(observedAt: now, windows: []), "grokbot": AgentUsage(observedAt: now.addingTimeInterval(-3000), windows: [])])
        precondition(mixed.usageObservedAt == now)
        precondition(WidgetStatus(usage: ["grokbot": grokUsage]).usageObservedAt == grokUsage.observedAt)
        print("Usage history checks passed: real rates, quiet intervals, resets, gaps, missing reset identity, clock skew, duplicates, retention, bounded storage, standalone store and failed-refresh persistence, limits not in plan, Grok Bot readings")
    }
}
