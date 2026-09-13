import Foundation

public enum HomeSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case usage, quota, devices, models, activity, trends
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .usage: "用量"
        case .quota: "额度"
        case .devices: "设备"
        case .models: "模型"
        case .activity: "活动"
        case .trends: "每日趋势"
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
        case .system: "跟随系统"
        case .custom: "自定义"
        case .blue: "蓝色"
        case .purple: "紫色"
        case .pink: "粉色"
        case .red: "红色"
        case .orange: "橙色"
        case .green: "绿色"
        case .teal: "青色"
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
