import Foundation

public struct ChartStyle: Codable, Equatable, Sendable {
    public var preset = "vivid"
    public var customColors = Self.palette("vivid")
    public var other = Self.rgb(0x999999)
    public var remaining = Self.rgb(0x21A675)
    public var used = Self.rgb(0xBEC4CC)
    public var objectColors: [String: RGBColor]? = nil
    public var slots: [String: Int] = [:]
    public init() {}
    public static func rgb(_ hex: Int) -> RGBColor {
        RGBColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    public static func palette(_ name: String) -> [RGBColor] {
        let hex: [Int]
        switch name {
        case "soft": hex = [0x7699D4,0xDDA17A,0xA98AC2,0x70AFAB,0xD887A5,0x91AD70,0xBAA16E,0x8795AF]
        case "contrast": hex = [0x0072B2,0xE69F00,0x009E73,0xCC79A7,0xD55E00,0x56B4E9,0x7B4AB0,0x7A664B]
        default: hex = [0x3377DD,0xEF8A32,0x965AD6,0x18A8AB,0xDB598B,0x4A9A54,0x7969CD,0xAC774E]
        }
        return hex.map(rgb)
    }
    public var colors: [RGBColor] { preset == "custom" && customColors.count == 8 ? customColors : Self.palette(preset) }
    public func resolvedSlots(_ ids: [String]) -> [String: Int] {
        var result = slots.filter { (0..<8).contains($0.value) }
        var usedSlots = Set(ids.compactMap { result[$0] })
        for id in ids.sorted() where !id.hasPrefix("quota:") && !id.hasPrefix("aggregate:other") {
            let hash = id.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
            if result[id] != nil { continue }
            let preferred = Int(hash % 8)
            let slot = (0..<8).map { (preferred + $0) % 8 }.first { !usedSlots.contains($0) } ?? preferred
            result[id] = slot; usedSlots.insert(slot)
        }
        return result
    }
    public func color(id: String, activeIDs: [String]) -> RGBColor {
        if let override = objectColors?[id] { return override }
        if id.hasPrefix("aggregate:other") { return other }
        if id == "quota:remaining" { return remaining }
        if id == "quota:used" { return used }
        return colors[resolvedSlots(activeIDs)[id] ?? 0]
    }
}
