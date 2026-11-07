import AppKit

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    var geometry = PanelGeometry()
    var animationDuration: TimeInterval = 0.2
    var hidesOnFocusLoss = true

    private static let heightKey = "panelHeightFraction"

    private let runtime: GhosttyRuntime
    private let panel = DropPanel()
    private let content = PanelContentView()
    private var terminal: TerminalView?
    private var previousApp: NSRunningApplication?
    private var animationToken = 0
    private var animationsInFlight = 0
    private var isResizing = false
    private var shownScreen: NSScreen?
    private(set) var isVisible = false

    init(runtime: GhosttyRuntime) {
        self.runtime = runtime
        super.init()
        if let stored = UserDefaults.standard.object(forKey: Self.heightKey) as? Double,
           PanelGeometry.heightRange.contains(CGFloat(stored)) {
            geometry.heightFraction = CGFloat(stored)
        }
        content.configure(stripAtTop: geometry.resizeEdgeIsTop)
        content.strip.onDrag = { [weak self] in self?.dragResize(toCursorY: $0) }
        content.strip.onEnd = { [weak self] in self?.endResize() }
        panel.contentView = content
        panel.delegate = self
        runtime.onCloseSurface = { [weak self] view in self?.surfaceClosed(view) }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
        animationToken += 1
        let token = animationToken

        if !NSApp.isActive,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }

        let terminal = ensureTerminal()
        let screen = screenUnderMouse()
        shownScreen = screen
        let shown = geometry.shownFrame(on: screen)
        let hidden = geometry.hiddenFrame(for: shown, on: screen)

        // Only popUpMenu and above can render over the menu bar and off-screen during the slide.
        panel.level = .popUpMenu
        panel.setFrame(geometry.fadesInPlace ? shown : hidden, display: false)
        panel.alphaValue = geometry.fadesInPlace ? 0 : 1
        panel.makeKeyAndOrderFront(nil)
        terminal.syncDisplay()
        terminal.setVisible(true)

        animate(to: shown, alpha: 1) { [weak self] in
            guard let self, self.isVisible, token == self.animationToken else { return }
            // Floating (rather than popUpMenu) lets IME candidate windows appear above the panel.
            self.panel.level = .floating
            self.focusTerminal()
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        animationToken += 1
        let token = animationToken

        if let previousApp {
            self.previousApp = nil
            if !previousApp.isTerminated { previousApp.activate(options: []) }
        }

        let screen = panel.screen ?? screenUnderMouse()
        let hidden = geometry.hiddenFrame(for: panel.frame, on: screen)
        panel.level = .popUpMenu

        animate(to: hidden, alpha: geometry.fadesInPlace ? 0 : 1) { [weak self] in
            guard let self, !self.isVisible, token == self.animationToken else { return }
            self.panel.orderOut(nil)
            self.terminal?.setVisible(false)
        }
    }

    private func animate(to frame: NSRect, alpha: CGFloat, completion: @escaping @MainActor () -> Void) {
        animationsInFlight += 1
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            MainActor.assumeIsolated {
                self.animationsInFlight -= 1
                completion()
            }
        })
    }

    private func stepHeight(grow: Bool) {
        geometry.stepHeight(grow: grow)
        applyHeight()
        saveHeight()
    }

    private func dragResize(toCursorY y: CGFloat) {
        guard let screen = shownScreen else { return }
        isResizing = true
        geometry.setHeightFraction(geometry.heightFraction(forCursorY: y, in: screen.visibleFrame))
        applyHeight()
    }

    private func endResize() {
        isResizing = false
        saveHeight()
    }

    // A slide in flight owns the frame, so resizing is ignored until it settles.
    private func applyHeight() {
        guard isVisible, animationsInFlight == 0, let screen = shownScreen else { return }
        panel.setFrame(geometry.shownFrame(on: screen), display: true)
    }

    private func saveHeight() {
        UserDefaults.standard.set(Double(geometry.heightFraction), forKey: Self.heightKey)
    }

    private func focusTerminal() {
        guard let terminal else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(terminal)
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func ensureTerminal() -> TerminalView {
        if let terminal { return terminal }
        let view = TerminalView(runtime: runtime)
        view.onResizeKey = { [weak self] in self?.stepHeight(grow: $0) }
        content.attach(view)
        terminal = view
        return view
    }

    private func surfaceClosed(_ view: TerminalView) {
        guard view === terminal else { return }
        if isVisible {
            hide()
        }
        // The shell is gone, so the surface is dropped right away; the next show builds a fresh one.
        view.close()
        view.removeFromSuperview()
        terminal = nil
        if !isVisible { panel.orderOut(nil) }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, hidesOnFocusLoss, !isResizing, panel.attachedSheet == nil else { return }
        if NSApp.isActive { previousApp = nil }
        hide()
    }
}
