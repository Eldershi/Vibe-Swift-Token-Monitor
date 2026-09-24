import XCTest
import SwiftUI
import Observation
@testable import MonitorCore
@testable import TokenMonitorNative

@MainActor @Observable private final class SummaryHarnessModel {
    var left: Distribution
    var right: Distribution
    var quota = true
    init(_ left: Distribution, right: Distribution = Distribution([])) {
        self.left = left; self.right = right
    }
}

private struct SummaryHarness: View {
    let model: SummaryHarnessModel
    var pair = false
    var body: some View {
        VStack(spacing: 0) {
            if pair {
                EqualHeightCards(spacing: 8) {
                    card(model.left, title: "Devices")
                    card(model.right, title: "Models")
                }.animation(DataMotion.summaryAnimation, value: model.left)
                    .animation(DataMotion.summaryAnimation, value: model.right)
            } else {
                QuotaSummaryRows(distribution: model.left, quota: model.quota, tint: .blue)
                    .padding(10)
            }
            Spacer(minLength: 0)
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
    private func card(_ distribution: Distribution, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            QuotaSummaryRows(distribution: distribution, quota: model.quota, tint: .blue)
        }.padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.25), in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor final class QuotaSummaryAnimationTests: XCTestCase {
    private func distribution(_ rows: [(String, Double)]) -> Distribution {
        Distribution(rows.map { .init(id: $0.0, name: $0.0, value: $0.1) }, limit: 4)
    }
    private func host(_ model: SummaryHarnessModel, pair: Bool = false) async throws -> (NSWindow, NSHostingView<SummaryHarness>) {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Visible motion is intentionally disabled by the system preference")
        let host = NSHostingView(rootView: SummaryHarness(model: model, pair: pair))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: pair ? 280 : 136, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host; window.orderFront(nil)
        await settle(host, milliseconds: 100)
        return (window, host)
    }
    private func settle(_ host: NSView, milliseconds: Int) async {
        for _ in 0..<max(1, milliseconds / 10) {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    private func capture(_ host: NSView, _ name: String) throws -> NSBitmapImageRep {
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let output = ProcessInfo.processInfo.environment["TOKEN_MONITOR_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        }
        return bitmap
    }
    private func blueRows(_ bitmap: NSBitmapImageRep) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      c.blueComponent > 0.55, c.redComponent < 0.35,
                      c.blueComponent - c.greenComponent > 0.15 else { continue }
                result[y, default: 0] += 1
            }
        }
        return result
    }

    func testMetricChangeKeepsVisibleIntermediateBarLengths() async throws {
        let model = SummaryHarnessModel(distribution([("Alpha", 10), ("Beta", 5)]))
        let (window, view) = try await host(model)
        defer { window.orderOut(nil) }
        let before = blueRows(try capture(view, "summary-metric-before")).values.max() ?? 0
        model.left = distribution([("Alpha", 800_000), ("Beta", 200_000)])
        model.quota = false
        await settle(view, milliseconds: 150)
        let middle = blueRows(try capture(view, "summary-metric-middle")).values.max() ?? 0
        await settle(view, milliseconds: 450)
        let after = blueRows(try capture(view, "summary-metric-after")).values.max() ?? 0
        XCTAssertGreaterThan(middle, before + 3, "The bar must move from its previous length")
        XCTAssertLessThan(middle, after - 3, "Metric switching must retain an intermediate frame, not replace the list")
    }

    func testReorderingMovesRetainedRowsAndRapidChangesReachLatestState() async throws {
        let initial = distribution([("Alpha", 90), ("Beta", 10)])
        let model = SummaryHarnessModel(initial)
        let (window, view) = try await host(model)
        defer { window.orderOut(nil) }
        let before = blueRows(try capture(view, "summary-order-before"))
        let originalBands = Set(before.keys)
        model.left = distribution([("Alpha", 30), ("Beta", 70)])
        var moved = false
        for index in 0..<4 {
            await settle(view, milliseconds: 70)
            let rows = blueRows(try capture(view, "summary-order-\(index)"))
            if rows.keys.contains(where: { y in !originalBands.contains(where: { abs($0 - y) < 3 }) }) { moved = true }
        }
        XCTAssertTrue(moved, "Existing rows must pass through intermediate vertical positions")
        model.left = distribution([("Gamma", 80), ("Beta", 20)])
        await settle(view, milliseconds: 70)
        model.left = initial
        await settle(view, milliseconds: 650)
        let after = blueRows(try capture(view, "summary-order-restored"))
        XCTAssertEqual(Set(after.keys), originalBands)
        XCTAssertEqual(after.values.max(), before.values.max(), "A rapid change must not finish an obsolete transition")
    }

    func testCardsStayEqualHeightDuringRowInsertionAndRemoval() async throws {
        let model = SummaryHarnessModel(distribution([("A", 30), ("B", 20), ("C", 10)]),
                                        right: distribution([("D", 40), ("E", 30), ("F", 20), ("G", 10)]))
        let (window, view) = try await host(model, pair: true)
        defer { window.orderOut(nil) }
        func bottoms(_ bitmap: NSBitmapImageRep) -> (Int, Int) {
            func bottom(at fraction: Double) -> Int {
                let x = Int(Double(bitmap.pixelsWide) * fraction)
                return (0..<bitmap.pixelsHigh).last { y in
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                    return max(color.redComponent, color.greenComponent, color.blueComponent) > 0.12
                } ?? 0
            }
            return (bottom(at: 0.24), bottom(at: 0.76))
        }
        let start = bottoms(try capture(view, "summary-height-before"))
        XCTAssertEqual(start.0, start.1, accuracy: 1)
        model.left = distribution([("A", 70), ("B", 30)])
        model.right = distribution([("D", 100)])
        for index in 0..<8 {
            await settle(view, milliseconds: 60)
            let b = bottoms(try capture(view, "summary-height-\(index)"))
            XCTAssertEqual(b.0, b.1, accuracy: 1, "Both backgrounds must share the same animated height")
        }
        let end = bottoms(try capture(view, "summary-height-after"))
        XCTAssertLessThan(end.0, start.0 - 20, "Fewer rows must shrink both cards")
    }
}
