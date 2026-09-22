// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenMonitorNative",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "TokenMonitorNative", targets: ["TokenMonitorNative"]), .executable(name: "TokenMonitorBackend", targets: ["TokenMonitorBackend"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "NativeBackendCore"),
        .testTarget(name: "NativeBackendCoreTests", dependencies: ["NativeBackendCore", "MonitorCore", "TokenMonitorNative"]),
        .target(name: "MonitorCore", resources: [.process("Resources")]),
        .executableTarget(name: "TokenMonitorBackend", dependencies: ["NativeBackendCore"]),
        .executableTarget(name: "TokenMonitorNative", dependencies: ["MonitorCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore", "TokenMonitorNative"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
