import Foundation
import Darwin

struct UsageWindow: Codable {
    let window: String
    let usedPercent: Double
    let resetsAt: Date?
}

/// Only provider observations, never publication times or interpolated samples.
struct UsageObservation: Codable {
    let date: Date
    let usedPercent: Double
    let resetsAt: Date?
}

struct UsageActivity: Equatable {
    let start: Date
    let end: Date
    let percentagePoints: Double
    var perMinute: Double { percentagePoints / (end.timeIntervalSince(start) / 60) }
}

enum UsageHistory {
    static let span: TimeInterval = 6 * 3600
    static let maximumGap: TimeInterval = 12 * 60
    static let maximumPoints = 121
    static func key(_ agent: String, _ window: String) -> String { agent + ":" + window }

    static func recording(_ old: [String: [UsageObservation]], usage: [String: AgentUsage],
                          at now: Date) -> [String: [UsageObservation]] {
        var result: [String: [UsageObservation]] = [:]
        for agent in ["claude", "codex"] {
            for name in Set((usage[agent]?.windows.map(\.window) ?? []) + old.keys.filter { $0.hasPrefix(agent + ":") }.map { String($0.dropFirst(agent.count + 1)) }).sorted().prefix(8) {
                let id = key(agent, name)
                var samples = (old[id] ?? []).filter {
                    $0.date <= now && now.timeIntervalSince($0.date) <= span + maximumGap &&
                    $0.usedPercent.isFinite && (0...100).contains($0.usedPercent)
                }.sorted { $0.date < $1.date }
                if let source = usage[agent], let observed = source.observedAt,
                   observed <= now, now.timeIntervalSince(observed) <= span,
                   let window = source.windows.first(where: { $0.window == name }),
                   window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
                   observed > (samples.last?.date ?? .distantPast) {
                    // Same-minute receipts replace each other, keeping storage bounded without inventing points.
                    if let last = samples.last,
                       Int(last.date.timeIntervalSince1970 / 60) == Int(observed.timeIntervalSince1970 / 60) {
                        samples.removeLast()
                    }
                    samples.append(UsageObservation(date: observed, usedPercent: window.usedPercent, resetsAt: window.resetsAt))
                }
                if !samples.isEmpty { result[id] = Array(samples.suffix(maximumPoints)) }
            }
        }
        return result
    }

    static func activity(_ samples: [UsageObservation], at now: Date) -> [UsageActivity] {
        zip(samples, samples.dropFirst()).compactMap { before, after in
            let elapsed = after.date.timeIntervalSince(before.date)
            // Do not bridge a reset, counter correction, missing reset identity, long outage or future clock.
            guard elapsed >= 30, elapsed <= maximumGap, after.date <= now,
                  before.date >= now.addingTimeInterval(-span),
                  let reset = before.resetsAt, let nextReset = after.resetsAt,
                  abs(reset.timeIntervalSince(nextReset)) <= 90,
                  before.date < reset, after.date < reset,
                  after.usedPercent.isFinite, before.usedPercent.isFinite,
                  (0...100).contains(before.usedPercent), (0...100).contains(after.usedPercent),
                  after.usedPercent >= before.usedPercent else { return nil }
            return UsageActivity(start: before.date, end: after.date,
                                 percentagePoints: after.usedPercent - before.usedPercent)
        }
    }
}

/// Refresh attempts have their own clock; a failed attempt never makes cached usage look current.
enum UsageRefreshStatus: String, Codable { case ok, failed, unknown }

enum UsageFailureReason: String, Codable {
    case cliUpdateRequired = "cli_update_required"
    case signInRequired = "sign_in_required"
    case interactiveSetupRequired = "interactive_setup_required"
    case rateLimited = "rate_limited"
    case usageReadTimedOut = "usage_read_timed_out"
    case usagePanelIncomplete = "usage_panel_incomplete"
    case resetFormatChanged = "reset_format_changed"
    case resetOutOfRange = "reset_out_of_range"
    case invalidUsage = "invalid_usage"
    case terminalBounds = "terminal_bounds"
    case outputTooLarge = "output_too_large"
    case probeDirectoryUnavailable = "probe_directory_unavailable"
    case snapshotWriteFailed = "snapshot_write_failed"
    case unavailable

