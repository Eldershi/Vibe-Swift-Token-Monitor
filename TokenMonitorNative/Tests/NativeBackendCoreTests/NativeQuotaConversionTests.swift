import Foundation
import Testing
@testable import NativeBackendCore
@testable import TokenMonitorNative

private func quotaFixture(account: String = "synthetic-account", cost: Double = 10, tokens: Int = 100,
                          id: String = "synthetic-device") -> [String: Any] {
    ["deviceId": id, "updatedAt": "2026-09-22T00:00:00.000Z",
     "periodWindows": ["timeZone": "UTC"],
     "limits": ["providers": [["provider": "codex", "accountKey": account]]],
     "history": ["daily": [["date": "2026-09-20", "perClient": ["codex": ["tokens": tokens, "cost": cost]],
                             "perModel": ["synthetic-model": ["tokens": tokens, "cost": cost]]]]]]
}

@Test func nativeQuotaProjectionUsesFreshMatchedAccountAndCompleteDays() throws {
    let window: [String: Any] = ["kind": "weekly", "windowMinutes": 10_080,
                                 "remainingPercent": 40, "resetsAt": "2026-09-28T00:00:00.000Z",
                                 "limitId": "codex"]
    let provider: [String: Any] = ["provider": "codex", "status": "ok",
                                   "accountKey": "synthetic-account", "sourceDeviceId": "synthetic-device",
                                   "updatedAt": "2026-09-22T00:00:00.000Z",
                                   "windows": [["kind": "billing", "windowMinutes": 10_080], window]]
    let stats: [String: Any] = ["limits": ["providers": [provider]]]
    let devices: [String: Any] = ["devices": [quotaFixture(),
        quotaFixture(cost: 20, tokens: 200, id: "synthetic-peer"),
        quotaFixture(account: "other-account", id: "excluded-peer")]]
    let now = ISO8601DateFormatter().date(from: "2026-09-22T00:05:00Z")!
    let output = try NativeQuotaConversion.make(stats: JSONSerialization.data(withJSONObject: stats),
        devices: JSONSerialization.data(withJSONObject: devices), deviceID: "synthetic-device", hourly: nil, now: now)
    let decoded = try JSONDecoder().decode(ConversionSnapshot.self, from: output)
    #expect(decoded.result.approximation?.devices.count == 2)
    let value = try JSONSerialization.jsonObject(with: output) as! [String: Any]
    let choices = value["choices"] as! [[String: Any]]
    #expect(choices.count == 1)
    let result = value["result"] as! [String: Any]
    #expect(result["attributionAvailable"] as? Bool == false)
    let approximate = result["approximation"] as! [String: Any]
    #expect(approximate["attributionAvailable"] as? Bool == true)
    let rows = approximate["devices"] as! [[String: Any]]
    #expect(rows.count == 2)
    let quotas = rows.compactMap { $0["quota"] as? Double }.sorted()
    #expect(abs(quotas[0] - 20) < 0.0001)
    #expect(abs(quotas[1] - 40) < 0.0001)
    #expect(approximate["missingDevices"] as? [String] == ["excluded-peer"])
    #expect(value["accountId"] as? String != "synthetic-account")

    let expired = try NativeQuotaConversion.make(stats: JSONSerialization.data(withJSONObject: stats),
        devices: JSONSerialization.data(withJSONObject: devices), deviceID: "synthetic-device", hourly: nil,
        now: now.addingTimeInterval(660))
    let stale = try JSONSerialization.jsonObject(with: expired) as! [String: Any]
    let staleResult = stale["result"] as! [String: Any]
    let staleApproximation = staleResult["approximation"] as! [String: Any]
    #expect(staleApproximation["attributionAvailable"] as? Bool == false)
    #expect((staleApproximation["devices"] as! [[String: Any]]).isEmpty)
}

