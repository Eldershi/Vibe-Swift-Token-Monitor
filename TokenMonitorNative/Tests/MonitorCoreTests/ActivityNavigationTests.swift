import XCTest
import SwiftUI
@testable import MonitorCore
@testable import TokenMonitorNative

@MainActor final class ActivityNavigationTests: XCTestCase {
    func testLegacyPagesAndBothHomeEntrancesResolveToActivity() {
        XCTAssertEqual(Page.restored("趋势"), .activity)
        XCTAssertEqual(Page.restored("活动"), .activity)
        XCTAssertEqual(Page.restored("rate"), .overview)
        XCTAssertEqual(HomeSection.activity.page, .activity)
        XCTAssertEqual(HomeSection.trends.page, .activity)
        XCTAssertEqual(Page.allCases.filter { $0 == .activity }.count, 1)
        XCTAssertEqual(Page.allCases.count, 6)
        XCTAssertEqual(HomeSection.activity.symbol, "calendar")
        XCTAssertEqual(HomeSection.trends.symbol, "chart.xyaxis.line")
        XCTAssertEqual(Page.activity.symbol, "waveform.path.ecg.text.clipboard")
        XCTAssertNotNil(NSImage(systemSymbolName: Page.activity.symbol, accessibilityDescription: nil))
    }

    func testIndependentChartVisibilityAndOrderPersist() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = PreferencesFile(url: directory.appendingPathComponent("settings.json"))
        for hidden: Set<HomeSection> in [[], [.activity], [.trends], [.activity, .trends]] {
            for reversed in [false, true] {
                var preferences = Preferences()
                preferences.hiddenHomeSections = hidden
                if reversed { preferences.moveHomeSection(.trends, to: .activity) }
                try file.save(preferences)
                let restored = try file.load()
                XCTAssertEqual(restored, preferences)
                XCTAssertEqual(restored.visibleHomeSections.contains(.activity), !hidden.contains(.activity))
                XCTAssertEqual(restored.visibleHomeSections.contains(.trends), !hidden.contains(.trends))
                XCTAssertEqual(restored.homeSections.firstIndex(of: .trends)! < restored.homeSections.firstIndex(of: .activity)!, reversed)
            }
        }
    }

    func testNativeAgentCheckmarksFollowActionsReopenAndRestoration() throws {
        _ = NSApplication.shared
        let store = AppStore(ephemeral: true)
        store.stats = try Stats.decode(Data(#"{"updatedAt":"2026-09-15T00:00:00Z","periods":{"today":{"totalTokens":30,"clients":{"codex":10,"claude":20}},"month":{"totalTokens":30},"allTime":{"totalTokens":30}},"devices":[]}"#.utf8))
        store.preferences.period = .today
        store.preferences.tool = ""
        for (tool, expected): (String, Double) in [("", 30), ("codex", 10), ("claude", 20), ("", 30)] {
            let index = ([""] + store.tools).firstIndex(of: tool)!
            let menu = FloatingMenuItem.makeMenu(store.toolMenuItems)
            menu.performActionForItem(at: index)
            XCTAssertEqual(store.preferences.tool, tool)
            XCTAssertEqual(store.selectedTokens, expected)
            let reopened = FloatingMenuItem.makeMenu(store.toolMenuItems)
            XCTAssertEqual(reopened.items.filter { $0.state == .on }.count, 1)
            XCTAssertEqual(reopened.items[index].state, .on)
            XCTAssertTrue(reopened.items.allSatisfy { $0.image == nil })
            let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(store.preferences.snapshot))
            let other = AppStore(ephemeral: true)
            other.stats = store.stats; other.preferences.tool = restored.tool
            other.reconcileToolSelection()
            XCTAssertEqual(FloatingMenuItem.makeMenu(other.toolMenuItems).items[index].state, .on)
        }
    }

    func testShieldClearsBothChartsAndLeavesNativeClicksUntouched() throws {
        for geometry: ChartHoverGeometry in [.heatmap, .bars(ceiling: 100, slot: 7, height: 136)] {
            for nested in [false, true] {
                let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
                let window = NSWindow(contentRect: root.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = root
                let chart = HistoryNativeScroll(content: AnyView(Color.clear))
                chart.frame = NSRect(x: 0, y: 100, width: 320, height: 160)
                if nested {
                    let page = NSScrollView(frame: root.bounds)
                    let document = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 800))
                    page.documentView = document; root.addSubview(page); document.addSubview(chart)
                    page.contentView.scroll(to: .zero)
                } else { root.addSubview(chart) }
                chart.documentSize = NSSize(width: 320, height: 160)
                chart.configureHeatmapHover(enabled: true, points: [TrendPoint(date: Date(), tokens: 100, cost: nil)], geometry: geometry)
                window.orderFront(nil); chart.layout()
                defer { chart.heatmapOverlay?.clear(); window.orderOut(nil) }
                let overlay = try XCTUnwrap(chart.heatmapOverlay)
                let point = NSPoint(x: 19, y: 10)
                overlay.show(at: point)
                XCTAssertEqual(overlay.selectedIndex, 0)
                let location = root.convert(point, from: overlay)
                let button = NSButton(frame: NSRect(x: location.x - 22, y: location.y - 22, width: 44, height: 44))
                root.addSubview(button)
                let shield = ChartInteractionShieldView(frame: button.bounds)
                button.addSubview(shield)
                overlay.show(at: point)
                XCTAssertNil(overlay.selectedIndex)
                XCTAssertNil(overlay.tooltip?.superview)
                XCTAssertNil(shield.hitTest(.zero))
                XCTAssertTrue(root.hitTest(location) === button)
                shield.isHidden = true
                overlay.show(at: point)
                XCTAssertEqual(overlay.selectedIndex, 0)
                shield.isHidden = false
                button.setFrameOrigin(NSPoint(x: 200, y: 0))
                XCTAssertFalse(ChartInteractionShield.blocks(point, from: overlay), "local=\(shield.convert(point, from: overlay)) frame=\(button.frame) visible=\(shield.visibleRect)")
                overlay.show(at: point)
                XCTAssertEqual(overlay.selectedIndex, 0)
            }
        }
    }
    func testNativeTitlebarControlBlocksOnlyItsOwnBounds() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let content = try XCTUnwrap(window.contentView)
        let frame = try XCTUnwrap(content.superview)
        let button = NSButton(frame: NSRect(x: 180, y: 340, width: 100, height: 30))
        frame.addSubview(button)
        let inside = content.convert(NSPoint(x: 230, y: 355), from: frame)
        let outside = content.convert(NSPoint(x: 150, y: 355), from: frame)
        XCTAssertTrue(ChartInteractionShield.blocks(inside, from: content))
        XCTAssertFalse(ChartInteractionShield.blocks(outside, from: content))
        button.isHidden = true
        XCTAssertFalse(ChartInteractionShield.blocks(inside, from: content))
        let scroll = PageNativeScroll(content: AnyView(Color.clear))
        XCTAssertFalse(scroll.automaticallyAdjustsContentInsets)
    }

}