    func actionLabel(agent: String) -> String {
        switch self {
        case .cliUpdateRequired: return "Update \(agent)"
        case .signInRequired: return "Sign in to \(agent)"
        case .interactiveSetupRequired: return "Open \(agent) to finish setup"
        case .rateLimited: return "Rate limited · will retry"
        case .usageReadTimedOut: return "Timed out · will retry"
        default: return "Will retry automatically"
        }
    }
}

struct UsageRefresh: Codable {
    let status: UsageRefreshStatus
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let lastFailureAt: Date?
    let failureReason: UsageFailureReason?
}

struct AgentUsage: Codable {
    let observedAt: Date?
    let windows: [UsageWindow]
    var refresh: UsageRefresh? = nil
    // Readings fade after 45 minutes, or later when checks are spaced further apart.
    static var staleAfter: TimeInterval { max(45 * 60, Double(WidgetSettings.load().refreshMinutes) * 90) }

    func isStale(at date: Date) -> Bool {
        guard let observedAt else { return true }
        return date.timeIntervalSince(observedAt) >= AgentUsage.staleAfter || observedAt.timeIntervalSince(date) > 30
    }
    static func resetLabel(_ reset: Date, at date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // Same day: time only. Within the next six days: weekday. A week or more away (a weekly reset lands on
        // today's weekday) : month/day, so "Sun 5:16 AM" never reads as already past.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: reset)).day ?? 0
        let clock = WidgetSettings.load().usDates ? "h:mm a" : "HH:mm"
        formatter.dateFormat = days == 0 ? clock : days < 7 ? "EEE " + clock : (WidgetSettings.load().usDates ? "M/d " : "d/M ") + clock
        return formatter.string(from: reset)
    }
    /// Small-widget name: "weekly all" and "weekly" become "week"; "weekly Fable" stays as is.
    static func compactName(_ name: String) -> String {
        name.replacingOccurrences(of: "weekly all", with: "week").replacingOccurrences(of: "weekly", with: "week")
    }
    /// Plain-words summary, e.g. "5-hour 42% used · weekly 10% used". Without resets (small widget) only the
    /// first two windows are shown, so Claude reads "5-hour 9% · week 94%" and the Fable line waits for the medium size.
    func summary(at date: Date, withResets: Bool, calendar: Calendar = .current) -> String {
        let shown = withResets ? windows : Array(windows.prefix(2))
        let parts = shown.map { window -> String in
            var text = "\(withResets ? window.window : AgentUsage.compactName(window.window)) \(Int(window.usedPercent.rounded()))%\(withResets ? " used" : "")"
            if withResets, let reset = window.resetsAt, reset > date {
                text += ", resets \(AgentUsage.resetLabel(reset, at: date, calendar: calendar))"
            }
            return text
        }
        let joined = parts.isEmpty ? "unavailable" : parts.joined(separator: " · ")
        return isStale(at: date) ? joined + " (old reading)" : joined
    }
}

/// How much of a limit is left, graded the same way for Claude and Codex.
/// `critical` (5% left) is Claude Code's own "approaching your usage limit" point: Claude Code 2.1.280 checkpoints the
/// session at utilization 0.95 (0.99 on Max 5x, 0.9975 on Max 20x). Claude's own usage bars have no separate
/// warning tint, so `warning` (20% left) is this project's choice, not a confirmed Claude threshold.
enum UsageLevel: Equatable {
    case normal, warning, critical
    static let warningLeftPercent: Double = 20
    static let criticalLeftPercent: Double = 5
    static func grade(leftPercent: Double) -> UsageLevel {
        if leftPercent <= criticalLeftPercent { return .critical }
        if leftPercent <= warningLeftPercent { return .warning }
        return .normal
    }
    /// Plain word shown beside the percent so the state reads without color (desktop widgets are tinted).
    var word: String? {
        switch self {
        case .normal: return nil
        case .warning: return "low"
        case .critical: return "almost out"
        }
    }
}

