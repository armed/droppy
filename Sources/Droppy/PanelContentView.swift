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

final class PanelContentView: NSView {
    let strip = ResizeStrip()

    init() {
        super.init(frame: .zero)
        strip.wantsLayer = true
        addSubview(strip)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(stripAtTop: Bool) {
        strip.autoresizingMask = stripAtTop ? [.width, .minYMargin] : [.width, .maxYMargin]
        let y = stripAtTop ? bounds.height - ResizeStrip.thickness : 0
        strip.frame = NSRect(x: 0, y: y, width: bounds.width, height: ResizeStrip.thickness)
    }

    func attach(_ terminal: NSView) {
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal, positioned: .below, relativeTo: strip)
    }
}
