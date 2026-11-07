import AppKit

final class ResizeStrip: NSView {
    static let thickness: CGFloat = 6

    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        onDrag?(NSEvent.mouseLocation.y)
    }

    // Screen coordinates keep the drag tracking when the cursor leaves the panel.
    override func mouseDragged(with event: NSEvent) {
        onDrag?(NSEvent.mouseLocation.y)
    }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }
}

@MainActor
final class PanelContentView: NSView {
    let strip = ResizeStrip()
    let tabBar = TabBarView(frame: .zero)

    var stripAtTop = false { didSet { relayout() } }
    var tabBarPosition = TabBarPosition.bottom { didSet { relayout() } }
    var tabBarVisible = false {
        didSet {
            tabBar.isHidden = !tabBarVisible
            relayout()
        }
    }

    private var shown: NSView?

    init() {
        super.init(frame: .zero)
        strip.wantsLayer = true
        tabBar.isHidden = true
        addSubview(tabBar)
        addSubview(strip)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func display(_ tab: Tab?) {
        let view = tab?.contentView
        guard shown !== view else { return }
        shown?.removeFromSuperview()
        shown = view
        if let view {
            addSubview(view, positioned: .below, relativeTo: tabBar)
        }
        relayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    func relayout() {
        let width = bounds.width
        let height = bounds.height
        let barHeight = tabBarVisible ? TabBarView.height : 0
        var area = bounds
        switch tabBarPosition {
        case .bottom:
            tabBar.frame = NSRect(x: 0, y: 0, width: width, height: barHeight)
            area = NSRect(x: 0, y: barHeight, width: width, height: height - barHeight)
        case .top:
            tabBar.frame = NSRect(x: 0, y: height - barHeight, width: width, height: barHeight)
            area = NSRect(x: 0, y: 0, width: width, height: height - barHeight)
        }
        shown?.frame = area
        let stripY = stripAtTop ? height - ResizeStrip.thickness : 0
        strip.frame = NSRect(x: 0, y: stripY, width: width, height: ResizeStrip.thickness)
    }
}
