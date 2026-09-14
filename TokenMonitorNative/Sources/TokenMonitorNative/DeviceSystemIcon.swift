import AppKit
import SwiftUI

enum DeviceOperatingSystem {
    case apple, windows, linux, other
    init(_ name: String?) {
        let name = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch name {
        case "macos", "mac os", "mac os x", "darwin", "os x": self = .apple
        case "win32", "windows", "windows_nt": self = .windows
        case "linux": self = .linux
        default: self = name.hasPrefix("windows ") ? .windows : .other
        }
    }
}

struct DeviceSystemIcon: View {
    let osName: String?
    private var icon: Image {
        switch DeviceOperatingSystem(osName) {
        case .apple:
            if let image = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "applelogo", accessibilityDescription: nil) { return Image(nsImage: image) }
            return Image("DeviceMac", bundle: InterfaceSymbols.resourceBundle)
        case .windows: return Image("DeviceWindows", bundle: InterfaceSymbols.resourceBundle)
        case .linux: return Image("DeviceLinux", bundle: InterfaceSymbols.resourceBundle)
        case .other: return Image(systemName: "macbook")
        }
    }
    var body: some View {
        icon.resizable().renderingMode(.template).scaledToFit()
            .frame(width: 13.5, height: 13.5).foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}
