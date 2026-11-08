import AppKit

@MainActor
final class ScrollbarView: NSView {
    static let width: CGFloat = 12

    var onScrollToRow: ((UInt64) -> Void)?

    private var total: UInt64 = 0
    private var offset: UInt64 = 0
    private var len: UInt64 = 0
    private var grabOffset: CGFloat = 0

    override var isFlipped: Bool { true }

    func update(total: UInt64, offset: UInt64, len: UInt64) {
        self.total = total
        self.offset = offset
        self.len = len
        isHidden = total <= len
        needsDisplay = true
    }

    private var knobRect: NSRect {
        let track = bounds.height
        guard total > len, total > 0 else { return .zero }
        let height = max(24, track * CGFloat(len) / CGFloat(total))
        let travel = track - height
        let y = travel * CGFloat(offset) / CGFloat(total - len)
        return NSRect(x: 2, y: y, width: bounds.width - 4, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let knob = knobRect
        guard !knob.isEmpty else { return }
        NSColor.labelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: knob, xRadius: knob.width / 2, yRadius: knob.width / 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let knob = knobRect
        grabOffset = knob.contains(point) ? point.y - knob.minY : knob.height / 2
        scroll(to: point.y)
    }

    override func mouseDragged(with event: NSEvent) {
        scroll(to: convert(event.locationInWindow, from: nil).y)
    }

    private func scroll(to y: CGFloat) {
        let travel = bounds.height - knobRect.height
        guard travel > 0, total > len else { return }
        let fraction = min(max((y - grabOffset) / travel, 0), 1)
        onScrollToRow?(UInt64((fraction * CGFloat(total - len)).rounded()))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : super.hitTest(point)
    }
}