extension UsageWindow {
    /// Bar-row name in plain words: "Session" (5-hour), "Weekly" (weekly / weekly all), "Fable" (weekly Fable).
    var displayName: String {
        switch window {
        case "5-hour": return "Session"
        case "weekly", "weekly all": return "Weekly"
        case "weekly Fable": return "Fable"
        default: return window
        }
    }
    var leftPercent: Double { min(max(100 - usedPercent, 0), 100) }
    var leftLabel: String { "\(Int(leftPercent.rounded()))% left" }
    /// Filled share of the bar: what is left.
    var leftFraction: Double { leftPercent / 100 }
    var level: UsageLevel { UsageLevel.grade(leftPercent: leftPercent) }
    func resetText(at date: Date, calendar: Calendar = .current) -> String? {
        guard let resetsAt, resetsAt > date else { return nil }
        return "resets " + AgentUsage.resetLabel(resetsAt, at: date, calendar: calendar)
    }
}

struct WidgetStatus: Codable {
    var usage: [String: AgentUsage]? = nil
    var usageHistory: [String: [UsageObservation]]? = nil
    /// Set while a check the user asked for is running, so the widget can show progress.
    var checkingSince: Date? = nil
    /// When the new reading should grow in: a moment after the check ends, so the widget shows empty, then full.
    var revealAt: Date? = nil
    /// True while that check runs (never longer than two minutes, in case the app quit mid-check).
    func checking(at date: Date) -> Bool { checkingSince.map { date >= $0.addingTimeInterval(-5) && date.timeIntervalSince($0) < 120 } ?? false }
    /// Readings show as empty while checking and until the reveal moment.
    func emptied(at date: Date) -> Bool { checking(at: date) }
    /// Sample readings for the widget gallery only; never written to storage.
    static var preview: WidgetStatus {
        let now = Date(), hour: TimeInterval = 3600
        let ok = UsageRefresh(status: .ok, lastAttemptAt: now, lastSuccessAt: now, lastFailureAt: nil, failureReason: nil)
        return WidgetStatus(usage: [
            "claude": AgentUsage(observedAt: now, windows: [UsageWindow(window: "5-hour", usedPercent: 38, resetsAt: now.addingTimeInterval(2.2 * hour)),
                                                           UsageWindow(window: "weekly all", usedPercent: 76, resetsAt: now.addingTimeInterval(74 * hour))], refresh: ok),
            "codex": AgentUsage(observedAt: now, windows: [UsageWindow(window: "5-hour", usedPercent: 18, resetsAt: now.addingTimeInterval(3.4 * hour)),
                                                          UsageWindow(window: "weekly", usedPercent: 92, resetsAt: now.addingTimeInterval(118 * hour))], refresh: ok)])
    }
    // Usage freshness is independent of recording and health publication.
    var usageObservedAt: Date? {
        ["claude", "codex"].compactMap { usage?[$0]?.observedAt }.min()
    }
    /// Only an explicit failed attempt is a failure. Old cache files have no such evidence.
    var usageFailure: (agent: String, refresh: UsageRefresh)? {
        ["claude", "codex"].compactMap { key -> (agent: String, refresh: UsageRefresh)? in
            guard let refresh = usage?[key]?.refresh, refresh.status == .failed else { return nil }
            // Being asked to wait (rate limited) isn't a failure while the last reading is still fresh.
            if refresh.failureReason == .rateLimited, usage?[key]?.isStale(at: Date()) == false { return nil }
            return (Self.name(key), refresh)
        }.max { ($0.refresh.lastFailureAt ?? $0.refresh.lastAttemptAt ?? .distantPast) <
            ($1.refresh.lastFailureAt ?? $1.refresh.lastAttemptAt ?? .distantPast) }
    }
    /// The limits each account usually reports, shown as placeholders until its first reading arrives.
    static func expectedWindows(_ provider: String) -> [String] { provider == "claude" ? ["5-hour", "weekly all", "weekly Fable"] : ["5-hour", "weekly"] }
    /// Limits this account's plan does not have, judged from a real reading. Per the official plan pages
    /// (10/18/2026): ChatGPT Pro has no 5-hour limit, and only Claude Max and Premium seats have a weekly Fable
    /// limit. Any model-specific weekly limit counts as that plan's model limit.
    static func notInPlan(_ provider: String, have: [String]) -> [String] {
        guard !have.isEmpty else { return [] }
        return expectedWindows(provider).filter { want in
            if want == "weekly Fable" { return !have.contains { $0.hasPrefix("weekly ") && $0 != "weekly all" } }
            return !have.contains(want)
        }
    }
    /// The one name used for each account everywhere.
    static func name(_ provider: String) -> String { provider == "claude" ? "Claude Code" : "ChatGPT Codex" }
    static func updateDateLabel(_ date: Date?, calendar: Calendar = .current) -> String {
        guard let date else { return "time unknown" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = WidgetSettings.load().usDates ? "M/d h:mm a" : "d/M HH:mm"
        return formatter.string(from: date)
    }
    func usageFailureText(calendar: Calendar = .current) -> String? {
        guard let failure = usageFailure else { return nil }
        return "Failed last update " + Self.updateDateLabel(failure.refresh.lastFailureAt ?? failure.refresh.lastAttemptAt, calendar: calendar)
    }
    /// When an account has asked the app to wait (checked too often), the time the app will try it again.
    /// The wait is the app's own (15 minutes, or the check interval if longer); Anthropic doesn't publish one.
    func pausedUntil(at now: Date = Date()) -> Date? {
        let wait = max(900, Double(WidgetSettings.load().refreshMinutes) * 60)
        return ["claude", "codex"].compactMap { key -> Date? in
            guard let refresh = usage?[key]?.refresh, refresh.status == .failed, refresh.failureReason == .rateLimited,
                  let failed = refresh.lastFailureAt, failed.addingTimeInterval(wait) > now else { return nil }
            return failed.addingTimeInterval(wait)
        }.max()
    }
    /// Settings' wording for the same pause.
    func pausedText(at now: Date = Date()) -> String? {
        guard let retry = pausedUntil(at: now) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = WidgetSettings.load().usDates ? "h:mm a" : "HH:mm"
        return "Too many refreshes. Waiting until " + formatter.string(from: retry) + " to try again."
    }
    func usageLastSuccessText(compact: Bool = false, calendar: Calendar = .current) -> String? {
        guard let failure = usageFailure else { return nil }
        let candidates = [failure.refresh.lastSuccessAt, usage?[failure.agent == Self.name("claude") ? "claude" : "codex"]?.observedAt].compactMap { $0 }
        guard !candidates.isEmpty else { return compact ? "No successful update yet" : "Last successful update: none yet" }
        let lastSuccess = candidates.filter { $0 <= Date().addingTimeInterval(30) }.max()
        return (compact ? "Last OK " : "Last successful update ") + Self.updateDateLabel(lastSuccess, calendar: calendar)
    }
    func usageWarning(at date: Date) -> String? {
        if let failure = usageFailureText() { return failure }
        if (usage ?? [:]).values.contains(where: { $0.isStale(at: date) || $0.windows.contains(where: { $0.resetsAt.map { $0 <= date } == true }) }) { return "Usage readings need refresh" }
        return nil
    }

}

struct UsageInputModel {
    struct UsageWindowInput: Decodable { let window: String?; let used_percent: Double?; let resets_at: String? }
    struct UsageInput: Decodable {
        let status: String?
        let observed_at: String?
        let windows: [UsageWindowInput]?
        let refresh_status: String?
        let last_attempt_at: String?
        let last_success_at: String?
        let last_failure_at: String?
        let failure_reason: String?

