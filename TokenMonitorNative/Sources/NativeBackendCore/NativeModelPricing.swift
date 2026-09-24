import Foundation

/// Versioned, offline estimate using official prices verified on 2026-09-24.
/// API dollars and Codex credits intentionally use different Fast multipliers.
public enum NativeModelPricing {
    public static let version = "openai-2026-09-24"
    public static let apiSource = "https://developers.openai.com/api/docs/pricing"
    public static let creditSource = "https://learn.chatgpt.com/docs/pricing"
    public struct Estimate: Equatable {
        public let dollars: Double
        public let credits: Double
    }
    // Input, cached input and output per million tokens. Unknown aliases remain unknown.
    private static let rates: [String: (Double, Double, Double)] = [
        "gpt-6-astra": (10, 1, 50), "gpt-6-sol": (2, 0.2, 10), "gpt-6-luna": (0.1, 0.01, 0.5)
    ]
    public static func estimate(_ event: NativeUsageEvent) -> Estimate? {
        guard let rate = rates[event.model], event.input >= 0, event.cached >= 0,
              event.cached <= event.input, event.output >= 0 else { return nil }
        let tier = event.serviceTier?.lowercased() ?? "default"
        guard ["default", "standard", "auto", "fast", "priority"].contains(tier) else { return nil }
        let fast = tier == "fast" || tier == "priority"
        // Missing tier is an explicit Standard estimate; it is never called a bill.
        let input = Double(event.input - event.cached), cached = Double(event.cached), output = Double(event.output)
        let longContext = (event.requestInput ?? event.input) > 272_000
        let inputCost = input * rate.0 + cached * rate.1
        let outputCost = output * rate.2
        let dollars = (inputCost * (longContext ? 2 : 1) + outputCost * (longContext ? 1.5 : 1))
            * (fast ? 2 : 1) / 1_000_000
        // Published Codex credit rates are 25x the Standard short-context API rates.
        // The credit table does not publish the API long-context surcharge.
        let credits = (inputCost + outputCost) * 25 * (fast ? 2.5 : 1) / 1_000_000
        return Estimate(dollars: dollars, credits: credits)
    }

    /// Price only a model whose complete token count matches the source record.
    /// This keeps missing logs and a different device/account from becoming a partial price.
    static func totals(_ events: [NativeUsageEvent], expected: [String: Double]) -> [String: Estimate] {
        let grouped = Dictionary(grouping: events, by: \.model)
        var result: [String: Estimate] = [:]
        for (model, tokens) in expected {
            guard let rows = grouped[model], Double(rows.reduce(Int64(0)) { $0 + $1.total }) == tokens else { continue }
            let priced = rows.compactMap(estimate)
            guard priced.count == rows.count else { continue }
            result[model] = Estimate(dollars: priced.reduce(0) { $0 + $1.dollars }, credits: priced.reduce(0) { $0 + $1.credits })
        }
        return result
    }

    /// In-memory overlay only: does not change Hub token totals or persist/backfill costs.
    public static func enrich(device: [String: Any], events: [NativeUsageEvent]) -> [String: Any] {
        guard let stamp = device["updatedAt"] as? String, let cutoff = date(stamp),
              let zoneID = (device["periodWindows"] as? [String: Any])?["timeZone"] as? String,
              let zone = TimeZone(identifier: zoneID) else { return device }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let available = events.filter { $0.timestamp <= cutoff }
        let day = calendar.startOfDay(for: cutoff), month = calendar.dateInterval(of: .month, for: cutoff)!.start
        var result = device, periods = device["periods"] as? [String: [String: Any]] ?? [:]
        for (key, start) in [("today", day), ("month", month), ("allTime", Date.distantPast)] {
            guard var row = periods[key], let models = (row["clientModels"] as? [String: [String: Double]])?["codex"] else { continue }
            let prices = totals(available.filter { $0.timestamp >= start }, expected: models)
            var clientCosts = row["clientModelCosts"] as? [String: [String: Double]] ?? [:]
            var costs = clientCosts["codex"] ?? [:]
            for (model, price) in prices { costs[model] = price.dollars }
            clientCosts["codex"] = costs; row["clientModelCosts"] = clientCosts
            periods[key] = row
        }
        result["periods"] = periods
        let format = DateFormatter(); format.calendar = calendar; format.timeZone = zone
        format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "yyyy-MM-dd"
        let days = Dictionary(grouping: available) { format.string(from: $0.timestamp) }
        var history = device["history"] as? [String: Any] ?? [:]
        history["daily"] = (history["daily"] as? [[String: Any]] ?? []).map { original in
            guard let key = original["date"] as? String, let events = days[key],
                  var models = original["perModel"] as? [String: [String: Any]],
                  var clients = original["perClient"] as? [String: [String: Any]],
                  var codex = clients["codex"], let tokens = codex["tokens"] as? Double else { return original }
            let expected = models.compactMapValues { $0["tokens"] as? Double }
            // Mixed-agent model history is not attributable to Codex without per-agent evidence.
            guard expected.count == models.count, expected.values.reduce(0, +) == tokens else { return original }
            let prices = totals(events, expected: expected)
            // Quota allocation requires the entire day to have a consistent weight basis.
            guard prices.count == models.count, !prices.isEmpty else { return original }
            for (model, price) in prices {
                models[model]?["cost"] = price.dollars
                models[model]?["quotaWeight"] = price.credits / 25
            }
            codex["cost"] = prices.values.reduce(0) { $0 + $1.dollars }
            codex["quotaWeight"] = prices.values.reduce(0) { $0 + $1.credits / 25 }
            clients["codex"] = codex
            var row = original; row["perModel"] = models; row["perClient"] = clients
            return row
        }
        result["history"] = history
        return result
    }

