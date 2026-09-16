import XCTest
@testable import MonitorCore
@testable import TokenMonitorNative

final class Beta3PresentationTests: XCTestCase {
    func testLegacyPaletteMigrationAndIndependentObjectOverrides() throws {
        var old = ChartStyle(); old.preset = "custom"; old.slots = ["model:a": 1, "device:b": 1]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "objectColors")
        var restored = try JSONDecoder().decode(ChartStyle.self, from: JSONSerialization.data(withJSONObject: json))
        let before = restored.color(id: "device:b", activeIDs: ["device:b"])
        restored.objectColors = ["model:a": ChartStyle.rgb(0x123456)]
        let encoded = try JSONEncoder().encode(restored)
        let result = try JSONDecoder().decode(ChartStyle.self, from: encoded)
        XCTAssertEqual(result.color(id: "device:b", activeIDs: []), before)
        XCTAssertEqual(result.color(id: "model:a", activeIDs: []), ChartStyle.rgb(0x123456))
    }
    func testAccountDigestDeduplicatesNewestReportWithoutRetainingRawIdentity() throws {
        func report(_ date: String, _ key: String) throws -> QuotaProvider {
            let raw: [String: Any] = ["provider":"codex", "status":"ok", "updatedAt":date, "accountKey":key, "accountEmail":"private@example.invalid", "windows":[["kind":"weekly", "remainingPercent":50]]]
            return try JSONDecoder().decode(QuotaProvider.self, from: JSONSerialization.data(withJSONObject: raw))
        }
        let a = try report("2026-09-16T00:00:00Z", "synthetic-account")
        let b = try report("2026-09-16T01:00:00Z", "synthetic-account")
        let c = try report("2026-09-16T00:00:00Z", "another-account")
        let reports = QuotaNaming.reports([a,b,c])
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports.first(where: { $0.accountId == a.accountId })?.updatedAt, b.updatedAt)
        let encoded = String(decoding: try JSONEncoder().encode(reports), as: UTF8.self)
        XCTAssertFalse(encoded.contains("synthetic-account")); XCTAssertFalse(encoded.contains("private@example"))
        XCTAssertEqual(QuotaNaming.reports([a,b], tool: "claude").count, 0)
    }
    func testUnknownAccountsAreNotMergedAndWindowNamesStayShort() throws {
        let data = Data(#"{"provider":"codex","status":"ok","windows":[]}"#.utf8)
        let report = try JSONDecoder().decode(QuotaProvider.self, from: data)
        XCTAssertEqual(QuotaNaming.reports([report,report]).count, 2)
        XCTAssertEqual(QuotaNaming.window(kind: "weekly", label: "GPT-5.3-Codex-Spark", minutes: 10080), "Spark " + L10n.text("每周"))
        XCTAssertEqual(QuotaNaming.window(kind: "session", label: "5h", minutes: 300), L10n.text("5 小时"))
    }
    func testOtherColorIsIndependentAcrossCharts() {
        var style = ChartStyle()
        style.objectColors = ["aggregate:other:model": ChartStyle.rgb(0x123456)]
        XCTAssertEqual(style.color(id: "aggregate:other:device", activeIDs: []), style.other)
        XCTAssertNotEqual(style.color(id: "aggregate:other:model", activeIDs: []), style.other)
    }
}
