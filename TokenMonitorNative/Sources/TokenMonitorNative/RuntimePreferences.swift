import SwiftUI
import MonitorCore

/// Observe individual preferences, not the entire Codable value on each selection change.
@MainActor @Observable final class RuntimePreferences {
    @ObservationIgnored var selectionChanged: (() -> Void)?
    var schemaVersion = 3
    var hubAddress = "http://127.0.0.1:17321"
    var connected = false
    var tool = "codex" { didSet { if oldValue != tool { selectionChanged?() } } }
    var period = Period.month { didSet { if oldValue != period { selectionChanged?() } } }
    var pinned = false
    var showPanelOnLaunch = true
    var modelSortByCost = false { didSet { if oldValue != modelSortByCost { selectionChanged?() } } }
    var homeSections = HomeSection.allCases
    var hiddenHomeSections = Set<HomeSection>([.devices])
    var showHomeDeviceUsageBars = false
    var homeQuotaSelection: Set<String>? = nil
    var themeColor = ThemeColor.system
    var customThemeColor = RGBColor(red: 0, green: 0.478, blue: 1)
    init(_ value: Preferences = Preferences()) {
        schemaVersion = value.schemaVersion
        hubAddress = value.hubAddress
        connected = value.connected
        tool = value.tool
        period = value.period
        pinned = value.pinned
        showPanelOnLaunch = value.showPanelOnLaunch
        modelSortByCost = value.modelSortByCost
        homeSections = value.homeSections
        hiddenHomeSections = value.hiddenHomeSections
        showHomeDeviceUsageBars = value.showHomeDeviceUsageBars
        homeQuotaSelection = value.homeQuotaSelection
        themeColor = value.themeColor
        customThemeColor = value.customThemeColor
    }
    var snapshot: Preferences {
        var value = Preferences()
        value.schemaVersion = schemaVersion
        value.hubAddress = hubAddress
        value.connected = connected
        value.tool = tool
        value.period = period
        value.pinned = pinned
        value.showPanelOnLaunch = showPanelOnLaunch
        value.modelSortByCost = modelSortByCost
        value.homeSections = homeSections
        value.hiddenHomeSections = hiddenHomeSections
        value.showHomeDeviceUsageBars = showHomeDeviceUsageBars
        value.homeQuotaSelection = homeQuotaSelection
        value.themeColor = themeColor
        value.customThemeColor = customThemeColor
        return value
    }
    var visibleHomeSections: [HomeSection] { [.usage] + homeSections.filter { $0 != .usage && !hiddenHomeSections.contains($0) } }
    func moveHomeSection(_ section: HomeSection, by offset: Int) {
        guard section != .usage else { return }
        homeSections = [.usage] + homeSections.filter { $0 != .usage }
        guard let from = homeSections.firstIndex(of: section), homeSections.indices.contains(from + offset), from + offset > 0 else { return }
        homeSections.swapAt(from, from + offset)
    }
    func moveHomeSection(_ section: HomeSection, to destination: HomeSection) {
        guard section != .usage, destination != .usage else { return }
        homeSections = [.usage] + homeSections.filter { $0 != .usage }
        guard let from = homeSections.firstIndex(of: section), let to = homeSections.firstIndex(of: destination), from != to else { return }
        homeSections.remove(at: from); homeSections.insert(section, at: to)
    }
}
