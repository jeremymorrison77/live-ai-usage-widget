import Foundation

/// A short private activity log for troubleshooting, plus the report a user can choose to send.
/// Kept in ~/Library/Logs/Live AI Usage Widget/activity.log: only the past three days, and never more than 256 KB.
/// Never records account names, emails, passwords, sign-in codes, links or conversation content.
enum Diagnostics {
    static let keptFor: TimeInterval = 3 * 86400
    static let maximumBytes = 256 * 1024
    private static let queue = DispatchQueue(label: "diagnostics")
    nonisolated(unsafe) static var folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Live AI Usage Widget")
    static var file: URL { folder.appendingPathComponent("activity.log") }
    static let marker = "=== Launch "

    /// Starts a new launch section and drops anything older than three days.
    static func startLaunch(_ details: String) {
        queue.sync {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let old = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            try? (recent(old, now: Date()) + marker + stamp(Date()) + " · " + clean(details) + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }

    static func log(_ event: String) {
        let line = stamp(Date()) + "  " + clean(event) + "\n"
        queue.async {
            guard let handle = try? FileHandle(forWritingTo: file) else { try? line.write(to: file, atomically: true, encoding: .utf8); return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            // Stay small even if one launch runs for weeks.
            if let size = try? handle.offsetInFile, size > UInt64(maximumBytes) {
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                try? String(text.suffix(maximumBytes / 2)).write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Only the lines from the past three days (and at most half the size limit), oldest first.
    static func recent(_ text: String, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yyyy h:mm:ss a"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).filter { line in
            let body = line.hasPrefix(marker) ? line.dropFirst(marker.count) : line[...]
            guard let date = formatter.date(from: String(body.prefix(22)).trimmingCharacters(in: .whitespaces))
                ?? formatter.date(from: String(body.prefix(21)).trimmingCharacters(in: .whitespaces)) else { return false }
            return now.timeIntervalSince(date) <= keptFor
        }
        let kept = lines.joined(separator: "\n")
        return kept.isEmpty ? "" : String(kept.suffix(maximumBytes / 2)) + "\n"
    }

    static func contents() -> String { queue.sync { recent((try? String(contentsOf: file, encoding: .utf8)) ?? "", now: Date()) } }

    /// Removes anything personal: the home folder name, email addresses, web links and long secret-looking strings.
    static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        for (pattern, replacement) in [("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "[email]"),
                                       ("https?://[^\\s\"'<>]+", "[link]"),
                                       ("[A-Za-z0-9_\\-]{32,}", "[hidden]")] {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return value.replacingOccurrences(of: "\n", with: " ")
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yyyy h:mm:ss a"
        return formatter.string(from: date)
    }

    /// Asks an official tool for its version, giving up after a few seconds.
    static func toolVersion(_ binary: String) -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--version"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "unknown" }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return "unknown" }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return clean(text.trimmingCharacters(in: .whitespacesAndNewlines)).prefix(60).description
    }
}
