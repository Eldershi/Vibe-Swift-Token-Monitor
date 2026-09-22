import Foundation

/// A durable absolute Hub snapshot. The first observation is anchored to the
/// existing device's last update, so old local history is never uploaded twice.
public struct HubHandoff {
    public let address: String
    public let deviceID: String
    public let establishedAt: String
    public private(set) var pendingUpload: Bool
    public var hostname: String { output["hostname"] as? String ?? "" }
    private var output: [String: Any]
    private var seen: [String: Any]

    public init(address: String, deviceID: String, remote: Data, localAtRemoteUpdate: Data,
                establishedAt: String = ISO8601DateFormatter().string(from: Date())) throws {
        let remote = try Self.object(remote), local = try Self.object(localAtRemoteUpdate)
        guard remote["deviceId"] as? String == deviceID, local["deviceId"] as? String == deviceID else {
            throw HandoffError.deviceMismatch
        }
        self.address = address; self.deviceID = deviceID; self.establishedAt = establishedAt
        output = remote; seen = local; pendingUpload = false
    }

    public init(saved: Data) throws {
        let value = try Self.object(saved)
        guard value["version"] as? Int == 1,
              let address = value["address"] as? String, let deviceID = value["deviceId"] as? String,
              let establishedAt = value["establishedAt"] as? String,
              let output = value["output"] as? [String: Any], let seen = value["seen"] as? [String: Any],
              output["deviceId"] as? String == deviceID, seen["deviceId"] as? String == deviceID else {
            throw HandoffError.invalidState
        }
        self.address = address; self.deviceID = deviceID; self.establishedAt = establishedAt
        self.output = output; self.seen = seen; pendingUpload = value["pendingUpload"] as? Bool == true
    }

    public func saved() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "address": address, "deviceId": deviceID,
            "establishedAt": establishedAt, "pendingUpload": pendingUpload, "output": output, "seen": seen], options: [.sortedKeys])
    }

    public func upload() throws -> Data {
        var value = output
        // A usage-only writer must not create stale quota observations on retries.
        value.removeValue(forKey: "limits")
        value.removeValue(forKey: "receivedAt")
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    public mutating func advance(localData: Data) throws -> Bool {
        let local = try Self.object(localData)
        guard local["deviceId"] as? String == deviceID else { throw HandoffError.deviceMismatch }
        let old = try upload()
        var outputPeriods = output["periods"] as? [String: Any] ?? [:]
        var seenPeriods = seen["periods"] as? [String: Any] ?? [:]
        let localPeriods = local["periods"] as? [String: Any] ?? [:]
        let oldWindows = output["periodWindows"] as? [String: Any] ?? [:]
        let newWindows = local["periodWindows"] as? [String: Any] ?? [:]
        for period in ["today", "month", "allTime"] {
            guard let current = localPeriods[period] as? [String: Any] else { throw HandoffError.invalidState }
            let oldKey = (oldWindows[period] as? [String: Any])?["key"] as? String
            let newKey = (newWindows[period] as? [String: Any])?["key"] as? String
            if period != "allTime" && oldKey != newKey {
                outputPeriods[period] = current; seenPeriods[period] = current
            } else {
                let result = Self.advanceCounters(output: outputPeriods[period] as? [String: Any] ?? [:],
                                                  seen: seenPeriods[period] as? [String: Any] ?? [:], current: current)
                outputPeriods[period] = result.output; seenPeriods[period] = result.seen
            }
            var row = outputPeriods[period] as? [String: Any] ?? [:]
            row["sessions"] = [String: Any](); row["projects"] = [String: Any]()
            outputPeriods[period] = row
        }
        output["periods"] = outputPeriods; seen["periods"] = seenPeriods
        let history = local["history"] as? [String: Any] ?? [:]
        var oldHistory = output["history"] as? [String: Any] ?? [:]
        var seenHistory = seen["history"] as? [String: Any] ?? [:]
        for (field, key) in [("daily", "date"), ("monthly", "month")] {
            let result = Self.advanceRows(output: oldHistory[field] as? [[String: Any]] ?? [],
                                          seen: seenHistory[field] as? [[String: Any]] ?? [],
                                          current: history[field] as? [[String: Any]] ?? [], key: key)
            oldHistory[field] = result.output; seenHistory[field] = result.seen
        }
        oldHistory.removeValue(forKey: "summary")
        output["history"] = oldHistory; seen["history"] = seenHistory
        for key in ["periodWindows", "updatedAt", "hostname", "osName", "osVersion", "agentVersion",
                    "agentRuntime", "platform", "trackedClients", "clientStatus", "historyAvailable"] {
            if let value = local[key] { output[key] = value }
        }
        output["syncUploadIntervalMs"] = 20_000
        seen["periodWindows"] = newWindows
        let changed = try upload() != old
        if changed { pendingUpload = true }
        return changed
    }

    public mutating func acknowledged() { pendingUpload = false }

    private static let counters: Set<String> = ["totalTokens", "costUsd", "cacheReadTokens", "cacheWriteTokens",
        "outputTokens", "unclassifiedTokens", "timedTokens", "timedOutputTokens", "timedDurationMs",
        "tokens", "cost", "messages", "activeTimeMs"]
    private static let maps: Set<String> = ["clients", "clientCosts", "clientCacheReads", "clientCacheWrites",
        "clientOutputs", "clientUnclassifiedTokens", "models", "modelCosts", "modelCacheReads",
        "modelCacheWrites", "modelOutputs", "modelUnclassifiedTokens", "clientModels", "clientModelCosts"]

    private static func advanceCounters(output: [String: Any], seen: [String: Any], current: [String: Any],
                                        numericMap: Bool = false) -> (output: [String: Any], seen: [String: Any]) {
        var next = output, high = seen
        for (key, value) in current {
            if let number = value as? NSNumber, numericMap || counters.contains(key) {
                let previous = (seen[key] as? NSNumber)?.doubleValue ?? 0
                let latest = max(previous, number.doubleValue)
                next[key] = ((output[key] as? NSNumber)?.doubleValue ?? 0) + latest - previous
                high[key] = latest
            } else if let child = value as? [String: Any] {
                let isMap = numericMap || maps.contains(key) || key == "perClient" || key == "perModel"
                // Unknown containers are metadata, except named client/model rows.
                guard isMap else { continue }
                let result = advanceCounters(output: output[key] as? [String: Any] ?? [:],
                                             seen: seen[key] as? [String: Any] ?? [:], current: child, numericMap: isMap)
                next[key] = result.output; high[key] = result.seen
            }
        }
        return (next, high)
    }

    private static func advanceRows(output: [[String: Any]], seen: [[String: Any]], current: [[String: Any]],
                                    key: String) -> (output: [[String: Any]], seen: [[String: Any]]) {
        var rows = Dictionary(output.compactMap { row -> (String, [String: Any])? in
            guard let id = row[key] as? String else { return nil }; return (id, row)
        }, uniquingKeysWith: { _, last in last })
        var previous = Dictionary(seen.compactMap { row -> (String, [String: Any])? in
            guard let id = row[key] as? String else { return nil }; return (id, row)
        }, uniquingKeysWith: { _, last in last })
        for row in current {
            guard let id = row[key] as? String else { continue }
            let result = advanceCounters(output: rows[id] ?? [key: id], seen: previous[id] ?? [key: id], current: row)
            rows[id] = result.output; previous[id] = result.seen
        }
        return (rows.keys.sorted().compactMap { rows[$0] }, previous.keys.sorted().compactMap { previous[$0] })
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HandoffError.invalidState }
        return value
    }
}

public enum HandoffError: Error { case invalidState, deviceMismatch }
