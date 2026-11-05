import Foundation

@main struct GrokCreditsTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool) { precondition(condition()); count += 1 }
        let now = Date(timeIntervalSince1970: 1793857920)
        func json(_ overrides: [String: Any] = [:]) throws -> Data {
            var values: [String: Any] = ["source": "grokbot-credits", "creditsAvailableUSD": 295.64,
                "usedThisMonthUSD": 304.37, "monthlyLimitUSD": NSNull(), "weeklyUsedPercent": 100,
                "weeklyResetsAt": "2026-11-08T16:23:00Z", "burn24hUSD": NSNull(), "updatedAt": UsageReader.iso(now)]
            values.merge(overrides) { _, new in new }
            return try JSONSerialization.data(withJSONObject: values)
        }
        let valid = try json()
        check(try! UsageReader.grokCreditsReading(valid)["creditsAvailableUSD"] as? Double == 295.64)
        for overrides: [String: Any] in [["source": "wrong"], ["creditsAvailableUSD": -1], ["creditsAvailableUSD": true], ["creditsAvailableUSD": NSNull()], ["weeklyUsedPercent": 101], ["weeklyUsedPercent": false], ["updatedAt": "bad"], ["updatedAt": NSNull()], ["weeklyResetsAt": "bad"], ["burn24hUSD": "bad"], ["usedThisMonthUSD": -1]] {
            check((try? UsageReader.grokCreditsReading(json(overrides))) == nil)
        }
        check((try? UsageReader.grokCreditsReading(Data(repeating: 32, count: 16384))) == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let weekly = directory.appendingPathComponent("grokbot-usage.json"), credits = directory.appendingPathComponent("grokbot-credits.json")
        check((try? UsageReader.grokBot(file: weekly)) == nil)
        func writeWeekly(_ date: Date, used: Double, balance: Double = 500) throws {
            try JSONSerialization.data(withJSONObject: ["source": "grokbot", "updatedAt": UsageReader.iso(date), "weekly": ["usedPercent": used], "creditsUSD": balance]).write(to: weekly)
        }
        try writeWeekly(now.addingTimeInterval(-60), used: 80)
        check(try! UsageReader.grokBot(file: weekly)["credits_usd"] as? Double == 500)
        try Data("bad".utf8).write(to: credits)
        check(try! UsageReader.grokBot(file: weekly)["credits_usd"] as? Double == 500)
        try valid.write(to: credits)
        let reading = try UsageReader.grokBot(file: weekly)
        check(reading["credits_usd"] as? Double == 295.64)
        check((reading["windows"] as! [[String: Any]])[0]["used_percent"] as? Double == 100)
        let inputs = try JSONDecoder().decode([String: UsageInputModel.UsageInput].self, from: JSONSerialization.data(withJSONObject: ["grokbot": reading]))
        let usage = UsageInputModel.agentUsage(inputs)["grokbot"]!
        check(usage.creditsLabel(for: "grokbot") == "$295.64")
        check(usage.grokMenuLines(at: now, showsUsed: true)[0].contains("100% used"))
        check(usage.grokMenuLines(at: now, showsUsed: false)[0].contains("0% left"))
        check(usage.grokMenuLines(at: now, showsUsed: false)[1] == "Grok · Credits · $295.64")
        let balance = usage.grokCredits!
        check(balance.fraction == nil) // Spending must never invent a denominator.
        func decoded(_ overrides: [String: Any]) throws -> GrokCredits {
            let reading = try UsageReader.grokCreditsReading(json(overrides))
            return try JSONDecoder().decode(GrokCredits.self, from: JSONSerialization.data(withJSONObject: reading))
        }
        let purchased = try decoded(["creditsPurchasedUSD": 300, "monthlyLimitUSD": 1000])
        check(purchased.creditsPurchasedUSD == 300)
        check(abs(purchased.fraction! - 295.64 / 300) < 0.000001)
        check(try! decoded(["creditsPurchasedUSD": 300, "usedThisMonthUSD": 0]).fraction == purchased.fraction)
        check(try! decoded(["creditsPurchasedUSD": 300, "usedThisMonthUSD": 9999]).fraction == purchased.fraction)
        check(try! decoded(["monthlyLimitUSD": 600]).fraction == 295.64 / 600)
        check(try! decoded(["creditsPurchasedUSD": 0, "monthlyLimitUSD": 600]).fraction == 295.64 / 600)
        check(try! decoded(["creditsPurchasedUSD": NSNull(), "monthlyLimitUSD": 600]).fraction == 295.64 / 600)
        check(try! decoded(["creditsPurchasedUSD": 0, "monthlyLimitUSD": 0]).fraction == nil)
        check(try! decoded(["creditsPurchasedUSD": NSNull()]).fraction == nil)
        check(try! decoded(["creditsPurchasedUSD": 100]).fraction == 1)
        check(try! decoded(["creditsPurchasedUSD": 300, "creditsAvailableUSD": 0]).fraction == 0)
        check(try! JSONDecoder().decode(GrokCredits.self, from: JSONEncoder().encode(purchased)) == purchased)
        for invalid: Any in [-1, true, "300", [], [:]] {
            check((try? UsageReader.grokCreditsReading(json(["creditsPurchasedUSD": invalid]))) == nil)
        }
        check((try? UsageReader.grokCreditsReading(Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "304.37", with: "1e999").replacingOccurrences(of: "usedThisMonthUSD", with: "creditsPurchasedUSD").utf8))) == nil)
        check(!balance.isStale(at: now.addingTimeInterval(28800)))
        check(balance.isStale(at: now.addingTimeInterval(28801)))
        for (amount, level): (Double, UsageLevel) in [(100, .normal), (99.99, .warning), (25, .warning), (24.99, .critical), (0, .critical)] {
            let value = GrokCredits(creditsAvailableUSD: amount, usedThisMonthUSD: nil, monthlyLimitUSD: nil, burn24hUSD: nil, updatedAt: UsageReader.iso(now))
            check(value.level == level); check(value.fraction == nil)
        }
        let limited = GrokCredits(creditsAvailableUSD: 50, usedThisMonthUSD: 100, monthlyLimitUSD: 200, burn24hUSD: 12, updatedAt: UsageReader.iso(now))
        check(limited.fraction == 0.25)
        var burn = usage; burn.grokCredits = limited; burn.creditsUSD = 50
        check(burn.creditsLabel(for: "grokbot") == "$50.00 · $12.00/day")
        check(try! JSONDecoder().decode(AgentUsage.self, from: JSONEncoder().encode(usage)).grokCredits == balance)
        try writeWeekly(now.addingTimeInterval(60), used: 90)
        let newer = try UsageReader.grokBot(file: weekly)
        check(newer["credits_usd"] as? Double == 500)
        check((newer["windows"] as! [[String: Any]])[0]["used_percent"] as? Double == 90)
        try FileManager.default.removeItem(at: weekly)
        check(try! UsageReader.grokBot(file: weekly)["credits_usd"] as? Double == 295.64)
        let cached = AgentUsage(observedAt: now.addingTimeInterval(60), windows: usage.windows)
        check(StatusStore.merged(["grokbot": cached], ["grokbot": usage])["grokbot"]?.grokCredits == balance)
        var regressed = usage
        regressed.grokCredits = GrokCredits(creditsAvailableUSD: 900, usedThisMonthUSD: 0, monthlyLimitUSD: nil, burn24hUSD: nil, updatedAt: UsageReader.iso(now.addingTimeInterval(-60)))
        check(StatusStore.merged(["grokbot": usage], ["grokbot": regressed])["grokbot"]?.grokCredits == balance)
        var below = usage
        below = AgentUsage(observedAt: now, windows: [UsageWindow(window: "weekly", usedPercent: 99, resetsAt: nil)], creditsUSD: 295.64, grokCredits: balance)
        check(below.creditsLabel(for: "grokbot") == nil)
        check(below.grokMenuLines(at: now, showsUsed: true).count == 1)
        let empty = GrokCredits(creditsAvailableUSD: 0, usedThisMonthUSD: 0, monthlyLimitUSD: nil, burn24hUSD: nil, updatedAt: UsageReader.iso(now))
        check(empty.fraction == nil)
        print("Grok credits: \(count) checks passed")
    }
}
