import AppKit

final class DimView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class DividerView: NSView {
    static let hitThickness: CGFloat = 6

    var path: [Bool] = []
    var color = NSColor(white: 1, alpha: 0.16) { didSet { needsDisplay = true } }
    var axis = SplitAxis.horizontal
    var onDrag: (([Bool], NSPoint) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        switch axis {
        case .horizontal:
            NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        case .vertical:
            NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        onDrag?(path, event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(path, event.locationInWindow)
    }
}

@MainActor
final class SplitContainerView: NSView {
    var onRatioDrag: (([Bool], CGFloat, CGFloat) -> Void)?

    var dividerColor = NSColor(white: 1, alpha: 0.16) {
        didSet { for view in dividerViews { view.color = dividerColor } }
    }

    private var tree: SplitNode<TerminalView>?
    private var focused: TerminalView?
    private var zoomed: TerminalView?
    private var dims: [ObjectIdentifier: DimView] = [:]
    private var dividerViews: [DividerView] = []
    private var dividers: [SplitDivider] = []
    private var overlays: [(view: TerminalView, overlay: NSView)] = []

    func setPaneOverlays(_ overlays: [(view: TerminalView, overlay: NSView)]) {
        self.overlays.forEach { $0.overlay.removeFromSuperview() }
        self.overlays = overlays
        overlays.forEach { addSubview($0.overlay) }
        relayout()
    }

    func update(tree: SplitNode<TerminalView>, focused: TerminalView, zoomed: TerminalView?) {
        self.tree = tree
        self.focused = focused
        self.zoomed = zoomed

        let leaves = tree.leaves
        for (id, dim) in dims where !leaves.contains(where: { ObjectIdentifier($0) == id }) {
            dim.removeFromSuperview()
            dims[id] = nil
        }
        for view in subviews.compactMap({ $0 as? TerminalView }) where !leaves.contains(where: { $0 === view }) {
            view.removeFromSuperview()
        }
        for leaf in leaves where leaf.superview !== self {
            addSubview(leaf)
            let dim = DimView()
            addSubview(dim)
            dims[ObjectIdentifier(leaf)] = dim
        }
        relayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    func relayout() {
        guard let tree else { return }
        let leaves = tree.leaves
        let layout = tree.layout(in: bounds)

        for pane in layout.panes {
            let isZoomedAway = zoomed.map { $0 !== pane.leaf } ?? false
            pane.leaf.isHidden = isZoomedAway
            pane.leaf.frame = zoomed === pane.leaf ? bounds : pane.frame
            let dim = dims[ObjectIdentifier(pane.leaf)]
            dim?.frame = pane.leaf.frame
            dim?.isHidden = isZoomedAway || leaves.count == 1 || pane.leaf === focused
            if let bar = pane.leaf.searchBar {
                if bar.superview !== self { addSubview(bar) }
                bar.isHidden = isZoomedAway
                let frame = pane.leaf.frame
                bar.frame = NSRect(
                    x: max(frame.minX, frame.maxX - SearchBarView.size.width - SearchBarView.margin),
                    y: max(frame.minY, frame.maxY - SearchBarView.size.height - SearchBarView.margin),
                    width: min(SearchBarView.size.width, frame.width),
                    height: SearchBarView.size.height
                )
            }
        }

        for (view, overlay) in overlays {
            let size = overlay.fittingSize
            let width = min(size.width, max(view.frame.width - 16, 0))
            overlay.isHidden = view.isHidden
            overlay.frame = NSRect(
                x: view.frame.midX - width / 2,
                y: view.frame.midY - size.height / 2,
                width: width,
                height: size.height
            )
        }

        dividers = zoomed == nil ? layout.dividers : []
        while dividerViews.count > dividers.count { dividerViews.removeLast().removeFromSuperview() }
        while dividerViews.count < dividers.count {
            let view = DividerView()
            view.onDrag = { [weak self] path, location in self?.dragged(path, to: location) }
            view.color = dividerColor
            addSubview(view)
            dividerViews.append(view)
        }
        let grip = DividerView.hitThickness
        for (view, divider) in zip(dividerViews, dividers) {
            view.path = divider.path
            if view.axis != divider.axis {
                view.axis = divider.axis
                view.needsDisplay = true
            }
            let rect = divider.rect
            view.frame = divider.axis == .horizontal
                ? rect.insetBy(dx: (rect.width - grip) / 2, dy: 0)
                : rect.insetBy(dx: 0, dy: (rect.height - grip) / 2)
            view.needsDisplay = true
            window?.invalidateCursorRects(for: view)
        }
    }

    private func dragged(_ path: [Bool], to windowLocation: NSPoint) {
        guard let divider = dividers.first(where: { $0.path == path }) else { return }
        let point = convert(windowLocation, from: nil)
        let thickness = SplitNode<TerminalView>.dividerThickness
        let rect = divider.splitRect
        switch divider.axis {
        case .horizontal:
            let available = rect.width - thickness
            onRatioDrag?(path, (point.x - rect.minX - thickness / 2) / available, available)
        case .vertical:
            let available = rect.height - thickness
            onRatioDrag?(path, (rect.maxY - point.y - thickness / 2) / available, available)
        }
    }
}