    public static func enrich(stats: Data, devices: Data, deviceID: String, events: [NativeUsageEvent]) throws -> (stats: Data, devices: Data) {
        guard var root = try JSONSerialization.jsonObject(with: stats) as? [String: Any],
              var deviceRoot = try JSONSerialization.jsonObject(with: devices) as? [String: Any],
              var rows = deviceRoot["devices"] as? [[String: Any]] else { return (stats, devices) }
        rows = rows.map { $0["deviceId"] as? String == deviceID ? enrich(device: $0, events: events) : $0 }
        deviceRoot["devices"] = rows
        // /api/devices may be newer than /api/stats. Price the aggregate from
        // the devices included in that exact stats snapshot, never a later fetch.
        let periodDevices = (root["devices"] as? [[String: Any]] ?? []).map {
            $0["deviceId"] as? String == deviceID ? enrich(device: $0, events: events) : $0
        }
        root["devices"] = periodDevices
        let snapshotTime = (root["updatedAt"] as? String).flatMap(date) ?? Date()
        var periods = root["periods"] as? [String: [String: Any]] ?? [:]
        for (period, original) in periods {
            guard let models = (original["clientModels"] as? [String: [String: Double]])?["codex"] else { continue }
            var costs = ((original["clientModelCosts"] as? [String: [String: Double]])?["codex"]) ?? [:]
            for (model, expectedTokens) in models {
                var tokens = 0.0, cost = 0.0, complete = true
                for device in periodDevices {
                    guard !periodExpired(device, period: period, at: snapshotTime) else { continue }
                    guard let row = (device["periods"] as? [String: [String: Any]])?[period],
                          let value = (row["clientModels"] as? [String: [String: Double]])?["codex"]?[model], value > 0 else { continue }
                    tokens += value
                    if let amount = (row["clientModelCosts"] as? [String: [String: Double]])?["codex"]?[model] { cost += amount }
                    else { complete = false }
                }
                if complete && tokens == expectedTokens && tokens > 0 { costs[model] = cost }
            }
            var updated = original, clientCosts = original["clientModelCosts"] as? [String: [String: Double]] ?? [:]
            clientCosts["codex"] = costs; updated["clientModelCosts"] = clientCosts; periods[period] = updated
        }
        root["periods"] = periods
        return (try JSONSerialization.data(withJSONObject: root), try JSONSerialization.data(withJSONObject: deviceRoot))
    }
    private static func periodExpired(_ device: [String: Any], period: String, at now: Date) -> Bool {
        guard period != "allTime" else { return false }
        if let raw = ((device["periodWindows"] as? [String: Any])?[period] as? [String: Any])?["endsAt"] as? String,
           let end = date(raw) { return now >= end }
        guard let raw = device["updatedAt"] as? String, let updated = date(raw) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return !calendar.isDate(updated, equalTo: now, toGranularity: period == "today" ? .day : .month)
    }
    private static func date(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
