import SwiftUI
import AppKit
import MonitorCore

struct FloatingMenuItem {
    let title: String
    let symbol: String?
    var isSelected: Bool = false
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
            .background(ChartInteractionShield())
    }
    private func openMenu() {
        guard let anchor else { return }
        let menu = FloatingMenuItem.makeMenu(items)
        // Place the full menu above the control with a visible gap.
        menu.update()
        let menuHeight = menu.size.height
        let gap: CGFloat = 10
        let y = anchor.isFlipped ? -(menuHeight + gap) : anchor.bounds.height + menuHeight + gap
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: anchor)
    }
}

extension FloatingMenuItem {
    @MainActor static func makeMenu(_ items: [FloatingMenuItem]) -> NSMenu {
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
            item.state = option.isSelected ? .on : .off
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        return menu
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

/// Marks each existing 44 pt button hit area, independently of its glass decoration.
/// The marker never consumes events or changes the button's click handling.
struct ChartInteractionShield: NSViewRepresentable {
    func makeNSView(context: Context) -> ChartInteractionShieldView { ChartInteractionShieldView() }
    func updateNSView(_ view: ChartInteractionShieldView, context: Context) {}
    @MainActor static func blocks(_ point: NSPoint, from source: NSView) -> Bool {
        guard let content = source.window?.contentView, let root = content.superview else { return false }
        func visit(_ view: NSView) -> Bool {
            guard !view.isHiddenOrHasHiddenAncestor else { return false }
            // Native titlebar controls float above full-size scrolling content.
            if view is NSControl, !view.isDescendant(of: content) {
                let local = view.convert(point, from: source)
                if view.bounds.contains(local) && view.visibleRect.contains(local) { return true }
            }
            if let shield = view as? ChartInteractionShieldView {
                let local = shield.convert(point, from: source)
                if shield.bounds.contains(local) && shield.visibleRect.contains(local) { return true }
            }
            return view.subviews.contains(where: visit)
        }
        return visit(root)
    }
}
final class ChartInteractionShieldView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor extension AppStore {
    var toolMenuItems: [FloatingMenuItem] {
        ([""] + tools).map { tool in
            FloatingMenuItem(title: tool.isEmpty ? L10n.text("全部工具") : tool == "codex" ? "Codex" : tool == "claude" ? "Claude" : tool,
                             symbol: nil, isSelected: preferences.tool == tool) {
                self.preferences.tool = tool
                self.savePreferences()
            }
        }
    }
}
