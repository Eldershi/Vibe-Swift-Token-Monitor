import Foundation
import Testing
@testable import NativeBackendCore

private func usage(model: String = "gpt-6-sol", input: Int64 = 100_000, cached: Int64 = 80_000,
                   output: Int64 = 10_000, tier: String? = nil, context: Int64? = nil) -> NativeUsageEvent {
    NativeUsageEvent(timestamp: ISO8601DateFormatter().date(from: "2026-09-23T12:00:00Z")!,
                     model: model, input: input, cached: cached, output: output,
                     serviceTier: tier, requestInput: context)
}
@Test func modelPricesSeparateAPIFastAndCodexCredits() throws {
    let normal = try #require(NativeModelPricing.estimate(usage()))
    #expect(abs(normal.dollars - 0.156) < 0.0000001)
    #expect(abs(normal.credits - 3.9) < 0.0000001)
    let fast = try #require(NativeModelPricing.estimate(usage(tier: "fast")))
    #expect(fast.dollars == normal.dollars * 2)
    #expect(fast.credits == normal.credits * 2.5)
    let astra = try #require(NativeModelPricing.estimate(usage(model: "gpt-6-astra")))
    let luna = try #require(NativeModelPricing.estimate(usage(model: "gpt-6-luna")))
    #expect(abs(astra.dollars - normal.dollars * 5) < 0.0000001)
    #expect(abs(luna.dollars - normal.dollars / 20) < 0.0000001)
}
@Test func priceContextThresholdAndUnknownModelsStayDistinct() throws {
    let boundary = try #require(NativeModelPricing.estimate(usage(context: 272_000)))
    let long = try #require(NativeModelPricing.estimate(usage(context: 272_001)))
    #expect(abs(long.dollars - 0.262) < 0.0000001)
    #expect(boundary.credits == long.credits)
    #expect(NativeModelPricing.estimate(usage(model: "codex-auto-review")) == nil)
    #expect(NativeModelPricing.estimate(usage(model: "gpt-6-sol-unknown")) == nil)
    #expect(NativeModelPricing.estimate(usage(tier: "unknown")) == nil)
    #expect(NativeModelPricing.estimate(usage(cached: 100_001)) == nil)
}
private func record(_ event: NativeUsageEvent) throws -> [String: Any] {
    let now = event.timestamp.addingTimeInterval(60)
    return try JSONSerialization.jsonObject(with: NativeSnapshot.make(events: [event], deviceID: "synthetic-local", now: now).deviceRecord) as! [String: Any]
}
@Test func priceOverlayRequiresExactCoverageAndPreservesTokenCounts() throws {
    let event = usage(), original = try record(event)
    let enriched = NativeModelPricing.enrich(device: original, events: [event])
    let periods = enriched["periods"] as! [String: [String: Any]]
    let all = periods["allTime"]!
    #expect((all["totalTokens"] as? Double) == 110_000)
    let costs = all["clientModelCosts"] as! [String: [String: Double]]
    #expect(abs(costs["codex"]!["gpt-6-sol"]! - 0.156) < 0.0000001)
    let missing = NativeModelPricing.enrich(device: original, events: [])
    #expect(((missing["periods"] as! [String: [String: Any]])["allTime"]?["clientModelCosts"] as? [String: [String: Double]])?["codex"]?["gpt-6-sol"] == nil)
    let extra = NativeModelPricing.enrich(device: original, events: [event, event])
    #expect(((extra["periods"] as! [String: [String: Any]])["allTime"]?["clientModelCosts"] as? [String: [String: Double]])?["codex"]?["gpt-6-sol"] == nil)
    let history = enriched["history"] as! [String: Any]
    let day = (history["daily"] as! [[String: Any]])[0]
    let model = (day["perModel"] as! [String: [String: Any]])["gpt-6-sol"]!
    #expect(abs((model["quotaWeight"] as! Double) - 0.156) < 0.0000001)
}
@Test func priceOverlayDoesNotPriceOtherDeviceOrPartialAggregate() throws {
    let event = usage(), snapshot = try NativeSnapshot.make(events: [event], deviceID: "synthetic-local", now: event.timestamp.addingTimeInterval(60))
    let device = try JSONSerialization.jsonObject(with: snapshot.deviceRecord)
    let devices = try JSONSerialization.data(withJSONObject: ["devices": [device]])
    let correct = try NativeModelPricing.enrich(stats: snapshot.stats, devices: devices, deviceID: "synthetic-local", events: [event])
    let wrong = try NativeModelPricing.enrich(stats: snapshot.stats, devices: devices, deviceID: "another-device", events: [event])
    func cost(_ data: Data) throws -> Double? {
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return (((root["periods"] as? [String: [String: Any]])?["allTime"]?["clientModelCosts"]) as? [String: [String: Double]])?["codex"]?["gpt-6-sol"]
    }
    #expect(try cost(correct.stats) != nil)
    #expect(try cost(wrong.stats) == nil)
}
@Test func scannerCarriesTierAndRequestContextIntoPrices() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"type":"turn_context","payload":{"model":"gpt-6-sol","service_tier":"fast"}}"#.utf8).write(to: url)
    let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd()
    try handle.write(contentsOf: Data(("\n" + #"{"timestamp":"2026-09-23T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300000,"cached_input_tokens":200000,"output_tokens":10000}}}}"# + "\n").utf8)); try handle.close()
    let event = try #require(CodexScanner.scanFile(url).first)
    #expect(event.serviceTier == "fast")
    #expect(event.requestInput == 300_000)
    #expect(NativeModelPricing.estimate(event) != nil)
}

@Test func pricingUsesSameStatsSnapshotWhenDeviceRequestIsNewer() throws {
    let event = usage(), now = event.timestamp.addingTimeInterval(60)
    let snapshot = try NativeSnapshot.make(events: [event], deviceID: "synthetic-local", now: now)
    let newer = try NativeSnapshot.make(events: [event, event], deviceID: "synthetic-local", now: now)
    let devices = try JSONSerialization.data(withJSONObject: ["devices": [JSONSerialization.jsonObject(with: newer.deviceRecord)]])
    let result = try NativeModelPricing.enrich(stats: snapshot.stats, devices: devices, deviceID: "synthetic-local", events: [event])
    let root = try JSONSerialization.jsonObject(with: result.stats) as! [String: Any]
    let row = (root["periods"] as! [String: [String: Any]])["allTime"]!
    let price = (row["clientModelCosts"] as? [String: [String: Double]])?["codex"]?["gpt-6-sol"]
    #expect(abs(try #require(price) - 0.156) < 0.0000001)
}

@Test func pricingExcludesExpiredDeviceTodayCountsLikeHubAggregate() throws {
    let event = usage(), now = event.timestamp.addingTimeInterval(60)
    let snapshot = try NativeSnapshot.make(events: [event], deviceID: "synthetic-local", now: now)
    var root = try JSONSerialization.jsonObject(with: snapshot.stats) as! [String: Any]
    var rows = root["devices"] as! [[String: Any]], old = rows[0]
    old["deviceId"] = "expired-peer"
    old["periodWindows"] = ["today": ["endsAt": "2026-09-23T00:00:00Z"], "timeZone": "UTC"]
    rows.append(old); root["devices"] = rows
    let result = try NativeModelPricing.enrich(stats: JSONSerialization.data(withJSONObject: root),
        devices: JSONSerialization.data(withJSONObject: ["devices": rows]), deviceID: "synthetic-local", events: [event])
    let priced = try JSONSerialization.jsonObject(with: result.stats) as! [String: Any]
    let row = (priced["periods"] as! [String: [String: Any]])["today"]!
    let cost = (row["clientModelCosts"] as? [String: [String: Double]])?["codex"]?["gpt-6-sol"]
    #expect(abs(try #require(cost) - 0.156) < 0.0000001)
}
