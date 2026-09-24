import Foundation
import CoreFoundation

/// Projects confirmed cycle boundaries and raw official observations. A shade is
/// always the last observed percentage, never a claimed final cycle total.
public enum NativeQuotaCycleTimeline {
    public static func make(events: [[String: Any]], observations: [[String: Any]],
                            devices: [[String: Any]], accountID: String?, accountKey: String,
                            sourceID: String?, selected: [String: Any]?,
                            currentResult: [String: Any], now: Date) -> [[String: Any]] {
        guard let selected, let kind = selected["kind"] as? String,
              let limitID = selected["limitId"] as? String,
              let minutes = number(selected["windowMinutes"]) else { return [] }
        let eligible = events.compactMap { event -> (event: [String: Any], start: Date, end: Date)? in
            guard event["schemaVersion"] as? Int == 1, event["policyVersion"] as? Int == 1,
                  event["derivation"] as? String == "stableDeadlineMinusDuration",
                  let id = event["identity"] as? [String: Any],
                  id["provider"] as? String == "codex", id["kind"] as? String == kind,
                  id["limitId"] as? String == limitID,
                  abs((number(id["durationMs"]) ?? -1) - minutes * 60_000) < 1,
                  (accountID != nil ? id["accountId"] as? String == accountID :
                    id["accountId"] is NSNull && id["deviceScope"] as? String == sourceID),
                  let start = date(event["inferredStartAt"] as? String),
                  let end = date(event["resetsAt"] as? String),
                  start < end, start <= now.addingTimeInterval(60) else { return nil }
            return (event, start, end)
        }.sorted { $0.start < $1.start }
        let latest = Array(eligible.suffix(200))
        return latest.enumerated().map { index, item in
            let nextStart = index + 1 < latest.count ? latest[index + 1].start : item.end
            let end = min(item.end, nextStart)
            let match = observations.compactMap { observation -> (at: Date, received: Date, used: Double)? in
                guard observation["schemaVersion"] as? Int == 1,
                      observation["provider"] as? String == "codex",
                      observation["status"] as? String == "ok",
                      (accountID != nil ? observation["accountId"] as? String == accountID :
                        observation["accountId"] is NSNull && observation["sourceDeviceId"] as? String == sourceID),
                      let at = date(observation["sourceObservedAt"] as? String),
                      let received = date(observation["receivedAt"] as? String),
                      at >= item.start, at < end, at <= now.addingTimeInterval(60),
                      received >= at.addingTimeInterval(-60),
                      let windows = observation["windows"] as? [[String: Any]] else { return nil }
                for window in windows {
                    guard window["kind"] as? String == kind,
                          window["limitId"] as? String == limitID,
                          abs((number(window["windowMinutes"]) ?? -1) - minutes) < 0.001,
                          let deadline = date(window["resetsAt"] as? String),
                          abs(deadline.timeIntervalSince(item.end)) <= 2,
                          let used = number(window["usedPercent"]) ?? number(window["remainingPercent"]).map({ 100 - $0 }),
                          (0...100).contains(used) else { continue }
                    return (at, received, used)
                }
                return nil
            }.max { a, b in a.at == b.at ? a.received < b.received : a.at < b.at }
            let isCurrent = abs(item.end.timeIntervalSince(date(selected["resetsAt"] as? String) ?? .distantPast)) <= 2
            let currentRange = currentResult["range"] as? [String: Any]
            let currentUsed = isCurrent ? number(currentRange?["used"]) : nil
            let used = currentUsed ?? match?.used
            let observed = currentUsed != nil ? date(currentRange?["observedAt"] as? String) : match?.at
            let approximation: [String: Any]
            if isCurrent, let value = currentResult["approximation"] as? [String: Any] {
                approximation = value
            } else if let used, let observed {
                approximation = estimateHistorical(devices: devices, accountKey: accountKey,
                                                    start: item.start, observed: observed,
                                                    used: used, spark: limitID.lowercased().contains("spark"),
                                                    supported: limitID == "codex" || limitID.lowercased().contains("spark"))
            } else { approximation = empty(reason: "observationUnavailable") }
            var range: [String: Any] = ["start": iso(item.start), "end": iso(end),
                                        "cycleStatus": "confirmed"]
            if let used { range["used"] = used; range["remaining"] = 100 - used }
            if let observed { range["observedAt"] = iso(observed) }
            let result: [String: Any] = ["attributionAvailable": false, "reasons": ["strictEventsUnavailable"],
                                         "mode": "approximate", "devices": [], "models": [],
                                         "totalWeight": 0, "simulationWeight": 0, "unknownTokens": 0,
                                         "remainingTokens": NSNull(), "range": range,
                                         "approximation": approximation]
            return ["id": item.event["id"] ?? "", "kind": item.event["kind"] ?? "cycleChanged",
                    "start": iso(item.start), "end": iso(end),
                    "observedAt": observed.map(iso) as Any? ?? NSNull(),
                    "usedPercent": used as Any? ?? NSNull(), "result": result]
        }
    }

