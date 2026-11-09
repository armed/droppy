import AppKit

enum PanelEdge {
    case top, bottom, left, right, center
}

struct PanelGeometry {
    var edge: PanelEdge = .top
    var alignment: PanelAlignment = .center
    var widthFraction: CGFloat = 1.0
    var heightFraction: CGFloat = 0.4
    var isMaximized = false

    // How the panel is anchored vertically: against the top or bottom of the area, or centred.
    private enum VerticalAnchor {
        case top, bottom, center
    }

    private var verticalAnchor: VerticalAnchor {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .center: .center
        case .left, .right:
            switch alignment {
            case .start: .top
            case .end: .bottom
            case .center: .center
            }
        }
    }

    func shownFrame(on screen: NSScreen) -> NSRect {
        shownFrame(in: Self.usableArea(on: screen))
    }

    // visibleFrame keeps reserving the Dock's edge on a fullscreen space even though the Dock is not shown there.
    static func usableArea(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        guard hasFullscreenWindow(on: screen) else { return visible }
        let full = screen.frame
        return NSRect(x: full.minX, y: full.minY, width: full.width, height: visible.maxY - full.minY)
    }

    private static func hasFullscreenWindow(on screen: NSScreen) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return false }
        let full = screen.frame
        // CGWindow bounds are top-left based relative to the primary screen.
        let target = CGRect(x: full.minX, y: primary.frame.maxY - full.maxY, width: full.width, height: full.height)
        // On a notched display a fullscreen window starts below the notch, so its top edge is not the screen's.
        let topInset = max(screen.safeAreaInsets.top, full.maxY - screen.visibleFrame.maxY)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return bounds.minX == target.minX && bounds.width == target.width && bounds.maxY == target.maxY
                && bounds.height >= target.height - topInset - 1
        }
    }

    func hiddenFrame(for shown: NSRect, on screen: NSScreen) -> NSRect {
        hiddenFrame(for: shown, in: screen.frame)
    }

    func shownFrame(in area: NSRect) -> NSRect {
        if isMaximized { return area }
        let size = NSSize(width: area.width * widthFraction, height: area.height * heightFraction)
        var origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        switch edge {
        case .left: origin.x = area.minX
        case .right: origin.x = area.maxX - size.width
        case .top, .bottom:
            switch alignment {
            case .start: origin.x = area.minX
            case .end: origin.x = area.maxX - size.width
            case .center: break
            }
        case .center: break
        }
        switch verticalAnchor {
        case .top: origin.y = area.maxY - size.height
        case .bottom: origin.y = area.minY
        case .center: break
        }
        return NSRect(origin: origin, size: size)
    }

    func hiddenFrame(for shown: NSRect, in screenFrame: NSRect) -> NSRect {
        var frame = shown
        switch edge {
        case .top: frame.origin.y = screenFrame.maxY
        case .bottom: frame.origin.y = screenFrame.minY - shown.height
        case .left: frame.origin.x = screenFrame.minX - shown.width
        case .right: frame.origin.x = screenFrame.maxX
        case .center: break
        }
        return frame
    }

    static let heightRange: ClosedRange<CGFloat> = 0.15...1.0
    static let heightStep: CGFloat = 0.05

    mutating func setHeightFraction(_ fraction: CGFloat) {
        isMaximized = false
        heightFraction = min(max(fraction, Self.heightRange.lowerBound), Self.heightRange.upperBound)
    }

    mutating func stepHeight(grow: Bool) {
        setHeightFraction(heightFraction + (grow ? Self.heightStep : -Self.heightStep))
    }

    // Inverse of shownFrame: the height at which the free edge sits under the cursor.
    // A vertically centred panel's edge moves at half rate.
    func heightFraction(forCursorY y: CGFloat, in area: NSRect) -> CGFloat {
        switch verticalAnchor {
        case .top: (area.maxY - y) / area.height
        case .bottom: (y - area.minY) / area.height
        case .center: 2 * (area.midY - y) / area.height
        }
    }

    var resizeEdgeIsTop: Bool { verticalAnchor == .bottom }

    var fadesInPlace: Bool { edge == .center }
}
