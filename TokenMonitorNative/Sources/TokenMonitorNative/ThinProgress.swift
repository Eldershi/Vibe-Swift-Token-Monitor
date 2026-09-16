import SwiftUI

struct ThinProgress: View {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint).frame(width: proxy.size.width * fraction)
                    .animation(reduceMotion ? nil : DataMotion.animation, value: fraction)
            }
        }.frame(height: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityValue(value.isFinite ? fraction.formatted(.percent) : "—")
    }
}
