import Foundation
import CryptoKit

public struct NativeSnapshot {
    public let stats: Data
    public let history: Data
    public let hourly: Data
    public let deviceRecord: Data

    public func conversion(deviceID: String, local: Bool) throws -> Data {
        let result: [String: Any] = ["attributionAvailable": false, "reasons": ["nativeConversionPending"],
            "devices": [], "models": [], "totalWeight": 0, "simulationWeight": 0,
            "unknownTokens": 0, "remainingTokens": NSNull()]
        let trend: [String: Any] = ["hourly": local ? try JSONSerialization.jsonObject(with: hourly) : NSNull()]
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "deviceId": deviceID,
            "choices": [], "choiceId": "", "result": result, "trend": trend])
    }

    public static func make(events: [NativeUsageEvent], deviceID: String, now: Date = Date(),
                            hostname: String = ProcessInfo.processInfo.hostName) throws -> NativeSnapshot {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let startToday = calendar.startOfDay(for: now)
        let startMonth = calendar.dateInterval(of: .month, for: now)?.start ?? startToday
        let periods: [String: [NativeUsageEvent]] = [
            "today": events.filter { $0.timestamp >= startToday && $0.timestamp <= now },
            "month": events.filter { $0.timestamp >= startMonth && $0.timestamp <= now },
            "allTime": events.filter { $0.timestamp <= now },
        ]
        func usage(_ rows: [NativeUsageEvent]) -> [String: Any] {
            let total = rows.reduce(Int64(0)) { $0 + $1.total }
            let cached = rows.reduce(Int64(0)) { $0 + $1.cached }
            let output = rows.reduce(Int64(0)) { $0 + $1.output }
            var models: [String: Int64] = [:]
            for row in rows { models[row.model, default: 0] += row.total }
            return ["totalTokens": total, "cacheReadTokens": cached, "outputTokens": output,
                    "clients": ["codex": total], "models": models,
                    "clientModels": ["codex": models],
                    "clientCacheReads": ["codex": cached], "clientOutputs": ["codex": output],
                    "capabilities": ["tokenComponents": true]]
        }
        let periodValues = periods.mapValues(usage)
        let updated = iso.string(from: now)
        let dayKey = DateFormatter(); dayKey.calendar = calendar; dayKey.timeZone = calendar.timeZone
        dayKey.locale = Locale(identifier: "en_US_POSIX"); dayKey.dateFormat = "yyyy-MM-dd"
        let monthKey = DateFormatter(); monthKey.calendar = calendar; monthKey.timeZone = calendar.timeZone
        monthKey.locale = Locale(identifier: "en_US_POSIX"); monthKey.dateFormat = "yyyy-MM"
        var device: [String: Any] = ["deviceId": deviceID, "hostname": hostname,
            "osName": "macOS", "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "agentVersion": "0.7.1", "updatedAt": updated,
            "agentRuntime": "swift-native", "platform": "darwin", "historyAvailable": true,
            "trackedClients": ["codex"], "clientStatus": ["codex": "healthy"],
            "periods": periodValues,
            "periodWindows": ["timeZone": calendar.timeZone.identifier,
                "today": ["key": dayKey.string(from: now), "endsAt": iso.string(from: calendar.date(byAdding: .day, value: 1, to: startToday)!)],
                "month": ["key": monthKey.string(from: now), "endsAt": iso.string(from: calendar.date(byAdding: .month, value: 1, to: startMonth)!)]],
        ]
        func rows(monthly: Bool) -> [[String: Any]] {
            var grouped: [String: [NativeUsageEvent]] = [:]
            let format = DateFormatter()
            format.calendar = calendar; format.timeZone = calendar.timeZone
            format.locale = Locale(identifier: "en_US_POSIX")
            format.dateFormat = monthly ? "yyyy-MM" : "yyyy-MM-dd"
            for event in events { grouped[format.string(from: event.timestamp), default: []].append(event) }
            return grouped.keys.sorted().map { key in
                let value = usage(grouped[key]!)
                let total = value["totalTokens"] as! Int64
                let cached = value["cacheReadTokens"] as! Int64
                let output = value["outputTokens"] as! Int64
                let models = value["models"] as! [String: Int64]
                return [monthly ? "month" : "date": key, "tokens": total,
                        "cacheReadTokens": cached, "outputTokens": output,
                        "perClient": ["codex": ["tokens": total, "cacheReadTokens": cached, "outputTokens": output]],
                        "perModel": models.mapValues { ["tokens": $0] }] as [String: Any]
            }
        }
        let history: [String: Any] = ["daily": rows(monthly: false), "monthly": rows(monthly: true)]
        device["history"] = history
        let historyData = try JSONSerialization.data(withJSONObject: history, options: [.sortedKeys])
        let historyRevision = SHA256.hash(data: historyData).map { String(format: "%02x", $0) }.joined()
        let stats: [String: Any] = ["updatedAt": updated, "periods": periodValues,
            "devices": [device], "staleAfterMs": 300_000,
            "historyRevision": historyRevision, "deviceHistoryRevision": historyRevision]
        let startHour = calendar.dateInterval(of: .hour, for: now)!.start
        let rangeStart = startHour.addingTimeInterval(-23 * 3600)
        let rangeEnd = startHour.addingTimeInterval(3600)
        var hourly = Array<Int64?>(repeating: nil, count: 24)
        for event in events where event.timestamp >= rangeStart && event.timestamp < rangeEnd && event.timestamp <= now.addingTimeInterval(60) {
            let index = Int(event.timestamp.timeIntervalSince(rangeStart) / 3600)
            guard (0..<24).contains(index) else { continue }
            hourly[index] = (hourly[index] ?? 0) + event.total
        }
        let day = DateFormatter(); day.calendar = calendar; day.timeZone = calendar.timeZone
        day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyy-MM-dd"
        let hourlyJSON: [String: Any] = ["version": 2, "mode": "rolling24", "date": day.string(from: now),
            "timeZone": calendar.timeZone.identifier, "rangeStart": iso.string(from: rangeStart),
            "rangeEnd": iso.string(from: rangeEnd),
            "points": hourly.enumerated().map { index, tokens in
                let start = rangeStart.addingTimeInterval(Double(index) * 3600)
                return ["hour": calendar.component(.hour, from: start), "start": iso.string(from: start),
                        "tokens": tokens as Any? ?? NSNull()] as [String: Any]
            }]
        return try NativeSnapshot(stats: JSONSerialization.data(withJSONObject: stats),
                                  history: historyData,
                                  hourly: JSONSerialization.data(withJSONObject: hourlyJSON),
                                  deviceRecord: JSONSerialization.data(withJSONObject: device, options: [.sortedKeys]))
    }
}
