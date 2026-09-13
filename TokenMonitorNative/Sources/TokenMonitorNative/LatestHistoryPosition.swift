import SwiftUI

/// Let the scroll view adjust its anchor as dimensions change, without a geometry/state loop.
/// Once the user starts browsing, incoming snapshots must not pull them away from history.
struct LatestHistoryPosition: ViewModifier {
    let resetKey: String
    @State private var followsLatest = true

    func body(content: Content) -> some View {
        content
            .defaultScrollAnchor(.trailing, for: .initialOffset)
            .defaultScrollAnchor(followsLatest ? .trailing : nil, for: .sizeChanges)
            .defaultScrollAnchor(.trailing, for: .alignment)
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { followsLatest = false }
            }
            .onAppear { followsLatest = true }
            .onChange(of: resetKey) { followsLatest = true }
            .id(resetKey)
    }
}
