import Foundation
import Darwin

/// Shared by the app worker and deterministic tests; stores no raw provider output.
enum Collector {
    static func collect(previous: [String: Any], providers: [String], now: Date,
                        read: (String) throws -> [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for provider in providers where ["claude", "codex"].contains(provider) {
            var value = previous[provider] as? [String: Any] ?? [:]
            if let due = value["next_attempt_epoch"] as? Double,
               due > now.timeIntervalSince1970, due <= now.timeIntervalSince1970+900 { result[provider] = value; continue }
            let stamp = UsageReader.iso(now)
            value["last_attempt_at"] = stamp
            do {
                let reading = try read(provider)
                value.merge(reading) { _, new in new }
                value["refresh_status"] = "ok"; value["last_success_at"] = reading["observed_at"]
                value.removeValue(forKey: "failure_reason"); value["next_attempt_epoch"] = now.timeIntervalSince1970+300
            } catch {
                let allowed = ["cli_update_required", "sign_in_required", "interactive_setup_required", "cli_unavailable", "rate_limited", "usage_read_timed_out", "usage_panel_incomplete", "reset_format_changed", "reset_out_of_range", "invalid_usage", "terminal_bounds", "output_too_large", "unavailable"]
                let reason = (error as? ReaderFailure)?.reason ?? "unavailable"
                value["refresh_status"] = "failed"; value["last_failure_at"] = stamp
                value["failure_reason"] = allowed.contains(reason) ? reason : "unavailable"
                value["next_attempt_epoch"] = now.timeIntervalSince1970+900
                if value["status"] == nil { value["status"] = "unavailable"; value["windows"] = [] }
            }
            result[provider] = value
        }
        return result
    }
    static func run(root: URL, generation: String, providers: [String]) throws -> Data {
        umask(0o077)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(root.appendingPathComponent("collection.lock").path, O_CREAT|O_RDWR|O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ReaderFailure("unavailable") }; defer { close(fd) }
        guard flock(fd, LOCK_EX|LOCK_NB) == 0 else { throw ReaderFailure("busy") }; defer { flock(fd, LOCK_UN) }
        let file = root.appendingPathComponent("collection.json")
        var previous: [String: Any] = [:]
        if let data = try? Data(contentsOf: file), data.count < 262144,
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], value["_generation"] as? String == generation { previous = value }
        let probe = root.appendingPathComponent("probe", isDirectory: true)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: probe.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw ReaderFailure("unavailable") }
        try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = collect(previous: previous, providers: providers, now: Date()) { provider in
            try provider == "claude" ? UsageReader.claude(directory: probe) : UsageReader.codex(directory: probe)
        }
        var saved = result; saved["_generation"] = generation
        try JSONSerialization.data(withJSONObject: saved, options: [.sortedKeys]).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return try JSONSerialization.data(withJSONObject: ["usage": result], options: [.sortedKeys])
    }
}
