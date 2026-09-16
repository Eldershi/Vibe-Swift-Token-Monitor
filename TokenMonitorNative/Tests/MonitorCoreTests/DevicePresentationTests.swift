import XCTest
import AppKit
@testable import MonitorCore
@testable import TokenMonitorNative

final class DevicePresentationTests: XCTestCase {
    private func device(_ states: String, clients: String = "{}") throws -> Device {
        try JSONDecoder().decode(Device.self, from: Data("""
        {"deviceId":"test-device","periods":{"allTime":{"totalTokens":100,"clients":\(clients)}},"clientHealth":{"clients":\(states)}}
        """.utf8))
    }
    func testUnusedMissingToolsDoNotWarnAboutHealthyDevice() throws {
        let device = try device(#"{"codex":{"overall":"healthy"},"claude":{"overall":"unavailable"}}"#, clients: #"{"codex":100}"#)
        XCTAssertNil(device.collectionNote(tool: ""))
        XCTAssertTrue(device.collectionNote(tool: "claude")?.contains("Claude") == true)
    }
    func testPreviouslyUsedMissingSourceAndMultipleFaultsAreNamed() throws {
        let device = try device(#"{"codex":{"overall":"unavailable"},"claude":{"overall":"attention"}}"#, clients: #"{"codex":100}"#)
        let note = try XCTUnwrap(device.collectionNote(tool: ""))
        XCTAssertTrue(note.contains("Codex")); XCTAssertTrue(note.contains("Claude"))
        XCTAssertFalse(device.collectionNote(tool: "codex")?.contains("Claude") == true)
    }
    func testLegacyMissingSourceUsesSameRelevanceRule() throws {
        let data = Data(#"{"deviceId":"test","periods":{},"clientStatus":{"codex":"missing"}}"#.utf8)
        let device = try JSONDecoder().decode(Device.self, from: data)
        XCTAssertNil(device.collectionNote(tool: ""))
        XCTAssertTrue(device.collectionNote(tool: "codex")?.contains("Codex") == true)
    }
    func testWaitingForUsageIsNotACollectionWarning() throws {
        let value = try device(#"{"copilot":{"overall":"waiting"},"codex":{"overall":"healthy"}}"#)
        XCTAssertNil(value.collectionNote(tool: ""))
        XCTAssertNil(value.collectionNote(tool: "copilot"))
    }
    func testOperatingSystemAliasesAndFallback() {
        for name in ["macOS", "Darwin", " Mac OS X "] { XCTAssertEqual(DeviceOperatingSystem(name), .apple) }
        for name in ["Windows", "win32", "Windows 11", "Windows_NT"] { XCTAssertEqual(DeviceOperatingSystem(name), .windows) }
        XCTAssertEqual(DeviceOperatingSystem("LINUX"), .linux)
        for name in [nil, "", "FreeBSD"] { XCTAssertEqual(DeviceOperatingSystem(name), .other) }
    }
    @MainActor func testUsageRemainsFirstDespiteLegacyHiddenOrMovedPreference() {
        var prefs = Preferences()
        prefs.homeSections = [.quota, .devices, .usage]
        prefs.hiddenHomeSections = [.usage]
        XCTAssertEqual(prefs.visibleHomeSections, [.usage, .quota, .devices])
        XCTAssertEqual(RuntimePreferences(prefs).visibleHomeSections, prefs.visibleHomeSections)
        prefs.moveHomeSection(.devices, by: -1)
        XCTAssertEqual(prefs.visibleHomeSections, [.usage, .devices, .quota])
        let runtime = RuntimePreferences(prefs)
        runtime.moveHomeSection(.devices, by: -1)
        XCTAssertEqual(runtime.visibleHomeSections, prefs.visibleHomeSections)
        XCTAssertNil(Page(rawValue: "用量"))
        XCTAssertNotNil(NSImage(systemSymbolName: "applelogo", accessibilityDescription: nil))
    }
}
