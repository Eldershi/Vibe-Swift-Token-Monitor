import XCTest
@testable import MonitorCore

final class HomePreferencesTests: XCTestCase {
    func testPreviousVersionMigratesWithoutChangingConnectionOrLayout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = PreferencesFile(url: directory.appendingPathComponent("settings.json"))
        let original = Data(#"{"schemaVersion":1,"hubAddress":"https://hub.example.invalid","connected":true,"tool":"claude","period":"allTime","pinned":true}"#.utf8)
        try original.write(to: file.url)
        let settings = try file.load()
        XCTAssertEqual(settings.schemaVersion, 4)
        XCTAssertEqual(settings.hubAddress, "https://hub.example.invalid")
        XCTAssertTrue(settings.connected); XCTAssertTrue(settings.pinned)
        XCTAssertEqual(settings.period, .allTime)
        XCTAssertEqual(settings.visibleHomeSections, [.usage, .quota, .models, .activity, .trends])
        XCTAssertEqual(settings.themeColor, .system)
        XCTAssertEqual(try Data(contentsOf: file.url.appendingPathExtension("pre-v4-backup")), original)
        XCTAssertEqual(try file.load(), settings)
    }
    func testOrderingVisibilityAndColorSurviveRoundTripIncludingEmptyHome() throws {
        var settings = Preferences()
        settings.hiddenHomeSections.remove(.devices)
        settings.moveHomeSection(.devices, by: -1)
        settings.moveHomeSection(.usage, by: -1) // first row must stay in bounds
        settings.themeColor = .purple
        XCTAssertEqual(settings.homeSections.prefix(3), [.usage, .devices, .quota])
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings); XCTAssertTrue(restored.visibleHomeSections.contains(.devices))
        settings.hiddenHomeSections = Set(HomeSection.allCases)
        let hidden = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(hidden.visibleHomeSections, [.usage])
    }
    func testUnknownAndDuplicateSectionsNormalizeWithoutLosingKnownChoices() throws {
        let json = Data(#"{"schemaVersion":2,"homeSections":["devices","future","devices","trends"],"hiddenHomeSections":["quota","future"],"themeColor":"future-color"}"#.utf8)
        let settings = try JSONDecoder().decode(Preferences.self, from: json)
        XCTAssertEqual(settings.homeSections, [.devices, .trends, .usage, .quota, .models, .activity])
        XCTAssertEqual(settings.hiddenHomeSections, [.quota])
        XCTAssertEqual(settings.themeColor, .system)
    }
    func testCustomSRGBAndDragOrderPersistToDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = PreferencesFile(url: directory.appendingPathComponent("settings.json"))
        var settings = Preferences()
        settings.themeColor = .custom
        settings.customThemeColor = RGBColor(red: 0.123456, green: 0.654321, blue: 0.456789)
        settings.moveHomeSection(.usage, to: .trends)
        XCTAssertEqual(settings.homeSections.first, .usage)
        settings.moveHomeSection(.devices, to: .quota)
        XCTAssertEqual(settings.homeSections[1], .devices)
        XCTAssertEqual(settings.hiddenHomeSections, [.devices])
        settings.moveHomeSection(.devices, to: .devices)
        XCTAssertEqual(Set(settings.homeSections).count, HomeSection.allCases.count)
        try file.save(settings)
        XCTAssertEqual(try file.load(), settings)
    }
    func testVersionTwoPresetAndOrderMigrateWithExactBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = PreferencesFile(url: directory.appendingPathComponent("settings.json"))
        let original = Data(#"{"schemaVersion":2,"themeColor":"teal","homeSections":["activity","usage"],"hiddenHomeSections":["rate"],"connected":true}"#.utf8)
        try original.write(to: file.url)
        let settings = try file.load()
        XCTAssertEqual(settings.schemaVersion, 4)
        XCTAssertEqual(settings.themeColor, .teal)
        XCTAssertEqual(Array(settings.homeSections.prefix(2)), [.activity, .usage])
        XCTAssertEqual(settings.hiddenHomeSections, [])
        XCTAssertTrue(settings.connected)
        XCTAssertEqual(try Data(contentsOf: file.url.appendingPathExtension("pre-v4-backup")), original)
    }
    func testInvalidCustomColorDoesNotDiscardConnectionOrLayout() throws {
        let json = Data(#"{"schemaVersion":3,"connected":true,"themeColor":"custom","customThemeColor":{"red":-1,"green":4,"blue":0},"homeSections":["trends"]}"#.utf8)
        let settings = try JSONDecoder().decode(Preferences.self, from: json)
        XCTAssertTrue(settings.connected)
        XCTAssertEqual(settings.homeSections.first, .trends)
        XCTAssertEqual(settings.customThemeColor, Preferences().customThemeColor)
    }

}
