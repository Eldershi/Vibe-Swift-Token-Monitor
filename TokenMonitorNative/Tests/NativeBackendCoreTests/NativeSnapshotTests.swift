import Foundation
import Testing
@testable import NativeBackendCore
import MonitorCore

@Test func generatedNativeStatsDecodeWithExistingUIContract() throws {
    let now = ISO8601DateFormatter().date(from: "2026-09-22T10:00:00Z")!
    let event = NativeUsageEvent(timestamp: now.addingTimeInterval(-60), model: "gpt-test",
                                 input: 100, cached: 20, output: 10)
    let snapshot = try NativeSnapshot.make(events: [event], deviceID: "native-test", now: now)
    let stats = try Stats.decode(snapshot.stats)
    let history = try History.decode(snapshot.history)
    #expect(stats.periods["today"]?.totalTokens == 110)
    #expect(stats.periods["today"]?.cacheReadTokens == 20)
    #expect(stats.devices.first?.periods["allTime"]?.clients?["codex"] == 110)
    #expect(history.daily.reduce(0) { $0 + $1.tokens } == 110)
    #expect(stats.historyRevision != nil)
    let updated = try NativeSnapshot.make(events: [event, event], deviceID: "native-test", now: now)
    #expect(try Stats.decode(updated.stats).historyRevision != stats.historyRevision)
}

@Test func rolling24NativeTrendAndConversionEnvelope() throws {
    let now = ISO8601DateFormatter().date(from: "2026-09-22T10:15:00Z")!
    let event = NativeUsageEvent(timestamp: now.addingTimeInterval(-60), model: "synthetic",
                                 input: 100, cached: 10, output: 5)
    let snapshot = try NativeSnapshot.make(events: [event], deviceID: "native-test", now: now)
    let value = try JSONSerialization.jsonObject(with: snapshot.conversion(deviceID: "native-test", local: true)) as! [String: Any]
    let trend = value["trend"] as! [String: Any]
    let hourly = trend["hourly"] as! [String: Any]
    let points = hourly["points"] as! [[String: Any]]
    #expect(points.count == 24)
    #expect(points.last?["tokens"] as? Int == 105)
    #expect((value["result"] as! [String: Any])["attributionAvailable"] as? Bool == false)
    let remote = try JSONSerialization.jsonObject(with: snapshot.conversion(deviceID: "native-test", local: false)) as! [String: Any]
    #expect((remote["trend"] as! [String: Any])["hourly"] is NSNull)
}
