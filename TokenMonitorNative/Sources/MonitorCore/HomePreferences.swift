import Foundation

public enum HomeSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case usage, quota, devices, models, activity, trends
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .usage: L10n.text("用量")
        case .quota: L10n.text("额度")
        case .devices: L10n.text("设备")
        case .models: L10n.text("模型")
        case .activity: L10n.text("活动")
        case .trends: L10n.text("每日趋势")
        }
    }
    public static func normalizedOrder(_ names: [String]) -> [HomeSection] {
        var seen = Set<HomeSection>()
        return (names.compactMap(HomeSection.init(rawValue:)) + allCases).filter { seen.insert($0).inserted }
    }
}
public enum ThemeColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, custom, blue, purple, pink, red, orange, green, teal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .custom: L10n.text("自定义")
        case .blue: L10n.text("蓝色")
        case .purple: L10n.text("紫色")
        case .pink: L10n.text("粉色")
        case .red: L10n.text("红色")
        case .orange: L10n.text("橙色")
        case .green: L10n.text("绿色")
        case .teal: L10n.text("青色")
        }
    }
}

/// Device-independent sRGB components, persisted without AppKit or SwiftUI types.
public struct RGBColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red.isFinite ? min(1, max(0, red)) : 0
        self.green = green.isFinite ? min(1, max(0, green)) : 0
        self.blue = blue.isFinite ? min(1, max(0, blue)) : 0
    }
    enum CodingKeys: String, CodingKey { case red, green, blue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = try c.decode(Double.self, forKey: .red)
        let g = try c.decode(Double.self, forKey: .green)
        let b = try c.decode(Double.self, forKey: .blue)
        guard [r, g, b].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid sRGB components"))
        }
        self.init(red: r, green: g, blue: b)
    }
}
