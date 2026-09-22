import Foundation
import Testing
@testable import NativeBackendCore

@Test func cumulativeCountersModelSwitchAndFork() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let main = directory.appendingPathComponent("main.jsonl")
    let fork = directory.appendingPathComponent("fork.jsonl")
    func row(_ stamp: String, _ type: String, _ payload: [String: Any]) -> String {
        let value: [String: Any] = ["timestamp": stamp, "type": type, "payload": payload]
        return String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
    }
    func count(_ input: Int, _ cached: Int, _ output: Int) -> [String: Any] {
        ["type": "token_count", "info": ["total_token_usage": ["input_tokens": input, "cached_input_tokens": cached, "output_tokens": output]]]
    }
    let t = "2026-09-22T01:00:00.000Z"
    try [row(t, "turn_context", ["model": "a"]), row(t, "event_msg", count(100, 20, 10)),
         row(t, "event_msg", count(100, 20, 10)), row(t, "turn_context", ["model": "b"]),
         row(t, "event_msg", count(125, 25, 15))].joined(separator: "\n").write(to: main, atomically: true, encoding: .utf8)
    try [row(t, "session_meta", ["forked_from_id": "main"]), row(t, "event_msg", count(125, 25, 15)),
         row(t, "turn_context", ["model": "b"]),
         row(t, "event_msg", count(135, 30, 20))].joined(separator: "\n").write(to: fork, atomically: true, encoding: .utf8)
    let events = try CodexScanner.scan(root: directory)
    #expect(events.count == 3)
    #expect(events.map(\.total).sorted() == [15, 30, 110])
    #expect(events.first(where: { $0.model == "b" })?.cached == 5)
    #expect(try CodexScanner.scan(root: directory).count == 3)
}
