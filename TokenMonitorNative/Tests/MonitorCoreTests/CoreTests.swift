import XCTest
@testable import MonitorCore

final class CoreTests: XCTestCase {
    func fixture(_ name: String = "stats") throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
    }
    func changed(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture()) as! [String: Any]
        edit(&object); return try JSONSerialization.data(withJSONObject: object)
    }
    let now = DateCodec.parse("2026-09-13T04:00:00Z")!
    func testAuthoritativeToolPeriodModelAndCost() throws {
        let stats = try Stats.decode(fixture())
        for period in Period.allCases {
            let usage = stats.periods[period.rawValue]!
            for tool in ["", "codex", "claude"] {
                XCTAssertEqual(stats.devices.reduce(0) { $0 + ($1.periods[period.rawValue]?.tokens(tool: tool) ?? 0) }, usage.tokens(tool: tool))
                XCTAssertEqual(usage.modelRows(tool: tool).reduce(0) { $0 + $1.tokens }, usage.tokens(tool: tool))
            }
        }
        XCTAssertEqual(stats.periods["today"]?.cost(tool: "codex"), 1.6)
        XCTAssertNil(stats.periods["today"]?.tokens(tool: "unreported"))
    }
    func testCacheDropsUnknownAndAccountFields() throws {
        let data = try JSONEncoder().encode(Stats.decode(fixture()))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("email")); XCTAssertFalse(text.contains("futureField"))
    }
    func testRequiredFieldsFailRatherThanBecomeZero() throws {
        XCTAssertThrowsError(try Stats.decode(changed { $0.removeValue(forKey: "periods") }))
        XCTAssertThrowsError(try Stats.decode(changed { $0["updatedAt"] = "not-a-date" }))
        XCTAssertThrowsError(try Stats.decode(changed { object in
            var ps = object["periods"] as! [String:[String:Any]]; ps["today"]?["totalTokens"] = -1; object["periods"] = ps
        }))
    }
    func testStalenessUsesReportsNotTokenMovement() throws {
        let stats = try Stats.decode(fixture())
        XCTAssertFalse(stats.devices[0].isStale(at: now.addingTimeInterval(60), threshold: 600000))
        XCTAssertTrue(stats.devices[0].isStale(at: now.addingTimeInterval(601), threshold: 600000))
        XCTAssertTrue(stats.devices[1].isStale(at: now, threshold: 600000))
        XCTAssertTrue(stats.devices[0].periodExpired(.today, at: now.addingTimeInterval(86400)))
        XCTAssertFalse(stats.devices[0].periodExpired(.allTime, at: now.addingTimeInterval(86400)))
    }
    func testHistoryGapsRemainMissingAndZeroRemainsZero() throws {
        let history = try History.decode(fixture("history"))
        let points = history.points(monthly: false, tool: "codex", now: now)
        XCTAssertEqual(points.count, 30); XCTAssertEqual(points.filter { $0.tokens == nil }.count, 5)
        XCTAssertTrue(points.contains { $0.tokens == 0 })
        XCTAssertTrue(history.points(monthly: true, tool: "other", now: now).allSatisfy { $0.tokens == nil })
    }
    func testSSEAllByteBoundariesCRLFMultieventAndHeartbeat() throws {
        let object = try JSONSerialization.jsonObject(with: fixture())
        let envelope = try JSONSerialization.data(withJSONObject: ["stats":object])
        let json = String(decoding: envelope, as: UTF8.self)
        let wire = Data(("\u{feff}: hb\r\nevent: snapshot\r\ndata: \(json)\r\n\r\n: hb\n\nevent: stats\ndata: \(json)\n\n").utf8)
        for chunkSize in [1,2,3,7,1024,wire.count] {
            var parser = SSEParser(); var events:[SSEEvent] = []
            for offset in stride(from:0,to:wire.count,by:chunkSize) { events += try parser.feed(wire.subdata(in:offset..<min(offset+chunkSize,wire.count))) }
            XCTAssertEqual(events.count,2)
            XCTAssertEqual(try events[0].stats()?.periods["today"]?.totalTokens,125000)
            XCTAssertEqual(try events[1].stats()?.devices.count,2)
        }
    }
    func testSSEMultilineAndUnknownEvent() throws {
        var parser = SSEParser()
        let events = try parser.feed(Data("event: future\ndata: one\ndata: 二\n\n".utf8))
        XCTAssertEqual(events.first?.data,Data("one\n二".utf8))
        XCTAssertNil(try events.first?.stats())
        XCTAssertThrowsError(try parser.feed(Data(repeating:65,count:17*1024*1024)))
    }
    func testMalformedStatsEventReportsCompatibility() throws {
        var parser = SSEParser()
        let event = try XCTUnwrap(parser.feed(Data("event: stats\ndata: {bad-json\n\n".utf8)).first)
        XCTAssertThrowsError(try event.stats()) { error in
            guard case .incompatible = error as? HubError else { return XCTFail("Expected compatibility diagnostic") }
        }
    }
    func testRateMatchedDeltasResetAndIdle() throws {
        var tracker = LiveRateTracker(); let first = try Stats.decode(fixture())
        tracker.observe(first, now:now); XCTAssertNil(tracker.sample(now:now))
        let next = try Stats.decode(changed { object in
            var devices = object["devices"] as! [[String:Any]]
            var periods = devices[0]["periods"] as! [String:[String:Any]]
            periods["today"]?["timedTokens"] = 101000
            periods["today"]?["timedOutputTokens"] = 10200
            periods["today"]?["timedDurationMs"] = 12000
            devices[0]["periods"] = periods; object["devices"] = devices
        })
        tracker.observe(next, now:now.addingTimeInterval(1))
        XCTAssertEqual(tracker.sample(now:now.addingTimeInterval(1))?.burn,30000)
        XCTAssertEqual(tracker.sample(now:now.addingTimeInterval(1))?.speed,100)
        XCTAssertEqual(tracker.sample(now:now.addingTimeInterval(10))?.idle,true)
        XCTAssertNil(tracker.sample(now:now.addingTimeInterval(182)))
        tracker.observe(first, now:now.addingTimeInterval(2)); XCTAssertNil(tracker.sample(now:now.addingTimeInterval(2)))
        tracker.reset(); tracker.observe(next,now:now); XCTAssertNil(tracker.sample(now:now))
    }
    func testURLsAndSecrets() throws {
        let c = try HubConnection(address:"http://127.0.0.1:17321/",secret:"sample-only")
        XCTAssertEqual(c.request("api/stats").url?.absoluteString,"http://127.0.0.1:17321/api/stats")
        for url in ["file:///tmp/x","https://u:p@host","http://host?q=1","http://host/#x"] { XCTAssertThrowsError(try HubConnection(address:url,secret:"test")) }
        XCTAssertThrowsError(try HubConnection(address:"http://host",secret:""))
        XCTAssertThrowsError(try HubConnection(address:"http://host",secret:"a\nb"))
    }
    func testSettingsMigrationAndRollbackBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let file = PreferencesFile(url:dir.appendingPathComponent("settings.json"))
        let old = Data(#"{"hubAddress":"http://example.invalid:17321","tool":"claude"}"#.utf8)
        try old.write(to:file.url)
        let p = try file.load(); XCTAssertEqual(p.tool,"claude"); XCTAssertFalse(p.pinned)
        XCTAssertEqual(try Data(contentsOf:file.url.appendingPathExtension("pre-v4-backup")),old)
        XCTAssertEqual(try file.load(),p)
        try Data(#"{"schemaVersion":99}"#.utf8).write(to:file.url)
        XCTAssertThrowsError(try file.load())
    }
    func testLargeNumberAndUnknownModel() throws {
        XCTAssertFalse(DisplayFormat.tokens(9e15).isEmpty)
        let stats = try Stats.decode(fixture())
        XCTAssertTrue(stats.periods["today"]!.modelRows(tool:"").contains { $0.name == "unknown-model" })
    }
}
