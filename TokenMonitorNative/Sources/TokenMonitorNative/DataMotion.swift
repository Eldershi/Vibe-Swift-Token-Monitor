import SwiftUI

enum DataMotion {
    static let duration = 0.28
    private static let control1X = 0.45
    private static let control2X = 0.55
    static let animation = Animation.timingCurve(control1X, 0, control2X, 1, duration: duration)

    /// Evaluate the same cubic Bézier used by SwiftUI so native timer-driven
    /// charts and SwiftUI views keep the same timing rather than only the same duration.
    static func progress(_ raw: Double) -> Double {
        let x = min(1, max(0, raw))
        if x == 0 || x == 1 { return x }
        var lower = 0.0, upper = 1.0
        for _ in 0..<14 {
            let parameter = (lower + upper) / 2
            let inverse = 1 - parameter
            let candidate = 3 * inverse * inverse * parameter * control1X
                + 3 * inverse * parameter * parameter * control2X
                + parameter * parameter * parameter
            if candidate < x { lower = parameter } else { upper = parameter }
        }
        let parameter = (lower + upper) / 2
        return parameter * parameter * (3 - 2 * parameter)
    }
}