        var refresh: UsageRefresh? {
            guard let rawStatus = refresh_status, let status = UsageRefreshStatus(rawValue: rawStatus) else { return nil }
            return UsageRefresh(status: status, lastAttemptAt: UsageInputModel.parseDate(last_attempt_at),
                lastSuccessAt: UsageInputModel.parseDate(last_success_at), lastFailureAt: UsageInputModel.parseDate(last_failure_at),
                failureReason: status == .failed ? UsageFailureReason(rawValue: failure_reason ?? "") ?? .unavailable : nil)
        }
    }
    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }


    static func agentUsage(_ inputs: [String: UsageInput]) -> [String: AgentUsage] {
        var result: [String: AgentUsage] = [:]
        for (name, input) in inputs where ["claude", "codex"].contains(name) {
            let windows = (input.status == "ok" ? input.windows ?? [] : []).compactMap { item -> UsageWindow? in
                guard let name = item.window, let used = item.used_percent, used.isFinite, (0...100).contains(used) else { return nil }
                return UsageWindow(window: name, usedPercent: used, resetsAt: UsageInputModel.parseDate(item.resets_at))
            }
            if !windows.isEmpty || input.refresh != nil {
                result[name] = AgentUsage(observedAt: windows.isEmpty ? nil : UsageInputModel.parseDate(input.observed_at),
                    windows: windows, refresh: input.refresh)
            }
        }
        return result
    }

}

