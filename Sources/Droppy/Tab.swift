import AppKit

@MainActor
final class Tab {
    private var tree: SplitNode<TerminalView>
    private(set) var focusedView: TerminalView
    private var zoomedView: TerminalView?
    private var isShown = false
    let container = SplitContainerView()

    init(root: TerminalView) {
        tree = .leaf(root)
        focusedView = root
        container.onRatioDrag = { [weak self] path, ratio, available in
            self?.setRatio(ratio, at: path, available: available)
        }
        refresh()
    }

    var views: [TerminalView] { tree.leaves }
    var contentView: NSView { container }

    var userTitle: String?

    var title: String {
        if let userTitle { return userTitle }
        return focusedView.title.isEmpty ? "Terminal" : focusedView.title
    }

    func contains(_ view: TerminalView) -> Bool {
        tree.contains(view)
    }

    func setShown(_ shown: Bool) {
        isShown = shown
        applyVisibility()
    }

    func split(_ target: TerminalView, direction: SplitDirection, adding view: TerminalView, equalizing: Bool = false) {
        tree = tree.inserting(view, beside: target, direction: direction)
        if equalizing { tree = tree.equalized() }
        zoomedView = nil
        focusedView = view
        refresh()
    }

    // Returns true when the tab has no views left and must be closed.
    func remove(_ view: TerminalView, equalizing: Bool = false) -> Bool {
        guard let remaining = tree.removing(view) else { return true }
        if focusedView === view {
            focusedView = tree.sibling(of: view) ?? remaining.leaves[0]
        }
        if zoomedView === view { zoomedView = nil }
        tree = equalizing ? remaining.equalized() : remaining
        refresh()
        return false
    }

    func focus(_ view: TerminalView) {
        guard tree.contains(view), focusedView !== view || zoomedView != nil else { return }
        focusedView = view
        if zoomedView !== view { zoomedView = nil }
        refresh()
    }

    func focusSplit(_ target: SplitFocusTarget) {
        let layout = tree.layout(in: container.bounds)
        guard let next = tree.adjacent(to: focusedView, target, in: layout), next !== focusedView else { return }
        zoomedView = nil
        focusedView = next
        refresh()
    }

    func resizeSplit(_ direction: SplitDirection, amount: CGFloat) {
        let result = tree.resizing(focusedView, direction: direction, amount: amount, in: container.bounds)
        guard result.handled else { return }
        tree = result.node
        container.update(tree: tree, focused: focusedView, zoomed: zoomedView)
    }

    func equalizeSplits() {
        tree = tree.equalized()
        container.update(tree: tree, focused: focusedView, zoomed: zoomedView)
    }

    func toggleZoom() {
        guard tree.leaves.count > 1 else { return }
        zoomedView = zoomedView == nil ? focusedView : nil
        refresh()
    }

    private func setRatio(_ ratio: CGFloat, at path: [Bool], available: CGFloat) {
        tree = tree.settingRatio(SplitNode<TerminalView>.clampedRatio(ratio, available: available), at: path)
        container.update(tree: tree, focused: focusedView, zoomed: zoomedView)
    }

    private func refresh() {
        container.update(tree: tree, focused: focusedView, zoomed: zoomedView)
        applyVisibility()
    }

    private func applyVisibility() {
        for view in tree.leaves {
            let visible = isShown && (zoomedView == nil || zoomedView === view)
            if visible { view.syncDisplay() }
            view.setVisible(visible)
        }
    }
}
