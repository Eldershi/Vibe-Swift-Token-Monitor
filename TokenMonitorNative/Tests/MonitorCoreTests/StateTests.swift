import XCTest
@testable import MonitorCore
@testable import TokenMonitorNative

@MainActor final class StateTests: XCTestCase {
    func fixture(_ name: String) throws -> Data { try Data(contentsOf: Bundle.module.url(forResource:name,withExtension:"json",subdirectory:"Fixtures")!) }
    func store(pause: @escaping (Double) async throws -> Void = { try await Task.sleep(for:.milliseconds(Int($0))) }) -> AppStore {
        AppStore(ephemeral:true,makeClient:{ HubClient(connection:$0,protocolClasses:[MockURLProtocol.self]) },pause:pause)
    }
    func connection() throws -> HubConnection { try HubConnection(address:"http://test.invalid",secret:"test") }
    func until(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(for:.milliseconds(5)) }
        XCTFail("State transition timed out")
    }
    func testAuthenticationFailureStopsAutomaticRetriesAndKeepsCache() async throws {
        var requests = 0; let health = try fixture("health")
        MockURLProtocol.handler = { req in requests += 1; return req.url!.path == "/api/health" ? (200,"application/json",[health]) : (401,"application/json",[]) }
        let s = store(); s.stats = try Stats.decode(fixture("stats")); s.connect(try connection()); defer { s.stopConnection() }
        try await until { s.status == "密钥需要检查" }
        let count = requests; try await Task.sleep(for:.milliseconds(50))
        XCTAssertEqual(requests,count); XCTAssertFalse(s.online); XCTAssertEqual(s.stats?.devices.count,2)
    }
    func testNetworkBackoffCapsAtThirtySeconds() async throws {
        var delays:[Double] = []
        MockURLProtocol.handler = { _ in (503,"application/json",[]) }
        let s = store { delay in delays.append(delay); try await Task.sleep(for:.milliseconds(1)) }
        s.connect(try connection()); defer { s.stopConnection() }
        try await until { delays.count >= 8 }
        XCTAssertEqual(Array(delays.prefix(8)),[1,2,4,8,16,30,30,30]); XCTAssertFalse(s.online)
    }
    func testUnsupportedSSEPollsAndSleepWakeReconnectsFullSnapshot() async throws {
        let health = try fixture("health"), stats = try fixture("stats")
        var statsCalls = 0; var streamCalls = 0; var delays:[Double] = []
        MockURLProtocol.handler = { req in
            switch req.url!.path {
            case "/api/health": return (200,"application/json",[health])
            case "/api/stats": statsCalls += 1; return (200,"application/json",[stats])
            default: streamCalls += 1; return (404,"application/json",[])
            }
        }
        let s = store { delay in delays.append(delay); try await Task.sleep(for:.milliseconds(20)) }
        s.connect(try connection()); defer { s.stopConnection() }
        try await until { statsCalls >= 2 }
        XCTAssertTrue(s.online); XCTAssertEqual(streamCalls,1); XCTAssertEqual(delays.first,30)
        s.sleep(); let sleepingCalls = statsCalls
        XCTAssertFalse(s.online); XCTAssertNotNil(s.stats)
        try await Task.sleep(for:.milliseconds(40)); XCTAssertEqual(statsCalls,sleepingCalls)
        s.wake(); try await until { statsCalls > sleepingCalls && s.online }
        XCTAssertTrue(s.online)
    }
    func testBackendRestartRefetchesFullSnapshot() async throws {
        let health = try fixture("health"), stats = try fixture("stats")
        var healthCalls = 0; var statsCalls = 0
        MockURLProtocol.handler = { req in
            switch req.url!.path {
            case "/api/health": healthCalls += 1; return healthCalls == 2 ? (503,"application/json",[]) : (200,"application/json",[health])
            case "/api/stats": statsCalls += 1; return (200,"application/json",[stats])
            default: return (200,"text/event-stream",[Data(": hb\n\n".utf8)])
            }
        }
        let s = store(); s.connect(try connection()); defer { s.stopConnection() }
        try await until { statsCalls >= 2 }
        XCTAssertGreaterThanOrEqual(healthCalls,3); XCTAssertEqual(s.stats?.devices.count,2)
    }
    func testInvalidNewSnapshotPreservesLastGoodState() async throws {
        let health = try fixture("health")
        MockURLProtocol.handler = { req in req.url!.path == "/api/health" ? (200,"application/json",[health]) : (200,"application/json",[Data("{}".utf8)]) }
        let s = store(); s.stats = try Stats.decode(fixture("stats")); s.connect(try connection()); defer { s.stopConnection() }
        try await until { s.status == "数据格式需要检查" }
        XCTAssertEqual(s.stats?.periods["today"]?.totalTokens,125000); XCTAssertFalse(s.online)
    }
    func visibilityStore(clients: [String: Double], status: [String: String] = [:], stale: Bool = false) throws -> AppStore {
        var json = try JSONSerialization.jsonObject(with: fixture("stats")) as! [String: Any]
        let usage: [String: Any] = ["totalTokens": clients.values.reduce(0, +), "clients": clients]
        let periods = Dictionary(uniqueKeysWithValues: Period.allCases.map { ($0.rawValue, usage) })
        json["devices"] = [["deviceId": "test", "receivedAt": "2026-09-13T04:00:00Z", "stale": stale,
                            "trackedClients": ["codex", "claude", "unreported"], "clientStatus": status, "periods": periods]]
        let s = store(); s.stats = try Stats.decode(JSONSerialization.data(withJSONObject: json))
        s.now = DateCodec.parse("2026-09-13T04:01:00Z")!; s.receivedAt = s.now; s.online = true
        return s
    }
    func testSourceVisibilityPreservesZeroAndHidesMissingOrUnreported() throws {
        let s = try visibilityStore(clients: ["codex": 0, "claude": 100], status: ["claude": "missing"])
        XCTAssertEqual(s.tools, ["codex"])
        XCTAssertEqual(s.stats?.periods["today"]?.totalTokens, 125000, "Backend totals must not be rewritten")
        s.preferences.tool = "claude"; s.reconcileToolSelection()
        XCTAssertEqual(s.preferences.tool, "codex")
        s.preferences.tool = ""
        XCTAssertEqual(s.modelRows.map(\.name), ["gpt-example"])
    }
    func testSourceVisibilityUsesReportsAndPreservesDisconnectedSnapshot() throws {
        let s = try visibilityStore(clients: ["codex": 0])
        s.now = s.now.addingTimeInterval(3600)
        XCTAssertTrue(s.tools.isEmpty)
        s.online = false
        XCTAssertEqual(s.tools, ["codex"], "A Hub disconnect must preserve the last valid snapshot")
        let expired = try visibilityStore(clients: ["codex": 100], stale: true)
        XCTAssertTrue(expired.tools.isEmpty)
    }
    func testFreshDeviceKeepsSourceWhenAnotherDeviceIsStale() throws {
        let s = store(); s.stats = try Stats.decode(fixture("stats")); s.online = true
        s.now = DateCodec.parse("2026-09-13T04:01:00Z")!
        XCTAssertEqual(s.tools, ["claude", "codex"])
    }

}
