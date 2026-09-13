// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenMonitorNative",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "TokenMonitorNative", targets: ["TokenMonitorNative"])],
    targets: [
        .target(name: "MonitorCore"),
        .executableTarget(name: "TokenMonitorNative", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore", "TokenMonitorNative"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
