// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenMonitorNative",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "TokenMonitorNative", targets: ["TokenMonitorNative"]), .executable(name: "TokenMonitorBackend", targets: ["TokenMonitorBackend"])],
    targets: [
        .target(name: "MonitorCore", resources: [.process("Resources")]),
        .executableTarget(name: "TokenMonitorBackend"),
        .executableTarget(name: "TokenMonitorNative", dependencies: ["MonitorCore"], resources: [.process("Resources")]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore", "TokenMonitorNative"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
