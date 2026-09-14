import AppKit
import SwiftUI

/// Native appearance changes invalidate hosted text even when the data and the
/// enclosing representable do not change (for example while another app is active).
@MainActor final class LiveAppearanceHostingView: NSHostingView<AnyView> {
    private var content: AnyView
    private(set) var appliedAppearance: NSAppearance.Name?
    init(content: AnyView) {
        self.content = content
        super.init(rootView: content)
        updateAppearance(force: true)
    }
    @MainActor required init(rootView: AnyView) {
        content = rootView
        super.init(rootView: rootView)
        updateAppearance(force: true)
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }
    func setContent(_ content: AnyView) {
        self.content = content
        updateAppearance(force: true)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance(force: false)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance(force: false)
    }
    private func updateAppearance(force: Bool) {
        let supported: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
        let name = supported.contains(effectiveAppearance.name) ? effectiveAppearance.name : (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua)
        guard force || name != appliedAppearance else { return }
        appliedAppearance = name
        let dark = name == .darkAqua || name == .accessibilityHighContrastDarkAqua
        rootView = AnyView(content
            .environment(\.colorScheme, dark ? .dark : .light))
        needsDisplay = true
    }
}
