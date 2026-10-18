import Foundation
import Darwin

@main struct ReaderTests {
    static func main() throws {
        signal(SIGPIPE, SIG_IGN)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T10:00:00Z")!
        let window: [String: Any] = ["usedPercent": 25.5, "windowDurationMins": 10080, "resetsAt": 1792650147]
        let result = try UsageReader.codexLimits(["rateLimits": ["primary": window], "email": "private@example.invalid"], at: now)
        precondition((result["windows"] as! [[String: Any]])[0]["used_percent"] as? Double == 25.5)
        let json = try JSONSerialization.data(withJSONObject: result)
        precondition(!String(data: json, encoding: .utf8)!.contains("private"))
        func fails(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch {} }
        for invalid: Any in [true, Double.nan, 101, -1] {
            var bad = window; bad["usedPercent"] = invalid
            fails { _ = try UsageReader.codexLimits(["rateLimits": ["primary": bad]], at: now) }
        }
        fails { _ = try UsageReader.codexLimits(["rateLimitsByLimitId": ["other": ["primary": window]], "rateLimits": ["primary": window]], at: now) }
        let panel = "Current session\n12% used\nResets 1pm (Europe/London)\nCurrent week (Example)\n30% used\nResets Oct 20 at 1pm (Europe/London)"
        let claude = try UsageReader.claudePanel(panel, now: now)
        let windows = claude["windows"] as! [[String: Any]]
        precondition(windows.count == 2 && windows[1]["window"] as? String == "weekly Example")
        precondition(windows[0]["resets_at"] as? String == "2026-10-17T12:00:00Z")
        fails { _ = try UsageReader.claudePanel("Current session\n12% used\nResets 1pm", now: now) }
        fails { _ = try UsageReader.reset("Resets 29pm (UTC)", now: now, session: true) }
        let rewritten = try UsageReader.terminal("99% used\r\u{1b}[2K12% used")
        precondition(rewritten == "12% used")
        let cleared = try UsageReader.terminal("old\nold\u{1b}[2Jfresh"); precondition(cleared == "fresh")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func script(_ body: String) throws -> String {
            let url = directory.appendingPathComponent(UUID().uuidString)
            try ("#!/bin/sh\n"+body).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url.path
        }
        let server = try script("read line\nprintf '%s\\n' '{\"id\":0,\"result\":{}}'\nread line\nread line\nprintf '%s\\n' '{\"id\":1,\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":12,\"windowDurationMins\":300,\"resetsAt\":1792650147}}}}'\nsleep 5\n")
        let fetched = try UsageReader.codex(directory: directory, binary: server, timeout: 3)
        precondition((fetched["windows"] as! [[String: Any]])[0]["window"] as? String == "5-hour")
        let sleeper = try script("sleep 20\n")
        let start = Date()
        fails { _ = try UsageReader.codex(directory: directory, binary: sleeper, timeout: 0.2) }
        precondition(Date().timeIntervalSince(start) < 2)
        // A real PTY protocol using synthetic panel output, never the real provider.
        let date = Date(); let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "h:mma"
        let reset = formatter.string(from: date.addingTimeInterval(3600))
        // Moving to Applications is offered only for hidden copies and Downloads or Desktop.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        precondition(Mover.shouldOffer(URL(fileURLWithPath: "/private/var/folders/x/T/AppTranslocation/ABC/d/Live AI Usage Widget.app")))
        precondition(Mover.shouldOffer(URL(fileURLWithPath: home + "/Downloads/Live AI Usage Widget.app")))
        precondition(!Mover.shouldOffer(URL(fileURLWithPath: "/Applications/Live AI Usage Widget.app")))
        // Updates: version order and the GitHub release reply.
        precondition(Updater.isNewer("1.1.1", than: "1.1.0") && Updater.isNewer("v1.10.0", than: "1.9.9") && Updater.isNewer("2.0", than: "1.9.9"))
        precondition(!Updater.isNewer("1.1.0", than: "1.1.0") && !Updater.isNewer("1.0.9", than: "1.1.0"))
        let reply = Data(#"{"tag_name":"v1.1.1","draft":false,"prerelease":false,"assets":[{"name":"live-ai-usage-widget-1.1.1-source.zip","browser_download_url":"https://github.com/o/r/releases/download/v1.1.1/s.zip"},{"name":"Live-AI-Usage-Widget-1.1.1-macOS-arm64.zip","browser_download_url":"https://github.com/o/r/releases/download/v1.1.1/Live-AI-Usage-Widget-1.1.1-macOS-arm64.zip"},{"name":"Live-AI-Usage-Widget-1.1.1-macOS-arm64.zip.sha256","browser_download_url":"https://github.com/o/r/releases/download/v1.1.1/Live-AI-Usage-Widget-1.1.1-macOS-arm64.zip.sha256"}]}"#.utf8)
        let found = Updater.release(from: reply)
        precondition(found?.version == "1.1.1" && found?.app.lastPathComponent == "Live-AI-Usage-Widget-1.1.1-macOS-arm64.zip" && found?.checksum.pathExtension == "sha256")
        precondition(Updater.release(from: Data(#"{"tag_name":"v9","prerelease":true,"assets":[]}"#.utf8)) == nil)
        // Claude Code's sign-in offers "Paste code here if prompted" and must keep running until the browser finishes.
        let login = try script("printf 'Opening browser to sign in: https://claude.ai/oauth/authorize?x=1\\nPaste code here if prompted > '\nsleep 2\nprintf '\\nLogin successful.\\n'\n")
        var opened: URL?
        let started = Date()
        try UsageReader.signIn("claude", directory: directory, binary: login, timeout: 10) { opened = $0 }
        precondition(opened?.host == "claude.ai" && Date().timeIntervalSince(started) >= 1.5, "Sign-in must wait for the tool to finish")
        let fakeClaude = try script("printf '$ '\nread line\nprintf '\\nCurrent session\\n12%% used\\nResets \(reset) (UTC)\\n'\nsleep 10\n")
        let receipt = try UsageReader.claude(directory: directory, binary: fakeClaude, timeout: 6)
        precondition((receipt["windows"] as! [[String: Any]])[0]["used_percent"] as? Double == 12)
        let autoModeClaude = try script("stty -icanon -echo\nprintf 'Permission Required: Make auto mode your default permission mode?\\nSelect with numbers [1-2]. Then Enter to submit or Escape to cancel:'\nkey=$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')\n[ \"$key\" = 27 ] || exit 1\nprintf '$ '\nread line\nprintf '\\nCurrent session\\n12%% used\\nResets \(reset) (UTC)\\n'\nsleep 10\n")
        let afterCancel = try UsageReader.claude(directory: directory, binary: autoModeClaude, timeout: 6)
        precondition((afterCancel["windows"] as! [[String: Any]])[0]["used_percent"] as? Double == 12)
        let oldClaude = try script("printf \"error: unknown option '--safe-mode'\\n\"\nexit 1\n")
        do {
            _ = try UsageReader.claude(directory: directory, binary: oldClaude, timeout: 3)
            fatalError("Old Claude should be rejected")
        } catch let error as ReaderFailure { precondition(error.reason == "cli_update_required") }
        let setupClaude = try script("printf 'Permission Required: Accessing workspace\\nEnter y/n:\\n'\nsleep 2\n")
        do {
            _ = try UsageReader.claude(directory: directory, binary: setupClaude, timeout: 3)
            fatalError("Setup prompt must be surfaced")
        } catch let error as ReaderFailure { precondition(error.reason == "interactive_setup_required") }
        var calls = 0
        let first = Collector.collect(previous: [:], providers: ["codex"], now: now) { _ in calls += 1; return result }
        _ = Collector.collect(previous: first, providers: ["codex"], now: now.addingTimeInterval(60)) { _ in calls += 1; return result }
        precondition(calls == 1)
        let failed = Collector.collect(previous: first, providers: ["codex"], now: now.addingTimeInterval(300)) { _ in throw ReaderFailure("raw secret") }
        let state = failed["codex"] as! [String: Any]
        precondition(state["observed_at"] as? String == result["observed_at"] as? String)
        precondition(state["failure_reason"] as? String == "unavailable")
        let recovered = Collector.collect(previous: failed, providers: ["codex"], now: now.addingTimeInterval(1200)) { _ in result }
        precondition((recovered["codex"] as! [String: Any])["refresh_status"] as? String == "ok")
        precondition(Collector.collect(previous: first, providers: [], now: now) { _ in result }.isEmpty)
        // Custom check interval: one minute re-reads after a minute; an hour waits; shortening applies at once.
        var custom = 0
        let minute = Collector.collect(previous: [:], providers: ["codex"], now: now, interval: 60) { _ in custom += 1; return result }
        _ = Collector.collect(previous: minute, providers: ["codex"], now: now.addingTimeInterval(61), interval: 60) { _ in custom += 1; return result }
        let hourly = Collector.collect(previous: [:], providers: ["codex"], now: now, interval: 3600) { _ in custom += 1; return result }
        _ = Collector.collect(previous: hourly, providers: ["codex"], now: now.addingTimeInterval(1800), interval: 3600) { _ in custom += 1; return result }
        _ = Collector.collect(previous: hourly, providers: ["codex"], now: now.addingTimeInterval(400), interval: 300) { _ in custom += 1; return result }
        precondition(custom == 4)
        // Check now re-reads a fresh success but still respects failure backoff.
        _ = Collector.collect(previous: hourly, providers: ["codex"], now: now.addingTimeInterval(10), interval: 3600, force: true) { _ in custom += 1; return result }
        _ = Collector.collect(previous: failed, providers: ["codex"], now: now.addingTimeInterval(310), force: true) { _ in custom += 1; return result }
        precondition(custom == 5)
        let empty = try Collector.run(root: directory, generation: "new", providers: [])
        let decoded = try JSONSerialization.jsonObject(with: empty) as! [String: Any]; precondition(decoded["usage"] as? [String: String] == [:])
        print("Native reader checks passed: exact buckets, invalid values, optional models, timezone, cursor redraw, stdio, PTY, timeout, backoff, sanitized failure, recovery, disabled providers")
    }
}
