import Foundation
import CryptoKit
import CoreFoundation

/// Restores the legacy Hub's explicitly approximate Codex quota view from
/// recent complete-day model costs. It never claims event-level attribution.
public enum NativeQuotaConversion {
    public static func make(stats: Data, devices: Data, deviceID: String, hourly: Data?,
                            selectedChoiceID: String? = nil, cycleEvents: [[String: Any]] = [],
                            cycleCapability: Bool = false, now: Date = Date()) throws -> Data {
        let stats = try object(stats), registry = try object(devices)
        let deviceRows = registry["devices"] as? [[String: Any]] ?? []
        let providers = (stats["limits"] as? [String: Any])?["providers"] as? [[String: Any]] ?? []
        let codex = providers.first { $0["provider"] as? String == "codex" }
        let accountKey = codex?["accountKey"] as? String ?? ""
        let accountID = accountKey.isEmpty ? nil : digest("codex\n" + String(accountKey.prefix(256)))
        let sourceID = codex?["sourceDeviceId"] as? String
        let windows = codex?["windows"] as? [[String: Any]] ?? []
        let supportedWindows = windows.filter { window in
            guard let kind = window["kind"] as? String,
                  let minutes = number(window["windowMinutes"]) else { return false }
            return ["session", "weekly", "daily"].contains(kind) && minutes > 0
        }
        let choices: [[String: Any]] = supportedWindows.compactMap { window in
            guard let kind = window["kind"] as? String,
                  ["session", "weekly", "daily"].contains(kind),
                  let minutes = number(window["windowMinutes"]), minutes > 0 else { return nil }
            let limitID = window["limitId"] as? String ?? ""
            let id = digest((accountID ?? sourceID ?? "codex") + ":" + kind + ":" + limitID)
            return ["id": id, "title": durationTitle(minutes), "kind": kind,
                    "label": window["label"] as? String ?? "", "limitId": limitID,
                    "additional": window["additional"] as? Bool ?? false,
                    "windowMinutes": minutes, "accountId": accountID as Any? ?? NSNull(),
                    "sourceDeviceId": sourceID as Any? ?? NSNull()]
        }
        let defaultIndex = choices.firstIndex { $0["kind"] as? String == "weekly" && $0["additional"] as? Bool != true && ["", "codex"].contains($0["limitId"] as? String ?? "") } ?? 0
        let selectedIndex = choices.firstIndex { $0["id"] as? String == selectedChoiceID } ?? defaultIndex
        let choice = choices.indices.contains(selectedIndex) ? choices[selectedIndex] : nil
        let selected = supportedWindows.indices.contains(selectedIndex) ? supportedWindows[selectedIndex] : nil
        let matchingEvents = cycleEvents.filter { event in
            guard event["schemaVersion"] as? Int == 1, event["policyVersion"] as? Int == 1,
                  let identity = event["identity"] as? [String: Any],
                  identity["provider"] as? String == "codex",
                  identity["kind"] as? String == selected?["kind"] as? String,
                  identity["limitId"] as? String == selected?["limitId"] as? String,
                  let duration = number(identity["durationMs"]),
                  let minutes = number(selected?["windowMinutes"]), abs(duration - minutes * 60000) < 1 else { return false }
            if let accountID { return identity["accountId"] as? String == accountID }
            return identity["accountId"] is NSNull && identity["deviceScope"] as? String == sourceID
        }.sorted { ($0["recordedAt"] as? String ?? "") < ($1["recordedAt"] as? String ?? "") }
        var range: [String: Any] = [:]
        var approximation = emptyApproximation(reason: "observationUnavailable")
        if let selected, let observed = date(codex?["updatedAt"] as? String),
           let reset = date(selected["resetsAt"] as? String),
           let minutes = number(selected["windowMinutes"]),
           let remaining = number(selected["remainingPercent"]),
           (codex?["status"] as? String) == "ok", codex?["stale"] as? Bool != true,
           minutes > 0, minutes <= 366 * 1_440,
           (0...100).contains(remaining), observed <= now.addingTimeInterval(60),
           now.timeIntervalSince(observed) <= 600, reset > now {
            let confirmed = matchingEvents.last.flatMap { event -> [String: Any]? in
                guard let end = date(event["resetsAt"] as? String),
                      let start = date(event["inferredStartAt"] as? String),
                      let at = date(event["confirmedAt"] as? String),
                      event["derivation"] as? String == "stableDeadlineMinusDuration" else { return nil }
                return abs(end.timeIntervalSince(reset)) <= 2 && abs(end.timeIntervalSince(start) - minutes * 60) < 0.001
                    && at <= observed.addingTimeInterval(60) ? event : nil
            }
            let start = date(confirmed?["inferredStartAt"] as? String) ?? reset.addingTimeInterval(-minutes * 60)
            let usedMatches = number(selected["usedPercent"]).map { abs($0 + remaining - 100) <= 0.01 } ?? true
            if observed >= start && observed < reset && usedMatches {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let used = 100 - remaining
                range = ["start": formatter.string(from: start), "end": formatter.string(from: reset),
                         "observedAt": formatter.string(from: observed),
                         "calculationStart": formatter.string(from: start),
                         "remaining": remaining, "used": used,
                         "cycleStatus": confirmed != nil ? "confirmed" : cycleCapability ? "pending" : "unverified"]
                if let confirmed { range["cycleEventId"] = confirmed["id"]; range["confirmedAt"] = confirmed["confirmedAt"] }
                let limitID = selected["limitId"] as? String ?? ""
                let additional = selected["additional"] as? Bool == true || (!limitID.isEmpty && limitID != "codex")
                let spark = limitID.lowercased().contains("spark")
                if cycleCapability && confirmed == nil {
                    approximation = emptyApproximation(reason: "cycleUnconfirmed")
                } else if additional && !spark {
                    approximation = emptyApproximation(reason: "unsupportedQuotaBucket")
                } else {
                    approximation = estimate(devices: deviceRows, accountKey: accountKey,
                                             start: start, observed: observed, used: used, spark: spark)
                }
            }
        }
        var result: [String: Any] = ["attributionAvailable": false,
            "reasons": ["strictEventsUnavailable"], "mode": "approximate",
            "devices": [], "models": [], "totalWeight": 0, "simulationWeight": 0,
            "unknownTokens": 0, "remainingTokens": NSNull(), "approximation": approximation]
        if !range.isEmpty { result["range"] = range }
        var response: [String: Any] = ["schemaVersion": 1, "deviceId": deviceID,
            "deviceIds": deviceRows.compactMap { $0["deviceId"] as? String },
            "choices": choices, "choiceId": choice?["id"] ?? "", "accountId": accountID as Any? ?? NSNull(),
            "config": ["automaticPrices": false, "approximateEstimates": true],
            "displayMode": approximation["attributionAvailable"] as? Bool == true ? "current" : "recorded",
            "lastSuccessful": NSNull(), "error": NSNull(), "result": result,
            "cycleRecordsAvailable": cycleCapability, "cycleEvents": matchingEvents,
            "pricing": ["error": "nativePriceRefreshUnavailable"], "prices": NSNull()]
        if let hourly, let value = try? JSONSerialization.jsonObject(with: hourly) {
            response["trend"] = ["hourly": value]
        }
        return try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
    }

