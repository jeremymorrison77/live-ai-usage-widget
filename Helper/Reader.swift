import Foundation
import Darwin

struct ReaderFailure: Error { let reason: String; init(_ reason: String) { self.reason = reason } }

/// A bounded, private child process group. Never selects existing processes by name.
final class ChildProcess {
    private static let registryLock = NSLock()
    private static var active: [pid_t: ChildProcess] = [:]
    private let lifecycleLock = NSLock()
    static func stopAll() {
        registryLock.lock(); let children = Array(active.values); registryLock.unlock()
        for child in children { child.stop() }
    }
    private(set) var pid: pid_t = 0
    private var input: Int32 = -1
    private var output: Int32 = -1
    private var closed = false
    init(binary: String, arguments: [String], directory: String, terminal: Bool = false) throws {
        var childIn: Int32 = -1, childOut: Int32 = -1
        if terminal {
            var master: Int32 = -1, slave: Int32 = -1
            var size = winsize(ws_row: 200, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
            guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw ReaderFailure("unavailable") }
            input = master; output = master; childIn = slave; childOut = slave
        } else {
            var incoming: [Int32] = [-1, -1], outgoing: [Int32] = [-1, -1]
            guard pipe(&incoming) == 0 else { throw ReaderFailure("unavailable") }
            guard pipe(&outgoing) == 0 else { close(incoming[0]); close(incoming[1]); throw ReaderFailure("unavailable") }
            input = incoming[1]; output = outgoing[0]; childIn = incoming[0]; childOut = outgoing[1]
        }
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes)
            close(childIn); if childOut != childIn { close(childOut) }
        }
        posix_spawn_file_actions_adddup2(&actions, childIn, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, childOut, STDOUT_FILENO)
        if terminal { posix_spawn_file_actions_adddup2(&actions, childOut, STDERR_FILENO) }
        else { posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) }
        for fd in Set([input, output, childIn, childOut]) where fd > STDERR_FILENO { posix_spawn_file_actions_addclose(&actions, fd) }
        posix_spawn_file_actions_addchdir_np(&actions, directory)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        var environment = ProcessInfo.processInfo.environment
        for key in ["CLAUDECODE", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY"] { environment.removeValue(forKey: key) }
        environment["TERM"] = "xterm-256color"
        var argv = ([binary] + arguments).map { strdup($0) } + [nil]
        var env = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { argv.compactMap { $0 }.forEach { free($0) }; env.compactMap { $0 }.forEach { free($0) } }
        let error = posix_spawn(&pid, binary, &actions, &attributes, &argv, &env)
        guard error == 0 else { close(input); if input != output { close(output) }; closed = true; throw ReaderFailure("cli_unavailable") }
        _ = fcntl(output, F_SETFL, O_NONBLOCK)
        Self.registryLock.lock(); Self.active[pid] = self; Self.registryLock.unlock()
    }
    func send(_ data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { bytes in
            while offset < data.count {
                let count = write(input, bytes.baseAddress!.advanced(by: offset), data.count - offset)
                guard count > 0 else { throw ReaderFailure("unavailable") }
                offset += count
            }
        }
    }
    func sendJSON(_ value: [String: Any]) throws { try send(JSONSerialization.data(withJSONObject: value) + Data([10])) }
    /// nil means no bytes yet; empty data means EOF.
    func readChunk() throws -> Data? {
        var descriptor = pollfd(fd: output, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 100)
        guard ready >= 0 || errno == EINTR else { throw ReaderFailure("unavailable") }
        guard ready > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = read(output, &buffer, buffer.count)
        if count < 0 && [EAGAIN, EINTR].contains(errno) { return nil }
        if count < 0 && errno == EIO { return Data() } // PTY closed
        guard count >= 0 else { throw ReaderFailure("unavailable") }
        return Data(buffer.prefix(count))
    }
    func stop() {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard !closed else { return }
        closed = true
        Self.registryLock.lock(); Self.active.removeValue(forKey: pid); Self.registryLock.unlock()
        // The leader remains unreaped until cleanup, keeping this process-group ID reserved.
        kill(-pid, SIGTERM); usleep(50000); kill(-pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        close(input); if input != output { close(output) }
    }
    deinit { stop() }
}

