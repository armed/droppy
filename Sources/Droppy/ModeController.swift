import AppKit
import Carbon.HIToolbox

enum ModeAction {
    case stay
    case exit
    case switchTo(PanelMode)
}

@MainActor
protocol PanelMode: AnyObject {
    func enter()
    func leave()
    func refresh()
    func handleKey(_ event: NSEvent) -> ModeAction
    func handleClick(on view: TerminalView) -> ModeAction
}

@MainActor
protocol PanelModeHost: AnyObject {
    var selectedTab: Tab? { get }
    var tabCount: Int { get }
    func selectTab(at index: Int)
    func setTabOverlays(_ overlays: [Int: NSView])
    func focusPane(_ view: TerminalView)
}

struct DoubleTapDetector {
    private static let interval: TimeInterval = 0.3

    private var cmdDown = false
    private var dirty = false
    private var lastTap: TimeInterval?

    mutating func reset() {
        cmdDown = false
        dirty = false
        lastTap = nil
    }

    mutating func keyDown() {
        dirty = true
        lastTap = nil
    }

    mutating func flagsChanged(_ event: NSEvent) -> Bool {
        let flags = event.significantModifiers
        if flags == .command {
            if !cmdDown {
                cmdDown = true
                dirty = false
            }
            return false
        }
        guard flags.isEmpty, cmdDown else {
            reset()
            return false
        }
        cmdDown = false
        guard !dirty else {
            lastTap = nil
            return false
        }
        if let lastTap, event.timestamp - lastTap <= Self.interval {
            self.lastTap = nil
            return true
        }
        lastTap = event.timestamp
        return false
    }
}

@MainActor
final class ModeController {
    private static let eventMask: NSEvent.EventTypeMask = [
        .flagsChanged, .keyDown, .keyUp,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .scrollWheel,
    ]

    private unowned let window: NSWindow
    private unowned let host: PanelModeHost
    private var detector = DoubleTapDetector()
    private var monitor: Any?
    private var mode: PanelMode?

    init(window: NSWindow, host: PanelModeHost) {
        self.window = window
        self.host = host
        monitor = NSEvent.addLocalMonitorForEvents(matching: Self.eventMask) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func exit() {
        set(nil)
    }

    func refresh() {
        mode?.refresh()
    }

    private func set(_ new: PanelMode?) {
        detector.reset()
        guard mode !== new else { return }
        mode?.leave()
        mode = new
        mode?.enter()
    }

    private func apply(_ action: ModeAction) {
        switch action {
        case .stay: break
        case .exit: set(nil)
        case .switchTo(let next): set(next)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, window.isKeyWindow else { return event }
        let wasActive = mode != nil
        switch event.type {
        case .flagsChanged:
            if detector.flagsChanged(event) { set(mode == nil ? JumpMode(host: host) : nil) }
        case .keyDown:
            detector.keyDown()
            guard let mode else { return event }
            apply(Int(event.keyCode) == kVK_Escape ? .exit : mode.handleKey(event))
        case .leftMouseDown:
            if let mode, let view = terminalView(at: event.locationInWindow) { apply(mode.handleClick(on: view)) }
        default:
            break
        }
        return wasActive ? nil : event
    }

    private func terminalView(at point: NSPoint) -> TerminalView? {
        var view = window.contentView?.superview?.hitTest(point)
        while let current = view, !(current is TerminalView) { view = current.superview }
        return view as? TerminalView
    }
}
