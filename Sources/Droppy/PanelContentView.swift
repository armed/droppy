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

private func effectiveRadius(_ radius: CGFloat, in rect: NSRect) -> CGFloat {
    max(0, min(radius, min(rect.width, rect.height) / 2))
}

private func roundedPath(in rect: NSRect, radius: CGFloat, corners: PanelCorners) -> CGPath {
    let r = effectiveRadius(radius, in: rect)
    let tl = corners.contains(.topLeft) ? r : 0
    let tr = corners.contains(.topRight) ? r : 0
    let bl = corners.contains(.bottomLeft) ? r : 0
    let br = corners.contains(.bottomRight) ? r : 0
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + bl, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + br), radius: br)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tr))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - tr, y: rect.maxY), radius: tr)
    path.addLine(to: CGPoint(x: rect.minX + tl, y: rect.maxY))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - tl), radius: tl)
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bl))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + bl, y: rect.minY), radius: bl)
    path.closeSubpath()
    return path
}

// Sits above the terminal's Metal layers and must never take a click meant for the strip, tabs or terminal.
final class BorderView: NSView {
    private let stroke = CAShapeLayer()
    private var sides: PanelSides = []
    private var width: CGFloat = 0
    private var radius: CGFloat = 0
    private var corners: PanelCorners = []

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.zPosition = 1000
        stroke.fillColor = nil
        stroke.lineCap = .butt
        layer?.addSublayer(stroke)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(sides: PanelSides, width: CGFloat, color: NSColor, radius: CGFloat, corners: PanelCorners) {
        self.sides = sides
        self.width = width
        self.radius = radius
        self.corners = corners
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.strokeColor = color.cgColor
        stroke.lineWidth = width
        stroke.isHidden = width <= 0 || sides.isEmpty
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.frame = bounds
        stroke.contentsScale = window?.backingScaleFactor ?? 2
        stroke.path = strokePath()
        CATransaction.commit()
    }

    private func strokePath() -> CGPath {
        let rect = bounds.insetBy(dx: width / 2, dy: width / 2)
        guard rect.width > 0, rect.height > 0 else { return CGMutablePath() }
        let r = effectiveRadius(radius - width / 2, in: rect)
        let tl = corners.contains(.topLeft) ? r : 0
        let tr = corners.contains(.topRight) ? r : 0
        let bl = corners.contains(.bottomLeft) ? r : 0
        let br = corners.contains(.bottomRight) ? r : 0
        let path = CGMutablePath()
        if sides.contains(.top) {
            path.move(to: CGPoint(x: rect.minX + tl, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        }
        if sides.contains(.bottom) {
            path.move(to: CGPoint(x: rect.minX + bl, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.minY))
        }
        if sides.contains(.left) {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + bl))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - tl))
        }
        if sides.contains(.right) {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY + br))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tr))
        }
        if r > 0 {
            if corners.contains(.topLeft), sides.isSuperset(of: [.top, .left]) {
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - r))
                path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
            }
            if corners.contains(.topRight), sides.isSuperset(of: [.top, .right]) {
                path.move(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
                path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: true)
            }
            if corners.contains(.bottomRight), sides.isSuperset(of: [.bottom, .right]) {
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY + r))
                path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
            }
            if corners.contains(.bottomLeft), sides.isSuperset(of: [.bottom, .left]) {
                path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
                path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
            }
        }
        return path
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
    private var cornerRadius: CGFloat = 0
    private var roundedCorners: PanelCorners = []
    private let cornerMask = CAShapeLayer()

    override var acceptsFirstResponder: Bool { true }

    // Swallows keys while the panel slides out, so they are neither typed into the shell nor beep.
    override func keyDown(with event: NSEvent) {}

    init() {
        super.init(frame: .zero)
        wantsLayer = true
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

    func setCorners(radius: CGFloat, corners: PanelCorners) {
        cornerRadius = radius
        roundedCorners = corners
        updateMask()
    }

    private func updateMask() {
        guard cornerRadius > 0, !roundedCorners.isEmpty, bounds.width > 0, bounds.height > 0 else {
            layer?.mask = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cornerMask.frame = bounds
        cornerMask.path = roundedPath(in: bounds, radius: cornerRadius, corners: roundedCorners)
        layer?.mask = cornerMask
        CATransaction.commit()
    }

    func relayout() {
        updateMask()
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
