import XCTest
import MonitorCore
import NativeBackendCore
@testable import TokenMonitorNative

@MainActor final class PreviewHourlyTrendTests: XCTestCase {
    private func endpoint() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1, "pid": 123, "session": UUID().uuidString,
            "address": "http://127.0.0.1:12345", "secret": String(repeating: "a", count: 64)
        ])
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
    private func store() -> AppStore {
        let store = AppStore(ephemeral: true, makeClient: { HubClient(connection: $0, protocolClasses: [MockURLProtocol.self]) })
        store.preferences.period = .today
        return store
    }
    private func conversion() throws -> Data {
        let snapshot = try NativeSnapshot.make(events: [], deviceID: "synthetic-device")
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.conversion(deviceID: "synthetic-device", local: true)) as? [String: Any])
        var trend = value["trend"] as! [String: Any]
        var hourly = trend["hourly"] as! [String: Any]
        var points = hourly["points"] as! [[String: Any]]
        points[23]["tokens"] = 1234
        hourly["points"] = points; trend["hourly"] = hourly; value["trend"] = trend
        return try JSONSerialization.data(withJSONObject: value)
    }
    func testPreviewLoadsActualHourlySnapshotUsingOnlyGETAndKeepsQuotaSelection() async throws {
        let url = try endpoint(); defer { try? FileManager.default.removeItem(at: url) }
        let before = try Data(contentsOf: url), payload = try conversion()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.url?.path, "/local/api/beta/conversion")
            return (200, "application/json", [payload])
        }
        let store = store()
        let quota = try JSONDecoder().decode(ConversionSnapshot.self, from: payload)
        store.conversionSnapshot = quota
        await store.refreshPreviewHourlyTrend(endpointURL: url)
        XCTAssertNil(store.hourlyTrendError)
        XCTAssertEqual(store.trendPoints().count, 24)
        XCTAssertEqual(store.trendPoints().last?.tokens, 1234)
        XCTAssertEqual(store.trendPoints().filter { $0.tokens != nil }.count, 1)
        XCTAssertEqual(store.conversionSnapshot?.deviceId, quota.deviceId)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testUnavailableHourlySourceShowsReadErrorAndCanRecover() async throws {
        let url = try endpoint(); defer { try? FileManager.default.removeItem(at: url) }
        let store = store(), payload = try conversion()
        MockURLProtocol.handler = { _ in (200, "application/json", [payload]) }
        await store.refreshPreviewHourlyTrend(endpointURL: url)
        MockURLProtocol.handler = { _ in (503, "application/json", []) }
        await store.refreshPreviewHourlyTrend(endpointURL: url)
        XCTAssertTrue(store.trendPoints().isEmpty)
        XCTAssertNotNil(store.hourlyTrendError)
        XCTAssertEqual(store.trendEmptyMessage, store.hourlyTrendError)
        store.preferences.period = .month
        XCTAssertNotEqual(store.trendEmptyMessage, store.hourlyTrendError)
        MockURLProtocol.handler = { _ in (200, "application/json", [payload]) }
        await store.refreshPreviewHourlyTrend(endpointURL: url)
        XCTAssertNil(store.hourlyTrendError)
        XCTAssertEqual(store.rollingHourlyTrend?.points.last?.tokens, 1234)
    }
    func testMalformedAndMissingHourlyDataDoNotBecomeZeroUsage() async throws {
        let url = try endpoint(); defer { try? FileManager.default.removeItem(at: url) }
        let store = store()
        let snapshot = try NativeSnapshot.make(events: [], deviceID: "synthetic-device")
        let payload = try snapshot.conversion(deviceID: "synthetic-device", local: false)
        for response in [Data("{}".utf8), payload] {
            MockURLProtocol.handler = { _ in (200, "application/json", [response]) }
            await store.refreshPreviewHourlyTrend(endpointURL: url)
            XCTAssertNil(store.rollingHourlyTrend)
            XCTAssertNotNil(store.hourlyTrendError)
            XCTAssertTrue(store.trendPoints().isEmpty)
        }
    }
}
