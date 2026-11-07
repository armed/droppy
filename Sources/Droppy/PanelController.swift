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
    private let tabs: TabManager
    private var previousApp: NSRunningApplication?
    private var animationToken = 0
    private var animationsInFlight = 0
    private var isResizing = false
    private var shownScreen: NSScreen?
    private(set) var isVisible = false

    init(runtime: GhosttyRuntime) {
        self.runtime = runtime
        tabs = TabManager(runtime: runtime)
        super.init()
        if let stored = UserDefaults.standard.object(forKey: Self.heightKey) as? Double,
           PanelGeometry.heightRange.contains(CGFloat(stored)) {
            geometry.heightFraction = CGFloat(stored)
        }
        content.stripAtTop = geometry.resizeEdgeIsTop
        content.tabBarPosition = geometry.tabBarPosition
        content.tabBar.onSelect = { [weak self] in self?.tabs.select(at: $0) }
        content.tabBar.onClose = { [weak self] index in
            guard let self, self.tabs.tabs.indices.contains(index) else { return }
            self.requestClose([self.tabs.tabs[index]])
        }
        content.tabBar.onNew = { [weak self] in self?.newTab(inheriting: self?.tabs.selected?.focusedView) }
        content.strip.onDrag = { [weak self] in self?.dragResize(toCursorY: $0) }
        content.strip.onEnd = { [weak self] in self?.endResize() }
        panel.contentView = content
        panel.delegate = self
        runtime.onCloseSurface = { [weak self] view, processAlive in self?.surfaceClosed(view, processAlive: processAlive) }
        runtime.onResizeKey = { [weak self] in self?.stepHeight(grow: $0) }
        runtime.onAction = { [weak self] action, view in self?.handle(action, from: view) ?? false }
        tabs.onChange = { [weak self] in self?.refreshTabs() }
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

        let screen = screenUnderMouse()
        shownScreen = screen
        let shown = geometry.shownFrame(on: screen)
        let hidden = geometry.hiddenFrame(for: shown, on: screen)

        // Only popUpMenu and above can render over the menu bar and off-screen during the slide.
        panel.level = .popUpMenu
        panel.setFrame(geometry.fadesInPlace ? shown : hidden, display: false)
        panel.alphaValue = geometry.fadesInPlace ? 0 : 1
        if tabs.isEmpty { tabs.newTab(inheriting: nil) }
        panel.makeKeyAndOrderFront(nil)
        refreshTabs()

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
            self.refreshTabs()
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
        guard let view = tabs.selected?.focusedView else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    private func refreshBar() {
        content.tabBarVisible = tabs.tabs.count > 1
        content.tabBar.update(
            titles: tabs.tabs.map(\.title),
            selected: tabs.selectedIndex,
            palette: TabBarPalette(terminalBackground: runtime.backgroundColor)
        )
    }

    private func refreshTabs() {
        content.display(tabs.selected)
        refreshBar()
        let panelShown = isVisible && panel.isVisible
        for tab in tabs.tabs {
            let visible = panelShown && tab === tabs.selected
            for view in tab.views {
                if visible { view.syncDisplay() }
                view.setVisible(visible)
            }
        }
        if panelShown { focusTerminal() }
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func newTab(inheriting source: TerminalView?) {
        tabs.newTab(inheriting: source)
    }

    // Actions fire inside a surface's own callback, so anything that can free or hide surfaces is deferred.
    private func handle(_ action: TerminalAction, from view: TerminalView?) -> Bool {
        switch action {
        case .setTitle(let title):
            view?.title = title
            refreshBar()
        case .newTab:
            let source = view ?? tabs.selected?.focusedView
            DispatchQueue.main.async { self.newTab(inheriting: source) }
        case .closeTab(let mode):
            DispatchQueue.main.async {
                guard let current = view.flatMap({ self.tabs.tab(containing: $0) }) ?? self.tabs.selected else { return }
                self.requestClose(self.tabsToClose(mode, relativeTo: current))
            }
        case .gotoTab(let target):
            DispatchQueue.main.async { self.gotoTab(target) }
        }
        return true
    }

    private func gotoTab(_ target: Int32) {
        switch target {
        case -1: tabs.selectPrevious()
        case -2: tabs.selectNext()
        case -3: tabs.selectLast()
        default: tabs.select(at: Int(target) - 1)
        }
    }

    private func tabsToClose(_ mode: CloseTabMode, relativeTo tab: Tab) -> [Tab] {
        guard let index = tabs.tabs.firstIndex(where: { $0 === tab }) else { return [] }
        return switch mode {
        case .this: [tab]
        case .other: tabs.tabs.filter { $0 !== tab }
        case .right: Array(tabs.tabs.dropFirst(index + 1))
        }
    }

    private func requestClose(_ doomed: [Tab]) {
        guard !doomed.isEmpty else { return }
        let busy = doomed.contains { tab in
            tab.views.contains(where: \.needsConfirmClose)
        }
        guard busy, panel.isVisible else {
            closeNow(doomed)
            return
        }
        let alert = NSAlert()
        alert.messageText = doomed.count == 1 ? "Close this tab?" : "Close \(doomed.count) tabs?"
        alert.informativeText = "A process is still running and will be terminated."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.closeNow(doomed) }
        }
    }

    // A tab may have been closed while the confirmation was open, so each one is re-checked.
    private func closeNow(_ doomed: [Tab]) {
        for tab in doomed where tabs.tabs.contains(where: { $0 === tab }) {
            tabs.remove(tab)
        }
        if tabs.isEmpty, isVisible { hide() }
    }

    private func surfaceClosed(_ view: TerminalView, processAlive: Bool) {
        guard let tab = tabs.tab(containing: view) else { return }
        guard processAlive else {
            if tab.remove(view) { closeNow([tab]) } else { refreshTabs() }
            return
        }
        requestClose([tab])
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, hidesOnFocusLoss, !isResizing, panel.attachedSheet == nil else { return }
        if NSApp.isActive { previousApp = nil }
        hide()
    }
}