enum UsageReader {
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    static func replace(_ pattern: String, _ text: String, with value: String = "") -> String {
        text.replacingOccurrences(of: pattern, with: value, options: .regularExpression)
    }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func find(_ provider: String, askShell: Bool = true) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let name = provider == "claude" ? "claude" : "codex"
        // Official installer first, then Homebrew and the usual npm, Bun and Volta global folders.
        var paths = [home + "/.local/bin/" + name, "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name,
                     home + "/.claude/local/" + name, home + "/.npm-global/bin/" + name, home + "/.bun/bin/" + name, home + "/.volta/bin/" + name]
        let nvm = home + "/.nvm/versions/node"
        paths += ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).sorted().reversed().map { nvm + "/" + $0 + "/bin/" + name }
        if provider == "codex" {
            paths = ["/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"] + paths
        }
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/" + name }
        if let binary = paths.first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }) { return binary }
        // Anywhere else (fnm, asdf, mise, pnpm, a custom npm folder…): ask the person's own Terminal setup.
        if askShell, let binary = shellLookup(name) { return binary }
        if !askShell, let binary = rememberedLookup(name) { return binary }
        throw ReaderFailure("cli_unavailable")
    }
    private static let lookupLock = NSLock()
    nonisolated(unsafe) private static var lookups: [String: (path: String?, at: Date)] = [:]
    /// The last Terminal answer, without asking again (for screens, which must never wait).
    static func rememberedLookup(_ name: String) -> String? {
        lookupLock.lock(); defer { lookupLock.unlock() }
        return lookups[name]?.path
    }
    /// Forgets earlier Terminal answers, for example right before deciding whether to install.
    static func forgetLookups() { lookupLock.lock(); lookups = [:]; lookupLock.unlock() }
    /// Runs the person's login shell the way Terminal does and asks where the tool is. Remembered for a minute,
    /// since screens ask often; gives up after five seconds.
    static func shellLookup(_ name: String) -> String? {
        lookupLock.lock()
        if let known = lookups[name], Date().timeIntervalSince(known.at) < 60 { lookupLock.unlock(); return known.path }
        lookupLock.unlock()
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "command -v " + name]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var found: String?
        if (try? process.run()) != nil {
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { process.terminate() }
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            found = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .last { $0.hasPrefix("/") && $0.hasSuffix("/" + name) && FileManager.default.isExecutableFile(atPath: $0) }
        }
        lookupLock.lock(); lookups[name] = (found, Date()); lookupLock.unlock()
        return found
    }
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    static func codexLimits(_ value: [String: Any], at now: Date) throws -> [String: Any] {
        let limits: [String: Any]?
        if let buckets = value["rateLimitsByLimitId"] as? [String: Any], !buckets.isEmpty { limits = buckets["codex"] as? [String: Any] }
        else { limits = value["rateLimits"] as? [String: Any] }
        guard let limits, limits["limitId"] == nil || limits["limitId"] is NSNull || limits["limitId"] as? String == "codex" else { throw ReaderFailure("usage_panel_incomplete") }
        var windows: [[String: Any]] = []
        for key in ["primary", "secondary"] {
            guard let item = limits[key], !(item is NSNull) else { continue }
            guard let item = item as? [String: Any], let used = number(item["usedPercent"]), (0...100).contains(used),
                  let minutes = number(item["windowDurationMins"]), minutes > 0, minutes <= 525600,
                  let reset = number(item["resetsAt"]), reset > 0, reset < 253402300800 else { throw ReaderFailure("invalid_usage") }
            let name = minutes == 300 ? "5-hour" : minutes == 10080 ? "weekly" : "\(Int(minutes))-minute"
            windows.append(["window": name, "used_percent": used, "resets_at": iso(Date(timeIntervalSince1970: reset))])
        }
        guard !windows.isEmpty else { throw ReaderFailure("usage_panel_incomplete") }
        return ["status": "ok", "observed_at": iso(now), "windows": windows]
    }
    static func codex(directory: URL, binary: String? = nil, timeout: Double = 15) throws -> [String: Any] {
        let child = try ChildProcess(binary: binary ?? find("codex"), arguments: ["app-server", "--listen", "stdio://"], directory: directory.path)
        defer { child.stop() }
        try child.sendJSON(["id": 0, "method": "initialize", "params": ["clientInfo": ["name": "live_ai_usage_widget", "title": "Live AI Usage Widget", "version": "1.3.1"]]])
        let start = ProcessInfo.processInfo.systemUptime
        var pending = Data(), total = 0, initialized = false
        while ProcessInfo.processInfo.systemUptime - start < timeout {
            guard let data = try child.readChunk() else { continue }
            guard !data.isEmpty else { throw ReaderFailure("unavailable") }
            total += data.count
            guard total <= 262144 else { throw ReaderFailure("output_too_large") }
            pending.append(data)
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline); pending.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw ReaderFailure("usage_panel_incomplete") }
                guard let id = message["id"] as? Int else { continue }
                if let error = message["error"] as? [String: Any] { throw ReaderFailure(errorReason(error["message"] as? String ?? "")) }
                if id == 0 && !initialized {
                    guard message["result"] is [String: Any] else { throw ReaderFailure("usage_panel_incomplete") }
                    initialized = true
                    try child.sendJSON(["method": "initialized", "params": [:]])
                    try child.sendJSON(["id": 1, "method": "account/rateLimits/read"])
                } else if id == 1 && initialized, let result = message["result"] as? [String: Any] { return try codexLimits(result, at: Date()) }
            }
        }
        throw ReaderFailure("usage_read_timed_out")
    }
    static func errorReason(_ message: String) -> String {
        let text = message.lowercased()
        if ["429", "rate limit", "too many requests"].contains(where: text.contains) { return "rate_limited" }
        if ["401", "unauthorized", "not logged", "sign in", "authentication"].contains(where: text.contains) { return "sign_in_required" }
        return "unavailable"
    }
    /// Cursor-aware terminal rendering: erased cached text cannot survive as the first percentage.
    static func terminal(_ raw: String) throws -> String {
        let text = replace("\\x1b\\][^\\x07\\x1b]*(?:\\x07|\\x1b\\\\)", raw)
        let tokens = matches("\\x1b\\[[0-?]*[ -/]*[@-~]|\\x1b[()][A-Z0-9]|\\x1b.|[^\\x1b]", text)
        var rows: [[Character]] = [[]], x = 0, y = 0
        for token in tokens.map({ $0[0] }) {
            if token.hasPrefix("\u{1b}[") {
                if let control = matches("^\\x1b\\[([0-9;]*)([ABCDEFGHJKf])$", token).first {
                    let numbers = control[1].split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                    let n = numbers.first ?? 0, count = n == 0 ? 1 : n
                    switch control[2] {
                    case "A": y = max(0, y-count)
                    case "B": y += count
                    case "C": x += count
                    case "D": x = max(0, x-count)
                    case "E": y += count; x = 0
                    case "F": y = max(0, y-count); x = 0
                    case "G": x = max(0, count-1)
                    case "H", "f": y = max(0, count-1); x = max(0, (numbers.count > 1 ? max(1, numbers[1]) : 1)-1)
                    case "J": if n == 2 { rows = [[]]; x = 0; y = 0 }
                    case "K":
                        if y < rows.count {
                            if n == 2 { rows[y] = [] }
                            else if n == 0 { rows[y] = Array(rows[y].prefix(x)) }
                            else if n == 1 { for index in 0..<min(x+1, rows[y].count) { rows[y][index] = " " } }
                        }
                    default: break
                    }
                }
                continue
            }
            if token.hasPrefix("\u{1b}") { continue }
            if token == "\r" { x = 0; continue }
            if token == "\n" { y += 1; x = 0; continue }
            if token == "\u{8}" { x = max(0, x-1); continue }
            guard let character = token.first, let scalar = token.unicodeScalars.first, scalar.value >= 32 else { continue }
            guard x <= 1000 && y <= 1000 else { throw ReaderFailure("terminal_bounds") }
            while rows.count <= y { rows.append([]) }
            while rows[y].count <= x { rows[y].append(" ") }
            rows[y][x] = character; x += 1
        }
        return rows.map { String($0) }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func reset(_ block: String, now: Date, session: Bool) throws -> String {
        guard let match = matches("(?i)Resets?\\s+([^\\n]+)", block).first,
              let zoneName = matches("\\(([^()]+)\\)", match[1]).first?[1], let zone = TimeZone(identifier: zoneName) else { throw ReaderFailure("reset_format_changed") }
        let value = replace("\\s*\\([^()]+\\)", match[1]).trimmingCharacters(in: .whitespaces).lowercased()
        guard let clock = matches("(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)", value).first,
              let h = Int(clock[1]), (1...12).contains(h), let timeRange = value.range(of: clock[0]) else { throw ReaderFailure("reset_format_changed") }
        let minute = Int(clock[2]) ?? 0
        guard minute < 60 else { throw ReaderFailure("reset_format_changed") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = h % 12 + (clock[3] == "pm" ? 12 : 0); components.minute = minute; components.second = 0
        let prefix = replace("\\s+at$", String(value[..<timeRange.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ,·")))
        if !prefix.isEmpty && !["today", "tomorrow"].contains(prefix) {
            let weekdays = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
            if let weekday = weekdays[String(prefix.prefix(3))] {
                let days = (weekday - calendar.component(.weekday, from: now) + 7) % 7
                guard let day = calendar.date(byAdding: .day, value: days, to: now) else { throw ReaderFailure("reset_format_changed") }
                let dateParts = calendar.dateComponents([.year, .month, .day], from: day)
                components.year = dateParts.year; components.month = dateParts.month; components.day = dateParts.day
            } else {
                var parsed: Date?
                for format in ["MMM d, yyyy", "MMMM d, yyyy", "MMM d yyyy", "MMMM d yyyy", "M/d yyyy"] {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone; formatter.dateFormat = format; formatter.isLenient = false
                    let text = prefix.contains(",") ? prefix : prefix + " \(components.year!)"
                    if let result = formatter.date(from: text) { parsed = result; break }
                }
                guard let parsed else { throw ReaderFailure("reset_format_changed") }
                let parts = calendar.dateComponents([.year, .month, .day], from: parsed)
                components.year = parts.year; components.month = parts.month; components.day = parts.day
            }
        }
        guard var result = calendar.date(from: components) else { throw ReaderFailure("reset_format_changed") }
        if prefix == "tomorrow" { result = calendar.date(byAdding: .day, value: 1, to: result)! }
        else if result <= now {
            if prefix.isEmpty { result = calendar.date(byAdding: .day, value: 1, to: result)! }
            else if matches("^(sun|mon|tue|wed|thu|fri|sat)", prefix).count > 0 { result = calendar.date(byAdding: .day, value: 7, to: result)! }
            else if prefix != "today", !prefix.contains(",") { result = calendar.date(byAdding: .year, value: 1, to: result)! }
        }
        guard result > now, result.timeIntervalSince(now) <= (session ? 21600 : 691200) else { throw ReaderFailure("reset_out_of_range") }
        return iso(result)
    }
    static func claudePanel(_ raw: String, now: Date) throws -> [String: Any] {
        let text = try terminal(raw)
        let regex = try NSRegularExpression(pattern: "(?i)Current\\s+(session|week(?:\\s*\\([^\\n)]*\\))?)[^\\n]*")
        let headings = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let ns = text as NSString
        var windows: [[String: Any]] = []
        for (index, heading) in headings.enumerated() {
            let title = ns.substring(with: heading.range)
            let start = heading.range.location + heading.range.length
            let end = index+1 < headings.count ? headings[index+1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: start, length: end-start))
            guard let percent = matches("(?i)(?<![\\d.])(\\d{1,3}(?:\\.\\d+)?)\\s*%\\s*(used|left|remaining)", block).first,
                  let number = Double(percent[1]), (0...100).contains(number) else { throw ReaderFailure("usage_panel_incomplete") }
            let session = title.lowercased().contains("session")
            let model = matches("\\(([^)]+)\\)", title).first?[1]
            let name = session ? "5-hour" : model == nil || model?.lowercased() == "all models" ? "weekly all" : "weekly " + model!
            windows.append(["window": name, "used_percent": percent[2].lowercased() == "used" ? number : 100-number,
                            "resets_at": try reset(block, now: now, session: session)])
        }
        guard !windows.isEmpty, windows.count <= 8 else { throw ReaderFailure("usage_panel_incomplete") }
        return ["status": "ok", "observed_at": iso(now), "windows": windows]
    }
    static let claudeArguments = ["--safe-mode", "--no-chrome", "--setting-sources", "", "--tools", "", "--strict-mcp-config", "--permission-mode", "dontAsk", "--settings", "{\"disableAllHooks\":true,\"remoteControlAtStartup\":false}", "--ax-screen-reader"]
    /// Only one Claude Code session at a time: on a first run, two at once (the connect step and a background
    /// check) block each other on its one-time setup and both stall.
    static let claudeTurn = NSLock()
    static func claude(directory: URL, binary: String? = nil, timeout: Double = 35) throws -> [String: Any] {
        guard claudeTurn.lock(before: Date().addingTimeInterval(90)) else { throw ReaderFailure("usage_read_timed_out") }
        defer { claudeTurn.unlock() }
        let child = try ChildProcess(binary: binary ?? find("claude"), arguments: claudeArguments, directory: directory.path, terminal: true)
        defer { child.stop() }
        let start = ProcessInfo.processInfo.systemUptime
        var lastOutput = start, data = Data(), sent = false, total = 0
        var dismissedAutoMode = false
        var firstRun: Set<String> = []
        while ProcessInfo.processInfo.systemUptime - start < timeout {
            if let chunk = try child.readChunk() {
                if chunk.isEmpty { throw ReaderFailure("unavailable") }
                total += chunk.count
                guard total <= 262144 else { throw ReaderFailure("output_too_large") }
                lastOutput = ProcessInfo.processInfo.systemUptime
                data.append(chunk)
                if String(decoding: chunk, as: UTF8.self).contains("\u{1b}[6n") { try child.send(Data("\u{1b}[1;1R".utf8)) }
            }
            trace?("usage: " + String(decoding: data, as: UTF8.self))
            let text = try terminal(String(decoding: data, as: UTF8.self))
            if !matches("(?i)unknown option|unrecognized option", text).isEmpty { throw ReaderFailure("cli_update_required") }
            if !matches("(?i)Not logged in|Login expired|run /login", text).isEmpty { throw ReaderFailure("sign_in_required") }
            if !sent, try answerFirstRun(text, child: child, answered: &firstRun) { data = Data(); continue }
            // Cancel only this optional opt-in. Never approve trust or permission prompts.
            if !sent && !dismissedAutoMode && text.contains("Permission Required: Make auto mode your default permission mode?") && text.contains("Escape to cancel:") {
                try child.send(Data([27])); data = Data(); dismissedAutoMode = true
                continue
            }
            if !matches("(?i)Enter y/n:|Select login method|Permission Required", text).isEmpty { throw ReaderFailure("interactive_setup_required") }
            if !sent && ProcessInfo.processInfo.systemUptime-start >= 2 && !matches("\\$\\s*$", text).isEmpty {
                try child.send(Data("/usage\r".utf8)); data = Data(); sent = true
            } else if sent {
                if !matches("(?i)429|rate.limit", text).isEmpty { throw ReaderFailure("rate_limited") }
                if !text.contains("Refreshing…") && ProcessInfo.processInfo.systemUptime-lastOutput >= 0.75,
                   let result = try? claudePanel(text, now: Date()) { return result }
            }
        }
        reportStall("Usage check", (try? terminal(String(decoding: data, as: UTF8.self))) ?? "")
        throw ReaderFailure("usage_read_timed_out")
    }
}

/// Setup helpers that run the official tools in the background, so no Terminal window is needed.
extension UsageReader {
    private static var uptime: Double { ProcessInfo.processInfo.systemUptime }
    private static func plain(_ data: Data) -> String {
        replace("\u{1b}\\[[0-9;?>=]*[a-zA-Z]", String(decoding: data, as: UTF8.self))
    }

    /// Testing only: receives every piece of screen output from the folder-trust step.
    nonisolated(unsafe) static var trace: ((String) -> Void)?
    /// Set by the app: told what Claude Code last showed when it stalls, for the diagnostic report.
    nonisolated(unsafe) static var onStall: ((String) -> Void)?
    static func reportStall(_ where_: String, _ text: String) {
        let screen = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(4).joined(separator: " / ")
        onStall?(where_ + " stalled; Claude Code showed: " + String(screen.suffix(240)))
    }
    /// Claude Code's one-time welcome screens on a fresh install (never opened in Terminal). In the mode the app uses,
    /// lists are answered by typing an option's number, then Enter. Keeps the suggested ("current") text style,
    /// continues past the safety notes, and declines the optional Terminal changes. Nothing else is answered.
    static func answerFirstRun(_ text: String, child: ChildProcess, answered: inout Set<String>) throws -> Bool {
        // Keys typed the instant a screen appears are dropped, so each answer waits a moment first.
        func pick(_ pattern: String, fallback: String) throws {
            Thread.sleep(forTimeInterval: 1)
            let number = matches(pattern, text).first?[1] ?? fallback
            try child.send(Data(number.utf8))
            Thread.sleep(forTimeInterval: 0.4)
            try child.send(Data("\r".utf8))
        }
        if !answered.contains("style"), text.contains("Choose the text style"), text.contains("Enter to submit") {
            try pick("(\\d+)\\.\\s*current:", fallback: "1"); answered.insert("style"); return true
        }
        if !answered.contains("notes"), text.contains("Security notes"), text.contains("Press Enter to continue") {
            Thread.sleep(forTimeInterval: 1); try child.send(Data("\r".utf8)); answered.insert("notes"); return true
        }
        if !answered.contains("terminal"), text.contains("Use Claude Code's terminal setup?") {
            if matches("(\\d+)\\.\\s*No", text).isEmpty { Thread.sleep(forTimeInterval: 1); try child.send(Data([27])) } else { try pick("(\\d+)\\.\\s*No", fallback: "2") }
            answered.insert("terminal"); return true
        }
        return false
    }

    /// Answers Claude Code's one-time workspace question, and only for the app's own empty probe folder.
    static func trustProbe(directory: URL, binary: String? = nil, timeout: Double = 45) throws {
        guard claudeTurn.lock(before: Date().addingTimeInterval(90)) else { throw ReaderFailure("usage_read_timed_out") }
        defer { claudeTurn.unlock() }
        trace?("trust: starting")
        let child = try ChildProcess(binary: binary ?? find("claude"), arguments: claudeArguments, directory: directory.path, terminal: true)
        defer { child.stop() }
        let start = uptime
        var data = Data(), answers = 0
        var firstRun: Set<String> = []
        while uptime - start < timeout {
            if let chunk = try child.readChunk() {
                if chunk.isEmpty { throw ReaderFailure("unavailable") }
                data.append(chunk)
                if String(decoding: chunk, as: UTF8.self).contains("\u{1b}[6n") { try child.send(Data("\u{1b}[1;1R".utf8)) }
            }
            trace?(plain(data))
            let text = plain(data)
            if !matches("(?i)unknown option|unrecognized option", text).isEmpty { throw ReaderFailure("cli_update_required") }
            if !matches("(?i)Not logged in|Login expired|run /login", text).isEmpty { throw ReaderFailure("sign_in_required") }
            if try answerFirstRun(text, child: child, answered: &firstRun) { data = Data(); continue }
            if answers < 3 && text.contains("Accessing workspace:") && text.contains("Enter y/n:") {
                let flat = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
                guard flat.contains(directory.path) || flat.contains(directory.resolvingSymlinksInPath().path) else { throw ReaderFailure("interactive_setup_required") }
                // Typed like a person: wait for the question to settle, the answer, a short pause, then Enter.
                // If the same question comes back (the keys were dropped), answer it again, up to three times.
                Thread.sleep(forTimeInterval: 1)
                try child.send(Data("y".utf8)); Thread.sleep(forTimeInterval: 0.4); try child.send(Data("\r".utf8))
                data = Data(); answers += 1
                continue
            }
            // Ready prompt means the folder is trusted (now or already).
            if uptime - start >= 2 && !matches("\\$\\s*$", text).isEmpty { return }
        }
        reportStall("Folder trust", plain(data))
        throw ReaderFailure("usage_read_timed_out")
    }

    /// Runs the official sign-in without Terminal. The tool opens the browser itself; any sign-in link it prints is passed on.
    static func signIn(_ provider: String, directory: URL, binary: String? = nil, timeout: Double = 600, onLink: @escaping (URL) -> Void) throws {
        let arguments = provider == "claude" ? ["auth", "login", "--claudeai"] : ["login"]
        let child = try ChildProcess(binary: binary ?? find(provider), arguments: arguments, directory: directory.path, terminal: true)
        defer { child.stop() }
        let start = uptime
        var data = Data(), linked = false
        while uptime - start < timeout {
            guard let chunk = try child.readChunk() else { continue }
            if chunk.isEmpty { return } // The tool finished; the connection check confirms the result.
            data.append(chunk)
            guard data.count <= 262144 else { throw ReaderFailure("output_too_large") }
            if String(decoding: chunk, as: UTF8.self).contains("\u{1b}[6n") { try child.send(Data("\u{1b}[1;1R".utf8)) }
            let text = plain(data)
            if !linked, let match = matches("(https://[^\\s\"'<>]+)", text).first, let url = URL(string: match[1]) { linked = true; onLink(url) }
            // Claude Code also offers "Paste code here if prompted"; the tool must keep running so the browser's
            // Authorize can reach it, so that line is not a failure.
        }
        throw ReaderFailure("usage_read_timed_out")
    }

    /// Whether the official tool reports a signed-in account. nil when it can't tell.
    static func signedIn(_ provider: String, directory: URL) -> Bool? {
        guard let child = try? ChildProcess(binary: find(provider), arguments: provider == "claude" ? ["auth", "status"] : ["login", "status"], directory: directory.path, terminal: true) else { return nil }
        defer { child.stop() }
        let start = uptime
        var data = Data()
        while uptime - start < 10 {
            guard let chunk = try? child.readChunk() else { continue }
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        // Terminal output can carry color codes; compare the plain text.
        let text = plain(data)
        if provider == "claude" {
            if !matches("\"loggedIn\"\\s*:\\s*true", text).isEmpty { return true }
            if !matches("\"loggedIn\"\\s*:\\s*false", text).isEmpty { return false }
            return nil
        }
        return text.localizedCaseInsensitiveContains("not logged in") ? false : text.localizedCaseInsensitiveContains("logged in") ? true : nil
    }
}
