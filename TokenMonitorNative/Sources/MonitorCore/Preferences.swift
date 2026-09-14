import Foundation

public struct Preferences: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var hubAddress = "http://127.0.0.1:17321"
    public var connected = false
    public var tool = "codex"
    public var period = Period.month
    public var pinned = false
    public var automaticallyCheckForUpdates = false
    public var showPanelOnLaunch = true
    public var modelSortByCost = false
    public var homeSections = HomeSection.allCases
    public var hiddenHomeSections: Set<HomeSection> = [.devices]
    public var showHomeDeviceUsageBars = false
    public var homeQuotaSelection: Set<String>? = nil
    public var themeColor = ThemeColor.system
    public var customThemeColor = RGBColor(red: 0, green: 0.478, blue: 1)
    public var visibleHomeSections: [HomeSection] { [.usage] + homeSections.filter { $0 != .usage && !hiddenHomeSections.contains($0) } }
    public mutating func moveHomeSection(_ section: HomeSection, by offset: Int) {
        guard section != .usage else { return }
        homeSections = [.usage] + homeSections.filter { $0 != .usage }
        guard let from = homeSections.firstIndex(of: section), homeSections.indices.contains(from + offset), from + offset > 0 else { return }
        homeSections.swapAt(from, from + offset)
    }
    public mutating func moveHomeSection(_ section: HomeSection, to destination: HomeSection) {
        guard section != .usage, destination != .usage else { return }
        homeSections = [.usage] + homeSections.filter { $0 != .usage }
        guard let from = homeSections.firstIndex(of: section),
              let to = homeSections.firstIndex(of: destination), from != to else { return }
        homeSections.remove(at: from)
        homeSections.insert(section, at: to)
    }
    public init() {}
    enum CodingKeys: String, CodingKey { case automaticallyCheckForUpdates, schemaVersion, hubAddress, connected, tool, period, pinned, showPanelOnLaunch, modelSortByCost, homeSections, hiddenHomeSections, showHomeDeviceUsageBars, homeQuotaSelection, themeColor, customThemeColor }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        guard version <= 3 else { throw HubError.incompatible(L10n.text("设置来自较新版本")) }
        automaticallyCheckForUpdates = try c.decodeIfPresent(Bool.self, forKey: .automaticallyCheckForUpdates) ?? false
        schemaVersion = 3
        hubAddress = try c.decodeIfPresent(String.self, forKey: .hubAddress) ?? "http://127.0.0.1:17321"
        connected = try c.decodeIfPresent(Bool.self, forKey: .connected) ?? false
        tool = try c.decodeIfPresent(String.self, forKey: .tool) ?? "codex"
        period = try c.decodeIfPresent(Period.self, forKey: .period) ?? .month
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        showPanelOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showPanelOnLaunch) ?? true
        modelSortByCost = try c.decodeIfPresent(Bool.self, forKey: .modelSortByCost) ?? false
        homeSections = HomeSection.normalizedOrder(try c.decodeIfPresent([String].self, forKey: .homeSections) ?? [])
        hiddenHomeSections = Set((try c.decodeIfPresent([String].self, forKey: .hiddenHomeSections) ?? ["devices"]).compactMap(HomeSection.init(rawValue:)))
        showHomeDeviceUsageBars = try c.decodeIfPresent(Bool.self, forKey: .showHomeDeviceUsageBars) ?? false
        homeQuotaSelection = try c.decodeIfPresent(Set<String>.self, forKey: .homeQuotaSelection)
        if homeQuotaSelection?.isEmpty == true { homeQuotaSelection = nil }
        customThemeColor = (try? c.decode(RGBColor.self, forKey: .customThemeColor)) ?? customThemeColor
        themeColor = ThemeColor(rawValue: try c.decodeIfPresent(String.self, forKey: .themeColor) ?? "system") ?? .system
    }
}

public final class PreferencesFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return Preferences() }
        let data = try Data(contentsOf: url)
        let result = try JSONDecoder().decode(Preferences.self, from: data)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if (raw?["schemaVersion"] as? Int ?? 0) < 3 {
            let backup = url.appendingPathExtension("pre-v3-backup")
            if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) }
            try save(result)
        }
        return result
    }
    public func save(_ value: Preferences) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic])
    }
}