    private static func estimate(devices: [[String: Any]], accountKey: String,
                                 start: Date, observed: Date, used: Double, spark: Bool) -> [String: Any] {
        let elapsedDays = observed.timeIntervalSince(start) / 86_400
        guard elapsedDays > 0 else { return emptyApproximation(reason: "windowDurationUnknown") }
        var rows: [[String: Any]] = []
        var modelTotals: [String: (tokens: Double, weight: Double)] = [:]
        var missing: [String] = []
        var totalTokens = 0.0, totalWeight = 0.0
        for device in devices {
            guard let id = device["deviceId"] as? String else { continue }
            let providers = (device["limits"] as? [String: Any])?["providers"] as? [[String: Any]] ?? []
            let codex = providers.first { $0["provider"] as? String == "codex" }
            guard !accountKey.isEmpty, codex?["accountKey"] as? String == accountKey,
                  let zoneName = (device["periodWindows"] as? [String: Any])?["timeZone"] as? String,
                  let zone = TimeZone(identifier: zoneName),
                  let updated = date(device["updatedAt"] as? String),
                  let days = (device["history"] as? [String: Any])?["daily"] as? [[String: Any]] else {
                missing.append(id); continue
            }
            let cutoff = min(day(observed, in: zone), day(updated, in: zone))
            let all = days.filter { row in
                guard let key = row["date"] as? String, key < cutoff,
                      let codex = (row["perClient"] as? [String: Any])?["codex"] as? [String: Any],
                      let tokens = number(codex["tokens"]) else { return false }
                return tokens >= 0
            }.sorted { ($0["date"] as? String ?? "") < ($1["date"] as? String ?? "") }
            let startDay = day(start, in: zone)
            let within = all.filter { ($0["date"] as? String ?? "") > startDay }
            let sample = Array((within.isEmpty ? all : within).suffix(7))
            guard !sample.isEmpty else { missing.append(id); continue }
            let factor = elapsedDays / Double(sample.count)
            var deviceTokens = 0.0, deviceWeight = 0.0
            var contributions: [String: (tokens: Double, weight: Double)] = [:]
            var completeSample = true
            for row in sample {
                guard let codex = (row["perClient"] as? [String: Any])?["codex"] as? [String: Any],
                      let codexTokens = number(codex["tokens"]),
                      let codexCost = number(codex["cost"]),
                      let models = row["perModel"] as? [String: [String: Any]] else {
                    completeSample = false; break
                }
                let tokenSum = models.values.reduce(0.0) { $0 + (number($1["tokens"]) ?? 0) }
                let costSum = models.values.reduce(0.0) { $0 + (number($1["cost"]) ?? 0) }
                guard abs(tokenSum - codexTokens) <= 1,
                      abs(costSum - codexCost) <= max(0.001, codexCost * 0.01) else {
                    completeSample = false; break
                }
                for (model, values) in models where model.lowercased().contains("spark") == spark {
                    guard let tokens = number(values["tokens"]), let cost = number(values["cost"]) else { continue }
                    deviceTokens += tokens * factor; deviceWeight += cost * factor
                    var current = contributions[model] ?? (0, 0)
                    current.tokens += tokens * factor; current.weight += cost * factor
                    contributions[model] = current
                }
            }
            guard completeSample, deviceTokens > 0, deviceWeight > 0 else { missing.append(id); continue }
            totalTokens += deviceTokens; totalWeight += deviceWeight
            for (model, value) in contributions {
                var current = modelTotals[model] ?? (0, 0)
                current.tokens += value.tokens; current.weight += value.weight
                modelTotals[model] = current
            }
            rows.append(["id": id, "tokens": deviceTokens, "weight": deviceWeight,
                         "basis": "dailyRateProjection", "sampleFrom": sample.first?["date"] ?? "",
                         "sampleTo": sample.last?["date"] ?? ""])
        }
        guard totalWeight > 0 else { return emptyApproximation(reason: "noPricedUsage", missing: missing) }
        for index in rows.indices {
            let weight = rows[index]["weight"] as! Double
            rows[index]["share"] = weight / totalWeight
            rows[index]["quota"] = used * weight / totalWeight
        }
        let models = modelTotals.keys.filter { modelTotals[$0]!.tokens > 0 }.sorted().map { name -> [String: Any] in
            let value = modelTotals[name]!
            return ["id": name, "tokens": value.tokens, "weight": value.weight,
                    "share": value.weight / totalWeight, "quota": used * value.weight / totalWeight]
        }
        return ["attributionAvailable": true, "remainingTokens": NSNull(),
                "tokens": totalTokens, "totalWeight": totalWeight, "excludedTokens": 0,
                "assumedTierTokens": 0, "assumedAccountTokens": 0, "devices": rows,
                "models": models, "missingDevices": missing, "reasons": ["dailyRateProjection"]]
    }

    private static func emptyApproximation(reason: String, missing: [String] = []) -> [String: Any] {
        ["attributionAvailable": false, "remainingTokens": NSNull(), "tokens": 0,
         "totalWeight": 0, "excludedTokens": 0, "assumedTierTokens": 0,
         "assumedAccountTokens": 0, "devices": [], "models": [],
         "missingDevices": missing, "reasons": [reason]]
    }
    private static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConversionError.invalidData
        }
        return value
    }
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }
    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    private static func day(_ value: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }
    private static func durationTitle(_ minutes: Double) -> String {
        if minutes.truncatingRemainder(dividingBy: 1_440) == 0 { return "\(Int(minutes / 1_440))d" }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(minutes / 60))h" }
        return "\(Int(minutes))m"
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum ConversionError: Error { case invalidData }
