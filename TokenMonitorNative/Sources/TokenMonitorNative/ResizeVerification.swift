import AppKit
import SwiftUI
import MonitorCore
import os

/// Uses the shipping panel, toolbar actions, glass navigation and snapshot acceptance.
/// CPU/layout measurements exclude pacing and are not claims about presented frame rate.
enum ResizeVerification {
    @MainActor static func run(store: AppStore) async {
        guard !store.tools.isEmpty, let history = store.history, !history.daily.isEmpty, let snapshot = store.stats else {
            fputs("INTERACTION FAIL: usable fixture reports and history required\n", stderr); exit(1)
        }
        let log = OSSignposter(subsystem: "local.tokenmonitor.native", category: "InteractionVerification")
        if ProcessInfo.processInfo.arguments.contains("--benchmark-profile") { try? await Task.sleep(for: .seconds(10)) }
        store.start()
        PanelController.shared.show()
        let window = PanelController.shared.verificationWindow
        let maximum = max(1000, window.screen?.visibleFrame.width ?? 1264)
        print("FULL PANEL: \(history.daily.count) daily records; width 320…\(Int(maximum)); toolbar, glass, ticker, snapshot acceptance enabled")
        window.setContentSize(NSSize(width: 600, height: 900))
        try? await Task.sleep(for: .seconds(3))
        func milliseconds(_ start: ContinuousClock.Instant) -> Double {
            let value = start.duration(to: .now).components
            return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
        }
        var resizing: [Double] = [], switching: [Double] = [], syncing: [Double] = [], lateness: [Double] = []
        for index in 0..<120 {
            let step = index < 60 ? index : 119 - index
            let width = 320 + Double(step) / 59 * (maximum - 320)
            let interval = log.beginInterval("Resize")
            let start = ContinuousClock.now
            window.setContentSize(NSSize(width: width, height: 900))
            window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            resizing.append(milliseconds(start)); log.endInterval("Resize", interval)
            // Allow SwiftUI's deferred transaction to run; collect this separately from CPU work.
            let pacingStart = ContinuousClock.now
            try? await Task.sleep(for: .milliseconds(16))
            lateness.append(max(0, milliseconds(pacingStart) - 16))
            if index.isMultiple(of: 20) {
                let interval = log.beginInterval("Snapshot")
                let start = ContinuousClock.now
                store.accept(snapshot)
                window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                syncing.append(milliseconds(start)); log.endInterval("Snapshot", interval)
            }
        }
        for width in [320.0, 600, 1000, maximum] {
            window.setContentSize(NSSize(width: width, height: 900))
            for index in 0..<15 {
                let interval = log.beginInterval("Period")
                let start = ContinuousClock.now
                PanelController.shared.verificationSelectPeriod(index % 3)
                window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                switching.append(milliseconds(start)); log.endInterval("Period", interval)
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        for (name, values) in [("resize", resizing), ("period", switching), ("snapshot", syncing)] {
            let sorted = values.sorted()
            print(String(format: "FULL PANEL %@ synchronous main work (pacing excluded): n=%d median=%.2f ms p95=%.2f ms max=%.2f ms", name, sorted.count, sorted[sorted.count / 2], sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], sorted.last!))
        }
        let late = lateness.sorted()
        print(String(format: "FULL PANEL resize scheduling delay beyond requested 16 ms pacing: median=%.2f ms p95=%.2f ms max=%.2f ms (not FPS)", late[60], late[114], late[119]))
        if ProcessInfo.processInfo.arguments.contains("--benchmark-profile") { try? await Task.sleep(for: .seconds(5)) }
        fflush(stdout)
        NSApp.terminate(nil)
    }
}
