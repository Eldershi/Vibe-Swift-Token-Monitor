import Foundation

public struct NativeUsageEvent: Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let input: Int64
    public let cached: Int64
    public let output: Int64
    public var total: Int64 { input + output }
}

/// Reads Codex rollout files directly. Per-message `last_token_usage` is the
/// primary increment; cumulative totals guard against replay and stale events.
public enum CodexScanner {
    private struct Counters: Equatable {
        var input: Int64 = 0
        var cached: Int64 = 0
        var output: Int64 = 0
        init(_ value: [String: Any]?) {
            func number(_ key: String) -> Int64 {
                guard let value = value?[key] as? NSNumber else { return 0 }
                return max(0, value.int64Value)
            }
            input = number("input_tokens")
            cached = min(input, number("cached_input_tokens"))
            output = number("output_tokens")
        }
        func difference(from previous: Self) -> Self? {
            guard input >= previous.input, cached >= previous.cached, output >= previous.output else { return nil }
            return Self(input: input - previous.input, cached: cached - previous.cached,
                        output: output - previous.output)
        }
        var total: Int64 { input + output }
        func looksStale(previous: Self, last: Self) -> Bool {
            total * 100 >= previous.total * 98 || total + last.total * 2 >= previous.total
        }
        func within(_ baseline: Self) -> Bool {
            input <= baseline.input && cached <= baseline.cached && output <= baseline.output
        }
        private init(input: Int64, cached: Int64, output: Int64) {
            self.input = input; self.cached = cached; self.output = output
        }
    }

    public static func scan(root: URL) throws -> [NativeUsageEvent] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var events: [NativeUsageEvent] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let info = try url.resourceValues(forKeys: Set(keys))
            guard info.isRegularFile == true, info.isSymbolicLink != true else { continue }
            events.append(contentsOf: try scanFile(url))
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    public static func scanFile(_ url: URL) throws -> [NativeUsageEvent] {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var model = "unknown"
        var previous: Counters?
        var forked = false
        var childTurnStarted = false
        var inherited: Counters?
        var events: [NativeUsageEvent] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        let tokenNeedle = Data("token_count".utf8)
        let contextNeedle = Data("turn_context".utf8)
        let metaNeedle = Data("session_meta".utf8)
        func consume(_ line: Data) {
            guard line.range(of: tokenNeedle) != nil || line.range(of: contextNeedle) != nil || line.range(of: metaNeedle) != nil,
                  let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = record["payload"] as? [String: Any] else { return }
            switch record["type"] as? String {
            case "session_meta": forked = payload["forked_from_id"] != nil
            case "turn_context":
                if let value = payload["model"] as? String, !value.isEmpty { model = value }
                if forked { childTurnStarted = true }
            case "event_msg":
                guard payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let stamp = record["timestamp"] as? String,
                      let timestamp = formatter.date(from: stamp) ?? fallback.date(from: stamp) else { return }
                let current = (info["total_token_usage"] as? [String: Any]).map(Counters.init)
                let last = (info["last_token_usage"] as? [String: Any]).map(Counters.init)
                if forked && !childTurnStarted {
                    if let current { inherited = current; previous = current }
                    return
                }
                if let current, let inherited, current.within(inherited) { return }
                inherited = nil
                let delta: Counters
                switch (current, last) {
                case (let current?, let last?):
                    if let previous = previous, current == previous ||
                        (current.difference(from: previous) == nil && current.looksStale(previous: previous, last: last)) { return }
                    delta = last
                    previous = current
                case (let current?, nil):
                    if let prior = previous {
                        guard let difference = current.difference(from: prior) else { previous = current; return }
                        delta = difference
                    } else { delta = current }
                    previous = current
                case (nil, let last?): delta = last
                default: return
                }
                if delta.total > 0 {
                    events.append(NativeUsageEvent(timestamp: timestamp, model: model,
                                                   input: delta.input, cached: delta.cached, output: delta.output))
                }
            default: return
            }
        }
        var partial = Data()
        while let chunk = try file.read(upToCount: 64 * 1024), !chunk.isEmpty {
            var start = chunk.startIndex
            for index in chunk.indices where chunk[index] == 10 {
                if partial.count < 8 * 1024 * 1024 {
                    partial.append(chunk[start..<index])
                    consume(partial)
                }
                partial.removeAll(keepingCapacity: true)
                start = chunk.index(after: index)
            }
            if start < chunk.endIndex { partial.append(chunk[start...]) }
            if partial.count > 8 * 1024 * 1024 { partial.removeAll(keepingCapacity: true) }
        }
        if !partial.isEmpty { consume(partial) }
        return events
    }
}
