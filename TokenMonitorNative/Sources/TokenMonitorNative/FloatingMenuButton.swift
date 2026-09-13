import SwiftUI
import AppKit

struct FloatingMenuItem {
    let title: String
    let symbol: String?
    let action: () -> Void
}
struct FloatingMenuButton<Content: View>: View {
    let items: [FloatingMenuItem]
    @ViewBuilder let label: () -> Content
    @State private var anchor: NSView?
    var body: some View {
        Button(action: openMenu, label: label)
            .buttonStyle(.plain)
            .background(MenuAnchor(view: $anchor))
    }
    private func openMenu() {
        guard let anchor else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for option in items {
            let target = MenuAction(option.action)
            let item = NSMenuItem(title: option.title, action: #selector(MenuAction.invoke), keyEquivalent: "")
            if let symbol = option.symbol {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: option.title)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular))
                if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            }
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        // Place the full menu above the control with a visible gap, not its first row against the button.
        menu.update()
        let menuHeight = menu.size.height
        let gap: CGFloat = 10
        let y = anchor.isFlipped ? -(menuHeight + gap) : anchor.bounds.height + menuHeight + gap
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: anchor)
    }
}
private final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
private struct MenuAnchor: NSViewRepresentable {
    @Binding var view: NSView?
    func makeNSView(context: Context) -> NSView {
        let anchor = NSView()
        DispatchQueue.main.async { view = anchor }
        return anchor
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