enum StoreError: Error { case sharedContainerUnavailable, invalidDate, oversized, oldSnapshot, lockUnavailable }

enum StatusStore {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "UsageAppGroup") as? String ?? "" }
    static let kind = "UsageWidget"
    static func fileURL() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { throw StoreError.sharedContainerUnavailable }
        return root.appendingPathComponent("status.json")
    }
    // Diagnostic receipt contains only timestamps, never account or conversation data.
    static func recordTimelineRead(status: WidgetStatus?, at date: Date, to url: URL? = nil) throws {
        let destination = try url ?? fileURL().deletingLastPathComponent().appendingPathComponent("timeline-read.json")
        var receipt = ["read_at": date.timeIntervalSince1970]
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, let number = Double(build) {
            receipt["build"] = number
        }
        for (agent, usage) in status?.usage ?? [:] {
            if let observed = usage.observedAt { receipt[agent + "_observed_at"] = observed.timeIntervalSince1970 }
        }
        try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]).write(to: destination, options: .atomic)
    }
    static func load(from url: URL? = nil) -> WidgetStatus? {
        guard let file = try? url ?? fileURL(), let data = try? Data(contentsOf: file), data.count < 262144
        else { return nil }
        return try? JSONDecoder().decode(WidgetStatus.self, from: data)
    }
    /// A reading clicked on the small widget shows its reset time for a few seconds: which one, and until when.
    static var revealURL: URL? { try? fileURL().deletingLastPathComponent().appendingPathComponent("reveal.json") }
    static func reveal(_ key: String, for seconds: TimeInterval = 4) throws {
        guard let url = revealURL else { return }
        try JSONEncoder().encode(Reveal(key: key, until: Date().addingTimeInterval(seconds))).write(to: url, options: .atomic)
    }
    static func reveal(at date: Date) -> Reveal? {
        guard let url = revealURL, let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Reveal.self, from: data),
              value.until > date else { return nil }
        return value
    }
    struct Reveal: Codable { let key: String; let until: Date }
    /// The widget's request for a check, picked up by the app as soon as it is written.
    static var checkRequestURL: URL? { try? fileURL().deletingLastPathComponent().appendingPathComponent("check-request") }
    static func requestCheck() throws {
        guard let url = checkRequestURL else { return }
        try Data().write(to: url, options: .atomic)
    }
    /// Marks a user-requested check as started (a date) or finished (nil).
    static func setChecking(_ date: Date?, to url: URL? = nil) throws {
        let destination = try url ?? fileURL()
        try locked(destination) {
            var value = load(from: destination) ?? WidgetStatus()
            if date == nil, value.checkingSince != nil { value.revealAt = Date().addingTimeInterval(1) }
            value.checkingSince = date
            try JSONEncoder().encode(value).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }
    /// Only successful source observations can advance the reading timestamp.
    static func publishUsage(input: Data, to url: URL? = nil, enabled: [String]? = nil) throws -> WidgetStatus {
        struct Update: Decodable { let usage: [String: UsageInputModel.UsageInput] }
        guard input.count < 262144 else { throw StoreError.oversized }
        let update = try JSONDecoder().decode(Update.self, from: input)
        let destination = try url ?? fileURL()
        return try locked(destination) {
            var value = load(from: destination) ?? WidgetStatus()
            value.usage = merged(value.usage ?? [:], UsageInputModel.agentUsage(update.usage))
            value.usage = value.usage?.filter { (enabled ?? WidgetSettings.load().enabled).contains($0.key) }
            value.usageHistory = UsageHistory.recording(value.usageHistory ?? [:], usage: value.usage ?? [:], at: Date())
            try JSONEncoder().encode(value).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return value
        }
    }

    static func merged(_ old: [String: AgentUsage], _ new: [String: AgentUsage]) -> [String: AgentUsage] {
        var result = old
        let latestAllowed = Date().addingTimeInterval(30)
        for (key, value) in new where ["claude", "codex"].contains(key) {
            let previous = result[key]
            // Source observations and refresh attempts can arrive through separate publishers in either order.
            let previousObserved = (previous?.observedAt).flatMap { $0 <= latestAllowed ? $0 : nil }
            let useReading = !value.windows.isEmpty && value.observedAt.map {
                $0 <= latestAllowed && $0 >= (previousObserved ?? .distantPast)
            } == true
            let refresh = mergedRefresh(previous?.refresh, value.refresh, latestAllowed: latestAllowed)
            if useReading || previous != nil || refresh != nil {
                result[key] = AgentUsage(observedAt: useReading ? value.observedAt : previous?.observedAt,
                    windows: useReading ? value.windows : previous?.windows ?? [], refresh: refresh)
            }
        }
        return result
    }

    private static func mergedRefresh(_ old: UsageRefresh?, _ new: UsageRefresh?, latestAllowed: Date) -> UsageRefresh? {
        guard let new else { return old }
        // Reject future clocks for the incoming outcome. A historical failure retained on recovery may
        // come from a corrected system clock; discard that date without discarding the valid recovery.
        let newOutcome = new.status == .ok ? new.lastSuccessAt : new.status == .failed ? new.lastFailureAt : nil
        guard [new.lastAttemptAt, newOutcome].compactMap({ $0 }).allSatisfy({ $0 <= latestAllowed }) else { return old }
        func plausible(_ stamp: Date?) -> Date? { stamp.flatMap { $0 <= latestAllowed ? $0 : nil } }
        // A verified fallback receipt can recover an existing attempt without starting another probe.
        // Compare outcome times as well as attempt starts; historical failure dates never age an OK result.
        func outcomeStamp(_ refresh: UsageRefresh?) -> Date? {
            guard let refresh else { return nil }
            let outcome = refresh.status == .ok ? refresh.lastSuccessAt : refresh.status == .failed ? refresh.lastFailureAt : nil
            return [refresh.lastAttemptAt, outcome].compactMap { plausible($0) }.max()
        }
        let oldStamp = outcomeStamp(old)
        let newStamp = outcomeStamp(new)
        let chosen: UsageRefresh
        if old == nil || newStamp.map({ $0 > (oldStamp ?? .distantPast) }) == true { chosen = new }
        else { chosen = old! }
        return UsageRefresh(status: chosen.status, lastAttemptAt: plausible(chosen.lastAttemptAt),
            lastSuccessAt: [old?.lastSuccessAt, new.lastSuccessAt].compactMap({ plausible($0) }).max(),
            lastFailureAt: chosen.status == .failed ? plausible(chosen.lastFailureAt) : [old?.lastFailureAt, new.lastFailureAt].compactMap({ plausible($0) }).max(),
            failureReason: chosen.status == .failed ? chosen.failureReason : nil)
    }

    static func locked<T>(_ destination: URL, action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(destination.path + ".lock", O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw StoreError.lockUnavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw StoreError.lockUnavailable }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
}
