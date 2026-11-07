import AppKit
import GhosttyKit

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    var geometry = PanelGeometry()
    var animationDuration: TimeInterval = 0.2
    var hidesOnFocusLoss = true
    var onOpenConfig: (() -> Void)?
    var onReloadConfig: (() -> Void)?

    // The height the user adjusted at runtime is kept next to the file's height it was based on, so editing
    // the file's height wins over it without the runtime value ever being written into the file.
    private static let runtimeHeightKey = "panelRuntimeHeight"
    private static let baseHeightKey = "panelRuntimeHeightBase"
    private static let legacyHeightKey = "panelHeightFraction"

    private let runtime: GhosttyRuntime
    private let panel = DropPanel()
    private let content = PanelContentView()
    private let tabs: TabManager
    private var configHeight: CGFloat = 0.4
    private var borderWidth: CGFloat = 1
    private var borderColor: RGBA?
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
        runtime.onViewFocused = { [weak self] view in
            self?.tabs.tab(containing: view)?.focus(view)
            self?.refreshBar()
        }
        tabs.onChange = { [weak self] in self?.refreshTabs() }
        runtime.onConfigChange = { [weak self] in self?.refreshAppearance() }
        runtime.onConfirmPaste = { [weak self] view, request in self?.confirmPaste(view, request) }
        refreshAppearance()
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
        updateBorder()
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
            self.panel.invalidateShadow()
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    func hide(userInitiated: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        animationToken += 1
        let token = animationToken

        // Keys typed while the panel slides out must not reach the shell.
        panel.makeFirstResponder(content)

        // Activated before the slide so the previous app is usable at once. It is only cleared in the completion
        // because a show that interrupts this hide still needs it.
        var activatedPreviousApp = false
        if userInitiated, let previousApp, !previousApp.isTerminated {
            previousApp.activate(options: [])
            activatedPreviousApp = true
        }

        let screen = panel.screen ?? screenUnderMouse()
        let hidden = geometry.hiddenFrame(for: panel.frame, on: screen)
        panel.level = .popUpMenu

        animate(to: hidden, alpha: geometry.fadesInPlace ? 0 : 1) { [weak self] in
            guard let self, !self.isVisible, token == self.animationToken else { return }
            self.refreshTabs()
            self.panel.orderOut(nil)
            self.previousApp = nil
            // Otherwise Droppy would stay frontmost with nothing on screen.
            if userInitiated && !activatedPreviousApp { NSApp.hide(nil) }
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
        updateBorder()
    }

    private func saveHeight() {
        let defaults = UserDefaults.standard
        defaults.set(Double(geometry.heightFraction), forKey: Self.runtimeHeightKey)
        defaults.set(Double(configHeight), forKey: Self.baseHeightKey)
    }

    func apply(_ config: Config) {
        let defaults = UserDefaults.standard
        if let legacy = defaults.object(forKey: Self.legacyHeightKey) as? Double {
            if defaults.object(forKey: Self.runtimeHeightKey) == nil {
                defaults.set(legacy, forKey: Self.runtimeHeightKey)
                defaults.set(Double(config.height), forKey: Self.baseHeightKey)
            }
            defaults.removeObject(forKey: Self.legacyHeightKey)
        }
        configHeight = config.height
        if let runtime = defaults.object(forKey: Self.runtimeHeightKey) as? Double,
           let base = defaults.object(forKey: Self.baseHeightKey) as? Double,
           abs(base - Double(config.height)) < 1e-6,
           PanelGeometry.heightRange.contains(CGFloat(runtime)) {
            geometry.heightFraction = CGFloat(runtime)
        } else {
            defaults.removeObject(forKey: Self.runtimeHeightKey)
            defaults.removeObject(forKey: Self.baseHeightKey)
            geometry.heightFraction = config.height
        }
        geometry.edge = config.position
        geometry.alignment = config.alignment
        geometry.widthFraction = config.width
        content.stripAtTop = geometry.resizeEdgeIsTop
        content.tabBarPosition = config.tabBar
        hidesOnFocusLoss = config.hideOnFocusLoss
        panel.hasShadow = config.shadow
        borderWidth = config.borderWidth
        borderColor = config.borderColor
        updateBorder()
        applyHeight()
    }

    // The auto colour is the terminal's foreground at low alpha: quiet, yet different from the background in
    // both dark and light themes.
    private func updateBorder() {
        guard let screen = shownScreen else { return }
        let sides = geometry.borderSides(shown: geometry.shownFrame(on: screen), in: screen.visibleFrame)
        let color = borderColor.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
            ?? runtime.foregroundColor.withAlphaComponent(0.3)
        content.border.update(sides: sides, width: borderWidth, color: color)
        panel.invalidateShadow()
    }

    private func focusTerminal() {
        guard let view = tabs.selected?.focusedView else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    // With a translucent terminal background the window must not paint an opaque backdrop behind it.
    private func refreshAppearance() {
        let opaque = runtime.backgroundOpacity >= 1
        panel.isOpaque = opaque
        panel.backgroundColor = opaque ? .black : .clear
        refreshBar()
        updateBorder()
    }

    private func refreshBar() {
        content.tabBarVisible = tabs.tabs.count > 1
        content.tabBar.update(
            titles: tabs.tabs.map(\.title),
            selected: tabs.selectedIndex,
            palette: TabBarPalette(terminalBackground: runtime.backgroundColor, opacity: runtime.backgroundOpacity)
        )
    }

    private func refreshTabs() {
        content.display(tabs.selected)
        refreshBar()
        let panelShown = isVisible && panel.isVisible
        for tab in tabs.tabs {
            tab.setShown(panelShown && tab === tabs.selected)
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
        case .newSplit(let direction):
            DispatchQueue.main.async {
                guard let tab = self.tab(for: view) else { return }
                self.tabs.split(tab, direction: direction)
            }
        case .gotoSplit(let target):
            DispatchQueue.main.async { self.focusSplit(target, from: view) }
        case .resizeSplit(let direction, let amount):
            tab(for: view)?.resizeSplit(direction, amount: CGFloat(amount))
        case .equalizeSplits:
            tab(for: view)?.equalizeSplits()
        case .toggleSplitZoom:
            DispatchQueue.main.async {
                self.tab(for: view)?.toggleZoom()
                self.refreshTabs()
            }
        case .reloadConfig:
            DispatchQueue.main.async { self.onReloadConfig?() }
        case .openConfig:
            DispatchQueue.main.async { self.onOpenConfig?() }
        case .quit:
            // terminate waits in a nested loop for the confirmation, which would starve the main dispatch queue.
            RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        }
        return true
    }

    private func tab(for view: TerminalView?) -> Tab? {
        view.flatMap { tabs.tab(containing: $0) } ?? tabs.selected
    }

    private func focusSplit(_ target: SplitFocusTarget, from view: TerminalView?) {
        guard let tab = tab(for: view) else { return }
        tab.focusSplit(target)
        refreshTabs()
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
        confirm(title: doomed.count == 1 ? "Close this tab?" : "Close \(doomed.count) tabs?") { [weak self] in
            self?.closeNow(doomed)
        }
    }

    var busyTerminalCount: Int { tabs.tabs.reduce(0) { $0 + $1.views.filter(\.needsConfirmClose).count } }

    func askToQuit(busy: Int, answer: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Quit Droppy?"
        alert.informativeText = busy == 1
            ? "A process is still running in 1 terminal and will be terminated."
            : "A process is still running in \(busy) terminals and will be terminated."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if isVisible, panel.isVisible, panel.attachedSheet == nil {
            alert.beginSheetModal(for: panel) { response in
                MainActor.assumeIsolated {
                    let quit = response == .alertFirstButtonReturn
                    if !quit { self.focusTerminal() }
                    answer(quit)
                }
            }
            return
        }
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        let quit = alert.runModal() == .alertFirstButtonReturn
        if !quit, let previous, previous != NSRunningApplication.current { previous.activate(options: []) }
        // NSApp.reply must not run before applicationShouldTerminate has returned .terminateLater.
        DispatchQueue.main.async { answer(quit) }
    }

    // Cancel is the default button so a stray Return never pastes. If the surface goes away while the sheet is up,
    // the request is denied first, while the surface is still valid, and the sheet is dismissed.
    private func confirmPaste(_ view: TerminalView, _ request: PasteConfirmation) {
        guard let surface = view.surface else { return }
        guard isVisible, panel.isVisible, panel.attachedSheet == nil else {
            ghostty_surface_deny_clipboard_request(surface, request.state)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Paste this text?"
        alert.informativeText = "Pasting it may run commands immediately."
        alert.alertStyle = .warning
        alert.accessoryView = Self.previewView(for: request.text)
        let paste = alert.addButton(withTitle: "Paste")
        let cancel = alert.addButton(withTitle: "Cancel")
        paste.keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        panel.makeFirstResponder(nil)

        var answered = false
        let answer: (Bool) -> Void = { [weak view] paste in
            guard !answered, let view, let surface = view.surface else { return }
            answered = true
            view.willClose = nil
            if paste {
                GhosttyRuntime.completeRequest(surface: surface, state: request.state, contents: request.contents, available: request.available, confirmed: true)
            } else {
                ghostty_surface_deny_clipboard_request(surface, request.state)
            }
        }
        view.willClose = { [weak self, weak alert] in
            answer(false)
            if let sheet = alert?.window { self?.panel.endSheet(sheet) }
        }
        alert.beginSheetModal(for: panel) { [weak self] response in
            MainActor.assumeIsolated {
                answer(response == .alertFirstButtonReturn)
                self?.focusTerminal()
            }
        }
    }

    private static func previewView(for text: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 160))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        return scroll
    }

    private func confirm(title: String, then action: @escaping @MainActor () -> Void) {
        // A sheet is already up (for instance the quit confirmation); stacking a second one on the panel is not possible.
        guard panel.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "A process is still running and will be terminated."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: panel) { response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { action() }
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
        guard tabs.tab(containing: view) != nil else { return }
        guard processAlive, panel.isVisible else {
            closePane(view)
            return
        }
        confirm(title: "Close this terminal?") { [weak self] in self?.closePane(view) }
    }

    // The pane may already be gone by the time a confirmation answers, so membership is re-checked here.
    private func closePane(_ view: TerminalView) {
        guard let tab = tabs.tab(containing: view) else { return }
        if tab.remove(view) {
            closeNow([tab])
        } else {
            view.close()
            refreshTabs()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, hidesOnFocusLoss, !isResizing, panel.attachedSheet == nil else { return }
        previousApp = nil
        hide(userInitiated: false)
    }
}
