import XCTest
import SwiftUI
@testable import TokenMonitorNative

@MainActor private final class AppearanceRecorder {
    var scheme: ColorScheme?
}
private struct AppearanceProbe: View {
    @Environment(\.colorScheme) private var scheme
    let recorder: AppearanceRecorder
    var body: some View {
        Text("Appearance probe").foregroundStyle(.primary)
            .onAppear { recorder.scheme = scheme }
            .onChange(of: scheme) { recorder.scheme = scheme }
    }
}
@MainActor final class AppearancePropagationTests: XCTestCase {
    func testPageBridgeUpdatesAppearanceWithoutDataRefresh() async {
        let recorder = AppearanceRecorder()
        let chartRecorder = AppearanceRecorder()
        let outer = NSHostingView(rootView: PageScrollView {
            VStack {
                AppearanceProbe(recorder: recorder)
                HistoryScrollView(width: 320, height: 104, resetKey: "test", points: [], tint: nil) {
                    AppearanceProbe(recorder: chartRecorder)
                }.frame(height: 104)
            }
        })
        outer.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = outer
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let oldAppearance = NSApp.appearance
        defer { NSApp.appearance = oldAppearance }
        for (appearance, expected) in [(NSAppearance.Name.aqua, ColorScheme.light), (.darkAqua, .dark), (.aqua, .light)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for _ in 0..<10 {
                outer.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(20))
                if recorder.scheme == expected && chartRecorder.scheme == expected { break }
            }
            XCTAssertEqual(recorder.scheme, expected, "Must update without usage data or a timer changing")
            XCTAssertEqual(chartRecorder.scheme, expected, "Nested charts must update in the same appearance transition")
        }
    }
    func testHoverEmphasisUsesCustomAndSystemAccent() {
        let hover = HeatmapHoverView(frame: .zero)
        XCTAssertEqual(hover.emphasisColor, NSColor.controlAccentColor)
        hover.accent = NSColor.systemPurple
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            hover.appearance = NSAppearance(named: appearance)
            XCTAssertEqual(hover.emphasisColor, NSColor.systemPurple)
        }
        hover.accent = nil
        XCTAssertEqual(hover.emphasisColor, NSColor.controlAccentColor)
    }

    func testNativeAppearanceCallbackImmediatelyInvalidatesStaticText() {
        let host = LiveAppearanceHostingView(content: AnyView(Text("Static label").foregroundStyle(.primary)))
        for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua, .accessibilityHighContrastDarkAqua] {
            host.appearance = NSAppearance(named: appearance)
            XCTAssertEqual(host.appliedAppearance, host.effectiveAppearance.name)
            if appearance == .aqua || appearance == .darkAqua { XCTAssertEqual(host.appliedAppearance, appearance) }
        }
    }

}
