import XCTest
@testable import MonitorCore
@testable import TokenMonitorNative

@MainActor final class HistoryCacheTests: XCTestCase {
    func testHistoryCacheTracksSnapshotToolAndCalendarDay() throws {
        let store = AppStore(ephemeral: true)
        let date = DateCodec.parse("2026-09-13T12:00:00Z")!
        store.now = date
        store.preferences.tool = "codex"
        let key = DateCodec.key(date, monthly: false)
        func history(_ tokens: Int) throws -> History {
            try History.decode(Data("{\"daily\":[{\"date\":\"\(key)\",\"tokens\":\(tokens),\"perClient\":{\"codex\":{\"tokens\":3}}}],\"monthly\":[]}".utf8))
        }
        store.history = try history(10)
        let initial = store.historyPoints()
        XCTAssertEqual(initial.last?.tokens, 3)
        store.now = date.addingTimeInterval(1)
        XCTAssertEqual(store.historyPoints(), initial)
        store.preferences.tool = ""
        XCTAssertEqual(store.historyPoints().last?.tokens, 10)
        store.history = try history(20)
        XCTAssertEqual(store.historyPoints().last?.tokens, 20)
        XCTAssertEqual(store.historyPoints(activity: true).last?.tokens, 20)
        XCTAssertEqual(store.historyPoints(monthly: true).count, 12)
        store.now = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        XCTAssertNil(store.historyPoints().last?.tokens)
        XCTAssertEqual(store.historyPoints().dropLast().last?.tokens, 20)
        store.history = nil
        XCTAssertTrue(store.historyPoints().isEmpty)
    }
}
