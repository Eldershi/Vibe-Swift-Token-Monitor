import Foundation

/// Shared native localization for SwiftUI, AppKit, and model-generated status text.
/// Language selection belongs to macOS, including its per-application override.
public enum L10n {
    static let resourceBundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("TokenMonitorNative_MonitorCore.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    public static func text(_ key: String, _ arguments: String...) -> String {
        let format = resourceBundle.localizedString(forKey: key, value: nil, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
