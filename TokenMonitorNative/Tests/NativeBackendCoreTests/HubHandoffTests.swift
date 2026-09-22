import Foundation
import Testing
@testable import NativeBackendCore

@Test func handoffAddsOnlyPostCutoffUsageAndSurvivesRetry() throws {
    let cutoff = ISO8601DateFormatter().date(from: "2026-09-22T01:00:00Z")!
    let later = cutoff.addingTimeInterval(3600)
    let before = NativeUsageEvent(timestamp: cutoff.addingTimeInterval(-60), model: "synthetic",
                                  input: 100, cached: 80, output: 10)
    let after = NativeUsageEvent(timestamp: later.addingTimeInterval(-60), model: "synthetic",
                                 input: 50, cached: 40, output: 5)
    let baseline = try NativeSnapshot.make(events: [before], deviceID: "synthetic-device", now: cutoff,
                                           hostname: "synthetic-host")
    var remote = try JSONSerialization.jsonObject(with: baseline.deviceRecord) as! [String: Any]
    var periods = remote["periods"] as! [String: [String: Any]]
    for name in ["today", "month", "allTime"] {
        periods[name]!["totalTokens"] = 1_000
        periods[name]!["clients"] = ["codex": 1_000]
        periods[name]!["models"] = ["synthetic": 1_000]
    }
    remote["periods"] = periods
    remote["limits"] = ["providers": [["provider": "codex", "status": "ok"]]]
    let remoteData = try JSONSerialization.data(withJSONObject: remote)
    var handoff = try HubHandoff(address: "https://example.test", deviceID: "synthetic-device",
                                 remote: remoteData, localAtRemoteUpdate: baseline.deviceRecord)
    let current = try NativeSnapshot.make(events: [before, after], deviceID: "synthetic-device",
                                          now: later, hostname: "synthetic-host")
    #expect(try handoff.advance(localData: current.deviceRecord))
    let payload = try JSONSerialization.jsonObject(with: handoff.upload()) as! [String: Any]
    let sent = payload["periods"] as! [String: [String: Any]]
    #expect((sent["allTime"]!["totalTokens"] as! NSNumber).intValue == 1_055)
    #expect((sent["allTime"]!["clients"] as! [String: NSNumber])["codex"]!.intValue == 1_055)
    #expect(payload["limits"] == nil)
    #expect(handoff.pendingUpload)
    var restored = try HubHandoff(saved: handoff.saved())
    #expect(try restored.upload() == handoff.upload())
    #expect(!(try restored.advance(localData: current.deviceRecord)))
    restored.acknowledged()
    #expect(!restored.pendingUpload)
    let regressed = try NativeSnapshot.make(events: [before], deviceID: "synthetic-device",
                                            now: later, hostname: "synthetic-host")
    _ = try restored.advance(localData: regressed.deviceRecord)
    let stable = try JSONSerialization.jsonObject(with: restored.upload()) as! [String: Any]
    let stableTotal = ((stable["periods"] as! [String: [String: Any]])["allTime"]!["totalTokens"] as! NSNumber).intValue
    #expect(stableTotal == 1_055)
}

@Test func handoffRejectsAnotherDeviceAndResetsNewDayWindow() throws {
    let start = ISO8601DateFormatter().date(from: "2026-09-22T15:00:00Z")!
    let next = start.addingTimeInterval(7200)
    let before = NativeUsageEvent(timestamp: start.addingTimeInterval(-30), model: "synthetic",
                                  input: 100, cached: 0, output: 0)
    let after = NativeUsageEvent(timestamp: next.addingTimeInterval(-30), model: "synthetic",
                                 input: 20, cached: 0, output: 0)
    let baseline = try NativeSnapshot.make(events: [before], deviceID: "a", now: start, hostname: "synthetic")
    var handoff = try HubHandoff(address: "https://example.test", deviceID: "a", remote: baseline.deviceRecord,
                                 localAtRemoteUpdate: baseline.deviceRecord)
    let wrong = try NativeSnapshot.make(events: [before, after], deviceID: "b", now: next, hostname: "synthetic")
    #expect(throws: HandoffError.self) { try handoff.advance(localData: wrong.deviceRecord) }
    let current = try NativeSnapshot.make(events: [before, after], deviceID: "a", now: next, hostname: "synthetic")
    _ = try handoff.advance(localData: current.deviceRecord)
    let payload = try JSONSerialization.jsonObject(with: handoff.upload()) as! [String: Any]
    let periods = payload["periods"] as! [String: [String: Any]]
    #expect((periods["today"]!["totalTokens"] as! NSNumber).intValue == 20)
    #expect((periods["allTime"]!["totalTokens"] as! NSNumber).intValue == 120)
}
