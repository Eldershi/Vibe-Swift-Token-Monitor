import Foundation
import Testing
@testable import NativeBackendCore
@testable import TokenMonitorNative

private func timestamp(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

private func fixtureEvent(id: String, start: String, end: String, account: String) -> [String: Any] {
    ["id": id, "schemaVersion": 1, "policyVersion": 1,
     "kind": "cycleChanged", "derivation": "stableDeadlineMinusDuration",
     "inferredStartAt": start, "resetsAt": end,
     "identity": ["provider": "codex", "kind": "weekly", "limitId": "codex",
                  "durationMs": 604800000, "accountId": account]]
}

private func fixtureObservation(id: String, at: String, used: Double, end: String,
                                account: String, limit: String = "codex") -> [String: Any] {
    ["id": id, "schemaVersion": 1, "provider": "codex", "status": "ok", "accountId": account,
     "sourceObservedAt": at, "receivedAt": at,
     "windows": [["kind": "weekly", "limitId": limit, "windowMinutes": 10080,
                  "resetsAt": end, "usedPercent": used]]]
}

private func fixtureDevice(id: String, cost: Double) -> [String: Any] {
    ["deviceId": id, "limits": ["providers": [["provider": "codex", "accountKey": "synthetic-key"]]],
     "periodWindows": ["timeZone": "UTC"],
     "history": ["daily": [["date": "2026-09-16",
                            "perClient": ["codex": ["tokens": 100, "cost": cost]],
                            "perModel": ["gpt-synthetic": ["tokens": 100, "cost": cost]]]]]]
}

@Test func timelineUsesLastMatchedObservationAndHistoricalCompleteDays() throws {
    let start = "2026-09-14T10:00:00Z", end = "2026-09-21T10:00:00Z"
    let account = "synthetic-account-id"
    let event = fixtureEvent(id: "first", start: start, end: end, account: account)
    let rows = [fixtureObservation(id: "later", at: "2026-09-20T12:00:00Z", used: 80, end: end, account: account),
                fixtureObservation(id: "earlier", at: "2026-09-18T12:00:00Z", used: 40, end: end, account: account),
                fixtureObservation(id: "other", at: "2026-09-20T13:00:00Z", used: 99, end: end, account: "other"),
                fixtureObservation(id: "wrong-window", at: "2026-09-20T14:00:00Z", used: 99, end: end, account: account, limit: "spark")]
    let output = NativeQuotaCycleTimeline.make(events: [event], observations: rows,
        devices: [fixtureDevice(id: "a", cost: 10), fixtureDevice(id: "b", cost: 30)],
        accountID: account, accountKey: "synthetic-key", sourceID: nil,
        selected: ["kind": "weekly", "limitId": "codex", "windowMinutes": 10080,
                   "resetsAt": "2026-09-28T10:00:00Z"], currentResult: [:],
        now: timestamp("2026-09-23T00:00:00Z"))
    #expect(output.count == 1)
    #expect(output[0]["usedPercent"] as? Double == 80)
    let result = output[0]["result"] as! [String: Any]
    let allocation = result["approximation"] as! [String: Any]
    #expect(allocation["attributionAvailable"] as? Bool == true)
    let devices = allocation["devices"] as! [[String: Any]]
    #expect(devices.count == 2)
    #expect(abs((devices.first { $0["id"] as? String == "a" }?["quota"] as! Double) - 20) < 0.001)
    #expect(abs((devices.first { $0["id"] as? String == "b" }?["quota"] as! Double) - 60) < 0.001)
}

@Test func timelineKeepsMissingObservationAndIncompleteCostUnknown() {
    let account = "synthetic-account-id"
    let start = "2026-09-14T10:00:00Z", end = "2026-09-21T10:00:00Z"
    let event = fixtureEvent(id: "first", start: start, end: end, account: account)
    let selected: [String: Any] = ["kind": "weekly", "limitId": "codex", "windowMinutes": 10080,
                                   "resetsAt": "2026-09-28T10:00:00Z"]
    let missing = NativeQuotaCycleTimeline.make(events: [event], observations: [], devices: [],
        accountID: account, accountKey: "synthetic-key", sourceID: nil,
        selected: selected, currentResult: [:], now: timestamp("2026-09-23T00:00:00Z"))
    #expect(missing[0]["usedPercent"] is NSNull)
    let observed = NativeQuotaCycleTimeline.make(events: [event],
        observations: [fixtureObservation(id: "only", at: "2026-09-15T12:00:00Z", used: 25, end: end, account: account)],
        devices: [fixtureDevice(id: "a", cost: 10)], accountID: account,
        accountKey: "synthetic-key", sourceID: nil, selected: selected,
        currentResult: [:], now: timestamp("2026-09-23T00:00:00Z"))
    let result = observed[0]["result"] as! [String: Any]
    #expect((result["approximation"] as! [String: Any])["attributionAvailable"] as? Bool == false)
}

@Test func earlyCycleChangeClipsPreviousVisibleRange() {
    let account = "synthetic-account-id"
    let first = fixtureEvent(id: "first", start: "2026-09-21T10:00:00Z",
                             end: "2026-09-28T10:00:00Z", account: account)
    let second = fixtureEvent(id: "second", start: "2026-09-23T10:00:00Z",
                              end: "2026-09-30T10:00:00Z", account: account)
    let output = NativeQuotaCycleTimeline.make(events: [second, first], observations: [], devices: [],
        accountID: account, accountKey: "synthetic-key", sourceID: nil,
        selected: ["kind": "weekly", "limitId": "codex", "windowMinutes": 10080,
                   "resetsAt": "2026-09-30T10:00:00Z"], currentResult: [:],
        now: timestamp("2026-09-24T00:00:00Z"))
    #expect(output[0]["end"] as? String == "2026-09-23T10:00:00.000Z")
    #expect(output[1]["start"] as? String == "2026-09-23T10:00:00.000Z")
}

@Test func cycleGeometrySplitsNaturalWeeksAndSameDayBoundary() throws {
    let empty = #"{"attributionAvailable":false,"reasons":[],"mode":"approximate","devices":[],"models":[],"totalWeight":0,"simulationWeight":0,"unknownTokens":0,"remainingTokens":null}"#
    let result = try JSONDecoder().decode(ConversionSnapshot.Result.self, from: Data(empty.utf8))
    let a = ConversionSnapshot.Cycle(id: "a", kind: "cycleChanged", start: "2026-09-16T10:00:00Z",
        end: "2026-09-23T10:00:00Z", observedAt: nil, usedPercent: 50, result: result)
    let b = ConversionSnapshot.Cycle(id: "b", kind: "cycleChanged", start: "2026-09-23T10:00:00Z",
        end: "2026-09-30T10:00:00Z", observedAt: nil, usedPercent: 20, result: result)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2
    let first = timestamp("2026-09-14T00:00:00Z")
    let days = (0..<21).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    let segments = QuotaCycleGeometry.segments(days: days, cycles: [a, b], now: timestamp("2026-09-27T12:00:00Z"), calendar: calendar)
    let aSegments = segments.filter { $0.cycleID == "a" }
    #expect(aSegments.count == 2)
    #expect(aSegments[0].rect.minY == 28) // First known cycle extends to local midnight.
    let bSegments = segments.filter { $0.cycleID == "b" }
    #expect(bSegments.count == 1) // Future days are not rendered.
    #expect(aSegments[1].rect.maxY + 3 <= bSegments[0].rect.minY)
    #expect(QuotaCycleGeometry.drawsActivity(on: days[0], now: timestamp("2026-09-27T12:00:00Z"), cycles: [a, b], calendar: calendar))
    #expect(!QuotaCycleGeometry.drawsActivity(on: days[2], now: timestamp("2026-09-27T12:00:00Z"), cycles: [a, b], calendar: calendar))
    #expect(!QuotaCycleGeometry.drawsActivity(on: days[14], now: timestamp("2026-09-27T12:00:00Z"), cycles: [a, b], calendar: calendar))
}

@Test func veryShortCycleStopsAtCapsuleSizeInsideItsWeek() throws {
    let empty = #"{"attributionAvailable":false,"reasons":[],"mode":"approximate","devices":[],"models":[],"totalWeight":0,"simulationWeight":0,"unknownTokens":0,"remainingTokens":null}"#
    let result = try JSONDecoder().decode(ConversionSnapshot.Result.self, from: Data(empty.utf8))
    let cycle = ConversionSnapshot.Cycle(id: "short", kind: "cycleChanged",
        start: "2026-09-20T23:50:00Z", end: "2026-09-20T23:55:00Z",
        observedAt: nil, usedPercent: nil, result: result)
    let previous = ConversionSnapshot.Cycle(id: "previous", kind: "cycleChanged",
        start: "2026-09-13T00:00:00Z", end: "2026-09-14T00:00:00Z",
        observedAt: nil, usedPercent: 90, result: result)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2
    let first = timestamp("2026-09-14T00:00:00Z")
    let days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    let segments = QuotaCycleGeometry.segments(days: days, cycles: [previous, cycle], now: timestamp("2026-09-20T23:50:01Z"), calendar: calendar)
    #expect(segments.count == 1)
    #expect(segments[0].rect.height == QuotaCycleGeometry.minimumHeight)
    #expect(segments[0].rect.minY >= 8 && segments[0].rect.maxY <= 75)
    #expect(QuotaCycleGeometry.hitRect(for: segments[0]).height == 7)
}

@Test func shortCyclesCascadeInsideWeekWithConstantThreePointGaps() throws {
    let empty = #"{"attributionAvailable":false,"reasons":[],"mode":"approximate","devices":[],"models":[],"totalWeight":0,"simulationWeight":0,"unknownTokens":0,"remainingTokens":null}"#
    let result = try JSONDecoder().decode(ConversionSnapshot.Result.self, from: Data(empty.utf8))
    func cycle(_ id: String, _ start: String, _ end: String) -> ConversionSnapshot.Cycle {
        .init(id: id, kind: "cycleChanged", start: start, end: end,
              observedAt: nil, usedPercent: 50, result: result)
    }
    let cycles = [cycle("long", "2026-09-14T00:00:00Z", "2026-09-20T23:50:00Z"),
                  cycle("short-1", "2026-09-20T23:50:00Z", "2026-09-20T23:53:00Z"),
                  cycle("short-2", "2026-09-20T23:53:00Z", "2026-09-27T23:53:00Z")]
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2
    let days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: timestamp("2026-09-14T00:00:00Z"))! }
    let segments = QuotaCycleGeometry.segments(days: days, cycles: cycles,
        now: timestamp("2026-09-20T23:54:00Z"), calendar: calendar)
    #expect(segments.map(\.cycleID) == ["long", "short-1", "short-2"])
    #expect(segments[1].rect.height == QuotaCycleGeometry.minimumHeight && segments[2].rect.height == QuotaCycleGeometry.minimumHeight)
    #expect(abs(segments[1].rect.minY - segments[0].rect.maxY - 3) < 0.001)
    #expect(abs(segments[2].rect.minY - segments[1].rect.maxY - 3) < 0.001)
    #expect(segments[0].rect.minY >= 8 && segments[2].rect.maxY <= 75)
    #expect(QuotaCycleGeometry.dayIndex(at: CGPoint(x: 16, y: 8), count: days.count) == 0)
    #expect(QuotaCycleGeometry.dayIndex(at: CGPoint(x: 24, y: 8), count: days.count) == nil)
}