@Test func nativeCycleConfirmationAndSparkIsolation() throws {
    let observed = "2026-09-22T00:00:00.000Z"
    let reset = "2026-09-28T00:00:00.000Z"
    let account = "synthetic-account"
    let accountID = NativeQuotaObservation.hash("codex\n" + account)
    let main: [String: Any] = ["kind": "weekly", "windowMinutes": 10080, "remainingPercent": 40,
                               "resetsAt": reset, "limitId": "codex"]
    var spark = main; spark["limitId"] = "codex-spark"; spark["additional"] = true
    let provider: [String: Any] = ["provider": "codex", "status": "ok", "accountKey": account,
                                   "sourceDeviceId": "synthetic-device", "updatedAt": observed, "windows": [main, spark]]
    var device = quotaFixture(cost: 30, tokens: 300)
    device["history"] = ["daily": [["date": "2026-09-20", "perClient": ["codex": ["tokens": 300, "cost": 30]],
       "perModel": ["regular-model": ["tokens": 100, "cost": 10], "gpt-spark": ["tokens": 200, "cost": 20]]]]]
    func event(_ limit: String, account: String = accountID, end: String = reset) -> [String: Any] {
        ["schemaVersion": 1, "policyVersion": 1, "id": limit, "identity": ["provider": "codex", "accountId": account,
          "kind": "weekly", "limitId": limit, "durationMs": 604800000], "kind": "cycleChanged",
         "derivation": "stableDeadlineMinusDuration", "inferredStartAt": "2026-09-21T00:00:00.000Z",
         "resetsAt": end, "confirmedAt": "2026-09-21T00:02:00.000Z", "recordedAt": "2026-09-21T00:02:00.000Z"]
    }
    func make(_ events: [[String: Any]], selected: String? = nil) throws -> ConversionSnapshot {
        let data = try NativeQuotaConversion.make(stats: JSONSerialization.data(withJSONObject: ["limits": ["providers": [provider]]]),
          devices: JSONSerialization.data(withJSONObject: ["devices": [device]]), deviceID: "synthetic-device", hourly: nil,
          selectedChoiceID: selected, cycleEvents: events, cycleCapability: true,
          now: ISO8601DateFormatter().date(from: "2026-09-22T00:05:00Z")!)
        return try JSONDecoder().decode(ConversionSnapshot.self, from: data)
    }
    let pending = try make([])
    #expect(pending.result.range?.cycleStatus == "pending")
    #expect(pending.result.approximation?.attributionAvailable == false)
    #expect(try make([event("codex", account: "different")]).result.approximation?.attributionAvailable == false)
    #expect(try make([event("codex", end: "2026-09-29T00:00:00.000Z")]).result.approximation?.attributionAvailable == false)
    let confirmed = try make([event("codex"), event("codex-spark")])
    #expect(confirmed.result.range?.cycleStatus == "confirmed")
    #expect(confirmed.result.approximation?.models.map(\.id) == ["regular-model"])
    let special = try make([event("codex"), event("codex-spark")], selected: confirmed.choices[1].id)
    #expect(special.result.approximation?.models.map(\.id) == ["gpt-spark"])
    #expect(special.cycleEvents?.map(\.id) == ["codex-spark"])
}

@Test func nativeQuotaIdentityAndObservationWhitelist() throws {
    let claims: [String: Any] = ["email": "USER@example.invalid", "https://api.openai.com/auth": ["chatgpt_account_id": "workspace"]]
    let jwt = "synthetic." + (try JSONSerialization.data(withJSONObject: claims)).base64EncodedString() + ".signature"
    let auth = try JSONSerialization.data(withJSONObject: ["tokens": ["access_token": "synthetic-token", "account_id": "WORKSPACE", "id_token": jwt]])
    let identity = try NativeQuotaObservation.identity(auth: auth)
    #expect(identity.accountKey == "sha256:" + NativeQuotaObservation.hash("codex\0user@example.invalid\0workspace\0"))
    let window: [String: Any] = ["limit_window_seconds": 604800, "used_percent": 0, "reset_at": 1790553600]
    let payload: [String: Any] = ["rate_limit": ["secondary_window": window],
          "additional_rate_limits": [["metered_feature": "codex-spark", "rate_limit": ["secondary_window": window]]],
          "email": "must-not-upload@example.invalid", "access_token": "must-not-upload"]
    let provider = try NativeQuotaObservation.provider(payload: JSONSerialization.data(withJSONObject: payload), identity: identity,
                                                        observedAt: Date(timeIntervalSince1970: 1789948800))
    let windows = provider["windows"] as! [[String: Any]]
    #expect(windows.count == 2)
    #expect(windows[0]["remainingPercent"] as? Double == 100)
    #expect(windows[1]["additional"] as? Bool == true)
    var monthlyWindow = window; monthlyWindow["limit_window_seconds"] = 30 * 86400
    let monthly = try NativeQuotaObservation.provider(payload: JSONSerialization.data(withJSONObject:
        ["rate_limit": ["primary_window": monthlyWindow]]), identity: identity, observedAt: Date())
    #expect((monthly["windows"] as? [[String: Any]])?.first?["kind"] as? String == "billing")
    let encoded = String(decoding: try JSONSerialization.data(withJSONObject: provider), as: UTF8.self)
    #expect(!encoded.contains("must-not-upload"))
    #expect(!encoded.contains("synthetic-token"))
    #expect(provider["updatedAt"] as? String == "2026-09-21T00:00:00.000Z")
    #expect(throws: Error.self) {
        try NativeQuotaObservation.provider(payload: Data("{\"rate_limit\":{\"secondary_window\":{\"used_percent\":true}}}".utf8), identity: identity, observedAt: Date())
    }
}

