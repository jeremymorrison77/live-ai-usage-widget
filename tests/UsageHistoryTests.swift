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
        print("Usage history checks passed: real rates, quiet intervals, resets, gaps, missing reset identity, clock skew, duplicates, retention, bounded storage, standalone store and failed-refresh persistence")
    }
}
