import XCTest
@testable import MonitorCore
@testable import TokenMonitorNative

final class QuotaSelectionTests: XCTestCase {
    func provider(_ windows: String, name: String = "codex") throws -> QuotaProvider {
        try JSONDecoder().decode(QuotaProvider.self, from: Data("{\"provider\":\"\(name)\",\"status\":\"ok\",\"windows\":[\(windows)]}".utf8))
    }
    let weekly = #"{"kind":"weekly","remainingPercent":0,"windowMinutes":10080}"#
    let session = #"{"kind":"session","remainingPercent":75,"windowMinutes":300}"#
    let spark = #"{"kind":"weekly","limitId":"spark","additional":true,"label":"Spark","remainingPercent":100}"#
    let future = #"{"kind":"session","limitId":"future-model","additional":true,"label":"Future model","remainingPercent":90}"#

    func testDefaultsUseOnlyReportedMainCodexWindows() throws {
        let codex = try provider([weekly, session, spark].joined(separator: ","))
        let claude = try provider(weekly, name: "claude")
        let choices = QuotaSelection.choices(in: [codex, claude])
        let ids = QuotaSelection.effectiveIDs(selection: nil, choices: choices)
        let home = QuotaSelection.filtered([codex, claude], ids: ids)
        XCTAssertEqual(home.count, 1)
        XCTAssertEqual(home[0].windows.map(\.kind), ["weekly", "session"])
        XCTAssertEqual(home[0].windows[0].validPercent, 0)
        XCTAssertEqual(home[0].windows[1].title, L10n.text("5 小时"))
        let pro = try provider([weekly, spark].joined(separator: ","))
        XCTAssertFalse(QuotaSelection.choices(in: [pro]).contains { $0.title.contains(L10n.text("5 小时")) })
    }
    func testAdditionalOnlyIsNeverPromotedByAutomaticMode() throws {
        let p = try provider(spark)
        let choices = QuotaSelection.choices(in: [p])
        XCTAssertTrue(QuotaSelection.effectiveIDs(selection: nil, choices: choices).isEmpty)
        XCTAssertEqual(QuotaSelection.effectiveIDs(selection: [], choices: choices).count, 1)
    }
    func testRemovalAndNewModelDiscoveryRequireNoFixedModelList() throws {
        let before = try provider([weekly, spark].joined(separator: ","))
        let selected = Set([before.windows[1].selectionID(provider: "codex")])
        let after = try provider([weekly, future].joined(separator: ","))
        let choices = QuotaSelection.choices(in: [after])
        XCTAssertFalse(choices.contains { selected.contains($0.id) })
        XCTAssertTrue(choices.contains { $0.title.contains("Future model") })
        let fallback = QuotaSelection.effectiveIDs(selection: selected, choices: choices)
        XCTAssertEqual(fallback, Set([after.windows[0].selectionID(provider: "codex")]))
        XCTAssertTrue(QuotaSelection.effectiveIDs(selection: selected, choices: []).isEmpty)
    }
    func testCustomChoicesSurviveValueResetLabelAndDurationChanges() throws {
        let a = try provider(spark).windows[0]
        let b = try provider(#"{"kind":"weekly","limitId":"spark","additional":true,"label":"Renamed model","remainingPercent":5,"resetsAt":"2027-01-01T00:00:00Z","windowMinutes":10080}"#).windows[0]
        XCTAssertEqual(a.selectionID(provider: "codex"), b.selectionID(provider: "codex"))
        let choices = QuotaSelection.choices(in: [try provider([weekly, spark, future].joined(separator: ","))])
        let selected = Set([a.selectionID(provider: "codex")])
        XCTAssertEqual(QuotaSelection.effectiveIDs(selection: selected, choices: choices), selected)
    }
    func testUnknownQuotaIsNotAnOptionButZeroIs() throws {
        let p = try provider([weekly, #"{"kind":"session","remainingPercent":null}"#, #"{"kind":"daily","remainingPercent":200}"#].joined(separator: ","))
        XCTAssertEqual(QuotaSelection.choices(in: [p]).count, 1)
    }
    func testCacheRetainsPublicLaneMetadataWithoutAccountIdentity() throws {
        let p = try provider(spark)
        let cached = try JSONEncoder().encode(p)
        let restored = try JSONDecoder().decode(QuotaProvider.self, from: cached)
        XCTAssertEqual(restored.windows[0].limitId, "spark")
        XCTAssertEqual(restored.windows[0].additional, true)
        XCTAssertFalse(String(decoding: cached, as: UTF8.self).contains("accountKey"))
    }
    func testOldPreferencesDefaultAndCustomSelectionDiskRoundTrip() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data(#"{"schemaVersion":3}"#.utf8))
        XCTAssertNil(old.homeQuotaSelection)
        var value = old
        value.homeQuotaSelection = ["codex-lane"]
        let file = PreferencesFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("settings.json"))
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        try file.save(value)
        XCTAssertEqual(try file.load().homeQuotaSelection, value.homeQuotaSelection)
        XCTAssertEqual(try file.load().schemaVersion, 4)
    }
    @MainActor func testStoreFiltersQuotaDetailsAndKeepsHomeConfigurationIndependent() throws {
        let store = AppStore(ephemeral: true)
        var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: Bundle.module.url(forResource: "stats", withExtension: "json", subdirectory: "Fixtures")!)) as! [String: Any]
        raw["devices"] = []
        let stamp = "2026-09-14T12:00:00Z"
        let quota = try JSONSerialization.jsonObject(with: JSONEncoder().encode(provider([weekly, session, spark].joined(separator: ",")))) as! [String: Any]
        raw["limits"] = ["providers": [quota.merging(["updatedAt": stamp]) { _, new in new }, quota.merging(["provider": "claude", "updatedAt": stamp]) { _, new in new }]]
        store.now = DateCodec.parse(stamp)!
        store.stats = try Stats.decode(JSONSerialization.data(withJSONObject: raw))
        store.online = true
        XCTAssertEqual(store.quotaChoices.count, 3)
        XCTAssertEqual(store.homeQuotaProviders.first?.windows.count, 2)
        XCTAssertEqual(store.quotaProviders.first?.windows.count, 3)
        XCTAssertTrue(store.quotaDonutChoices.contains { $0.window.isAdditional })
        XCTAssertEqual(store.quotaProviders.count, 1)
        XCTAssertEqual(store.quotaReports.map(\.provider), ["codex"])
        XCTAssertEqual(store.stats?.limits?.providers.count, 2)
        store.preferences.homeQuotaSelection = [store.availableQuotaProviders[0].windows[2].selectionID(provider: "codex")]
        XCTAssertEqual(store.homeQuotaProviders.first?.windows.first?.limitId, "spark")
        store.now = store.now.addingTimeInterval(3600)
        XCTAssertTrue(store.quotaChoices.isEmpty)
        XCTAssertTrue(store.homeQuotaProviders.isEmpty)
    }
    @MainActor func testRuntimePreferencesCarrySelection() {
        var p = Preferences(); p.homeQuotaSelection = ["lane"]
        let runtime = RuntimePreferences(p)
        XCTAssertEqual(runtime.snapshot.homeQuotaSelection, p.homeQuotaSelection)
        runtime.homeQuotaSelection = nil
        XCTAssertNil(runtime.snapshot.homeQuotaSelection)
    }
}