@Test func nativeSettingsReflectOnlyLocalCollectorAvailability() {
    #expect(NativeQuotaObservation.settingsProviders(latest: nil, error: nil).isEmpty)
    #expect(NativeQuotaObservation.settingsProviders(latest: nil, error: "quotaNotConfigured") == [["provider": "codex", "status": "notConfigured"]])
    #expect(NativeQuotaObservation.settingsProviders(latest: [:], error: nil) == [["provider": "codex", "status": "ok"]])
    #expect(NativeQuotaObservation.settingsProviders(latest: [:], error: "unauthorized") == [["provider": "codex", "status": "unauthorized"]])
    #expect(NativeQuotaObservation.settingsProviders(latest: [:], error: "sourceRateLimited").first?["status"] == "sourceRateLimited")
    #expect(NativeQuotaObservation.settingsProviders(latest: [:], error: "quotaUploadFailed").first?["status"] == "unavailable")
}

@Test func nativeQuotaDefaultsToWeeklyAndKeepsExplicitShortWindow() throws {
    let now = ISO8601DateFormatter().date(from: "2026-09-22T00:05:00Z")!
    let windows: [[String: Any]] = [
        ["kind": "session", "windowMinutes": 300, "remainingPercent": 85, "resetsAt": "2026-09-22T03:00:00Z", "limitId": "codex"],
        ["kind": "weekly", "windowMinutes": 10080, "remainingPercent": 40, "resetsAt": "2026-09-28T00:00:00Z", "limitId": "codex"]]
    let stats = try JSONSerialization.data(withJSONObject: ["limits": ["providers": [["provider": "codex", "status": "ok", "updatedAt": "2026-09-22T00:00:00Z", "windows": windows]]]])
    func snapshot(_ id: String? = nil) throws -> ConversionSnapshot {
        try JSONDecoder().decode(ConversionSnapshot.self, from: NativeQuotaConversion.make(stats: stats,
            devices: Data(#"{"devices":[]}"#.utf8), deviceID: "synthetic", hourly: nil, selectedChoiceID: id, now: now))
    }
    let weekly = try snapshot()
    #expect(weekly.choices.first { $0.id == weekly.choiceId }?.kind == "weekly")
    #expect(weekly.result.range?.remaining == 40)
    let short = try snapshot(weekly.choices.first { $0.kind == "session" }?.id)
    #expect(short.result.range?.remaining == 85)
    #expect(try snapshot("removed-window").choiceId == weekly.choiceId)
}

@Test func quotaAllocationPrefersCodexWeightsOverAPIDollars() throws {
    let window: [String: Any] = ["kind": "weekly", "windowMinutes": 10080, "remainingPercent": 40,
                                "resetsAt": "2026-09-28T00:00:00Z", "limitId": "codex"]
    let provider: [String: Any] = ["provider": "codex", "status": "ok", "accountKey": "synthetic-account",
        "sourceDeviceId": "synthetic-device", "updatedAt": "2026-09-22T00:00:00Z", "windows": [window]]
    var device = quotaFixture()
    device["history"] = ["daily": [["date": "2026-09-20",
        "perClient": ["codex": ["tokens": 100, "cost": 10, "quotaWeight": 30]],
        "perModel": ["synthetic-model": ["tokens": 100, "cost": 10, "quotaWeight": 30]]]]]
    let output = try NativeQuotaConversion.make(
        stats: JSONSerialization.data(withJSONObject: ["limits": ["providers": [provider]]]),
        devices: JSONSerialization.data(withJSONObject: ["devices": [device, quotaFixture(id: "peer")]]),
        deviceID: "synthetic-device", hourly: nil,
        now: ISO8601DateFormatter().date(from: "2026-09-22T00:05:00Z")!)
    let decoded = try JSONDecoder().decode(ConversionSnapshot.self, from: output)
    let rows = try #require(decoded.result.approximation?.devices)
    #expect(abs(try #require(rows.first { $0.id == "synthetic-device" }?.quota) - 45) < 0.0001)
    #expect(abs(try #require(rows.first { $0.id == "peer" }?.quota) - 15) < 0.0001)
}
