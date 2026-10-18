import Foundation
import SwiftUI

struct WidgetSettings: Codable {
    var enabled: [String] = []
    var generation = "initial"
    var usDates = false
    var usageColors = true
    var highThreshold = 30.0
    var lowThreshold = 10.0
    var highColor = "#39A66B"
    var middleColor = "#E99A38"
    var lowColor = "#D65B64"
    var style = "clean"
    var hiddenSmallMetrics: [String] = []
    var refreshMinutes = 5
    var autoDetected = false
    init() {}
    enum CodingKeys: String, CodingKey { case enabled, generation, usDates, usageColors, highThreshold, lowThreshold, highColor, middleColor, lowColor, style, hiddenSmallMetrics, refreshMinutes, autoDetected }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try c.decodeIfPresent([String].self, forKey: .enabled) ?? []).filter { ["claude", "codex"].contains($0) }
        generation = try c.decodeIfPresent(String.self, forKey: .generation) ?? "initial"
        usDates = try c.decodeIfPresent(Bool.self, forKey: .usDates) ?? false
        usageColors = try c.decodeIfPresent(Bool.self, forKey: .usageColors) ?? true
        highThreshold = try c.decodeIfPresent(Double.self, forKey: .highThreshold) ?? 30
        lowThreshold = try c.decodeIfPresent(Double.self, forKey: .lowThreshold) ?? 10
        highColor = try c.decodeIfPresent(String.self, forKey: .highColor) ?? "#39A66B"
        middleColor = try c.decodeIfPresent(String.self, forKey: .middleColor) ?? "#E99A38"
        lowColor = try c.decodeIfPresent(String.self, forKey: .lowColor) ?? "#D65B64"
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "clean"
        if !["clean", "solar", "trends"].contains(style) { style = "clean" }
        hiddenSmallMetrics = try c.decodeIfPresent([String].self, forKey: .hiddenSmallMetrics) ?? []
        refreshMinutes = min(1440, max(1, try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 5))
        autoDetected = try c.decodeIfPresent(Bool.self, forKey: .autoDetected) ?? false
        if !highThreshold.isFinite || !lowThreshold.isFinite || lowThreshold < 0 || highThreshold > 100 || lowThreshold >= highThreshold {
            highThreshold = 30; lowThreshold = 10
        }
    }

    static func url() throws -> URL {
        try StatusStore.fileURL().deletingLastPathComponent().appendingPathComponent("settings.json")
    }
    static func load() -> WidgetSettings {
        guard let url = try? url(), let data = try? Data(contentsOf: url), data.count < 8192,
              let value = try? JSONDecoder().decode(WidgetSettings.self, from: data) else { return WidgetSettings() }
        return value
    }
    func save() throws {
        guard highThreshold.isFinite, lowThreshold.isFinite,
              lowThreshold >= 0, highThreshold <= 100, lowThreshold < highThreshold else {
            throw SettingsError.invalidThreshold
        }
        let destination = try Self.url()
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: destination, options: .atomic)
    }
    func color(for left: Double) -> Color {
        guard usageColors else { return .accentColor }
        return Self.color(hex: left <= lowThreshold ? lowColor : left < highThreshold ? middleColor : highColor)
    }
    static func color(hex: String) -> Color {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x39A66B
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    enum SettingsError: Error { case invalidThreshold }
}
