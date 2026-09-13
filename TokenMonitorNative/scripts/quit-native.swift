import AppKit
import Foundation
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.tokenmonitor.native")
for app in apps { app.terminate() }
let until = Date().addingTimeInterval(10)
while apps.contains(where: { !$0.isTerminated }) && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
if apps.contains(where: { !$0.isTerminated }) { fputs("Please quit Token Monitor Native and retry.\n", stderr); exit(1) }
