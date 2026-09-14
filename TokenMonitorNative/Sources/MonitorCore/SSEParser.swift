import Foundation

/// Incremental UTF-8 event framing, independent of TCP chunk boundaries.
public struct SSEParser: Sendable {
    private var bytes = Data()
    private var lines: [String] = []
    private var name = "message"
    private var size = 0
    private var afterCR = false
    private var firstLine = true
    public init() {}
    public mutating func feed(_ data: Data) throws -> [SSEEvent] {
        var result: [SSEEvent] = []
        for byte in data {
            if afterCR { afterCR = false; if byte == 10 { continue } }
            if byte == 10 || byte == 13 {
                guard var line = String(data: bytes, encoding: .utf8) else { throw HubError.incompatible(L10n.text("串流 UTF-8")) }
                if firstLine { if line.hasPrefix("\u{FEFF}") { line.removeFirst() }; firstLine = false }
                bytes.removeAll(keepingCapacity: true)
                if let event = consume(line) { result.append(event) }
                afterCR = byte == 13
            } else {
                bytes.append(byte)
                guard bytes.count + size < 16 * 1024 * 1024 else { throw HubError.incompatible(L10n.text("串流事件过大")) }
            }
        }
        return result
    }
    private mutating func consume(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            defer { lines = []; name = "message"; size = 0 }
            guard !lines.isEmpty else { return nil }
            return SSEEvent(name: name, data: Data(lines.joined(separator: "\n").utf8))
        }
        if line.hasPrefix(":") { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = parts.count == 2 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        if parts[0] == "event" { name = value }
        if parts[0] == "data" { lines.append(value); size += value.utf8.count }
        return nil
    }
}
public struct SSEEvent: Sendable {
    public let name: String
    public let data: Data
    public func stats() throws -> Stats? {
        guard name == "stats" || name == "snapshot" else { return nil }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stats = json["stats"] as? [String: Any] else { throw HubError.incompatible(L10n.text("串流事件")) }
            return try Stats.decode(JSONSerialization.data(withJSONObject: stats))
        } catch let error as HubError { throw error }
        catch { throw HubError.incompatible(L10n.text("串流事件 JSON")) }
    }
}
