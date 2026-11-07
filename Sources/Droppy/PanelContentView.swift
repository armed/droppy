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

// Sits above the terminal's Metal layers and must never take a click meant for the strip, tabs or terminal.
final class BorderView: NSView {
    private let layers = [PanelSides.top, .bottom, .left, .right].map { ($0, CALayer()) }
    private var sides: PanelSides = []
    private var width: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.zPosition = 1000
        for (_, line) in layers { layer?.addSublayer(line) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(sides: PanelSides, width: CGFloat, color: NSColor) {
        self.sides = sides
        self.width = width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (side, line) in layers {
            line.backgroundColor = color.cgColor
            line.isHidden = width <= 0 || !sides.contains(side)
        }
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (side, line) in layers {
            line.contentsScale = scale
            switch side {
            case .top: line.frame = NSRect(x: 0, y: bounds.height - width, width: bounds.width, height: width)
            case .bottom: line.frame = NSRect(x: 0, y: 0, width: bounds.width, height: width)
            case .left: line.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
            default: line.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
            }
        }
        CATransaction.commit()
    }
}

@MainActor
final class PanelContentView: NSView {
    let strip = ResizeStrip()
    let tabBar = TabBarView(frame: .zero)
    let border = BorderView(frame: .zero)

    var stripAtTop = false { didSet { relayout() } }
    var tabBarPosition = TabBarPosition.bottom { didSet { relayout() } }
    var tabBarVisible = false {
        didSet {
            tabBar.isHidden = !tabBarVisible
            relayout()
        }
    }

    private var shown: NSView?

    override var acceptsFirstResponder: Bool { true }

    // Swallows keys while the panel slides out, so they are neither typed into the shell nor beep.
    override func keyDown(with event: NSEvent) {}

    init() {
        super.init(frame: .zero)
        strip.wantsLayer = true
        tabBar.isHidden = true
        addSubview(tabBar)
        addSubview(strip)
        addSubview(border)
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
        border.frame = bounds
    }
}