    private static func estimateHistorical(devices: [[String: Any]], accountKey: String,
                                           start: Date, observed: Date, used: Double,
                                           spark: Bool, supported: Bool) -> [String: Any] {
        guard supported else { return empty(reason: "unsupportedQuotaBucket") }
        var rows: [[String: Any]] = []
        var models: [String: (tokens: Double, weight: Double)] = [:]
        var missing: [String] = []
        var totalTokens = 0.0, totalWeight = 0.0
        for device in devices {
            guard let id = device["deviceId"] as? String else { continue }
            let providers = (device["limits"] as? [String: Any])?["providers"] as? [[String: Any]] ?? []
            guard !accountKey.isEmpty,
                  providers.contains(where: { $0["provider"] as? String == "codex" && $0["accountKey"] as? String == accountKey }),
                  let zoneName = (device["periodWindows"] as? [String: Any])?["timeZone"] as? String,
                  let zone = TimeZone(identifier: zoneName),
                  let days = (device["history"] as? [String: Any])?["daily"] as? [[String: Any]] else {
                missing.append(id); continue
            }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            var formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
            var tokenTotal = 0.0, weightTotal = 0.0
            var deviceModels: [String: (tokens: Double, weight: Double)] = [:]
            var first: String?, last: String?
            for day in days {
                guard let key = day["date"] as? String, let dayStart = formatter.date(from: key),
                      let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
                      dayStart >= start, dayEnd <= observed,
                      let codex = (day["perClient"] as? [String: Any])?["codex"] as? [String: Any],
                      let dayTokens = number(codex["tokens"]), let dayCost = number(codex["quotaWeight"] ?? codex["cost"]),
                      let perModel = day["perModel"] as? [String: [String: Any]] else { continue }
                let modelTokens = perModel.values.reduce(0.0) { $0 + (number($1["tokens"]) ?? 0) }
                let modelCost = perModel.values.reduce(0.0) { $0 + (number($1["quotaWeight"] ?? $1["cost"]) ?? 0) }
                guard abs(modelTokens - dayTokens) <= 1,
                      abs(modelCost - dayCost) <= max(0.001, dayCost * 0.01) else { continue }
                for (name, value) in perModel where name.lowercased().contains("spark") == spark {
                    guard let tokens = number(value["tokens"]), let cost = number(value["quotaWeight"] ?? value["cost"]) else { continue }
                    tokenTotal += tokens; weightTotal += cost
                    var row = deviceModels[name] ?? (0, 0)
                    row.tokens += tokens; row.weight += cost; deviceModels[name] = row
                }
                if first == nil { first = key }; last = key
            }
            guard weightTotal > 0 else { missing.append(id); continue }
            totalTokens += tokenTotal; totalWeight += weightTotal
            for (name, value) in deviceModels {
                var row = models[name] ?? (0, 0)
                row.tokens += value.tokens; row.weight += value.weight; models[name] = row
            }
            rows.append(["id": id, "tokens": tokenTotal, "weight": weightTotal,
                         "basis": "completeDaysInCycle", "sampleFrom": first ?? "", "sampleTo": last ?? ""])
        }
        guard totalWeight > 0 else { return empty(reason: "noPricedUsage", missing: missing) }
        for index in rows.indices {
            let weight = rows[index]["weight"] as! Double
            rows[index]["share"] = weight / totalWeight; rows[index]["quota"] = used * weight / totalWeight
        }
        let modelRows: [[String: Any]] = models.keys.sorted().compactMap { name in
            guard let value = models[name], value.weight > 0 else { return nil }
            return ["id": name, "tokens": value.tokens, "weight": value.weight,
                    "share": value.weight / totalWeight, "quota": used * value.weight / totalWeight]
        }
        return ["attributionAvailable": true, "remainingTokens": NSNull(), "tokens": totalTokens,
                "totalWeight": totalWeight, "excludedTokens": 0, "assumedTierTokens": 0,
                "assumedAccountTokens": 0, "devices": rows, "models": modelRows,
                "missingDevices": missing, "reasons": ["completeDaysInCycle"]]
    }
    private static func empty(reason: String, missing: [String] = []) -> [String: Any] {
        ["attributionAvailable": false, "remainingTokens": NSNull(), "tokens": 0, "totalWeight": 0,
         "excludedTokens": 0, "assumedTierTokens": 0, "assumedAccountTokens": 0,
         "devices": [], "models": [], "missingDevices": missing, "reasons": [reason]]
    }
    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue >= 0 else { return nil }
        return value.doubleValue
    }
    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
