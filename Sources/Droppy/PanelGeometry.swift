import AppKit

enum PanelEdge {
    case top, bottom, left, right, center
}

struct PanelGeometry {
    var edge: PanelEdge = .top
    var widthFraction: CGFloat = 1.0
    var heightFraction: CGFloat = 0.4

    func shownFrame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let size = NSSize(width: area.width * widthFraction, height: area.height * heightFraction)
        var origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        switch edge {
        case .top: origin.y = area.maxY - size.height
        case .bottom: origin.y = area.minY
        case .left: origin.x = area.minX
        case .right: origin.x = area.maxX - size.width
        case .center: break
        }
        return NSRect(origin: origin, size: size)
    }

    func hiddenFrame(for shown: NSRect, on screen: NSScreen) -> NSRect {
        var frame = shown
        switch edge {
        case .top: frame.origin.y = screen.frame.maxY
        case .bottom: frame.origin.y = screen.frame.minY - shown.height
        case .left: frame.origin.x = screen.frame.minX - shown.width
        case .right: frame.origin.x = screen.frame.maxX
        case .center: break
        }
        return frame
    }

    var fadesInPlace: Bool { edge == .center }
}
