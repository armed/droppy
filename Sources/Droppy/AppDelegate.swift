import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var runtime: GhosttyRuntime?
    private var panelController: PanelController?
    private var hotKey: GlobalHotKey?
    private var quitPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            runtime = try GhosttyRuntime()
        } catch {
            log.fault("ghostty failed to start: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        panelController = PanelController(runtime: runtime!)

        setUpMainMenu()
        setUpStatusItem()

        let hotKey = GlobalHotKey { [weak self] in self?.panelController?.toggle() }
        if !hotKey.register(.default) { log.error("hotkey registration failed") }
        self.hotKey = hotKey
    }

    private func setUpMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Droppy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let panelController, !Self.isSystemQuit else { return .terminateNow }
        let busy = panelController.busyTerminalCount
        guard busy > 0 else { return .terminateNow }
        guard !quitPending else { return .terminateCancel }
        quitPending = true
        panelController.askToQuit(busy: busy) { [weak self] quit in
            self?.quitPending = false
            NSApp.reply(toApplicationShouldTerminate: quit)
        }
        return .terminateLater
    }

    // Logout, restart and shutdown carry a reason on the quit event, and blocking them would stall the whole system.
    private static var isSystemQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) else { return false }
        return [kAEReallyLogOut, kAEShutDown, kAERestart, kAEQuitAll].contains { reason.enumCodeValue == OSType($0) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return false
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Droppy")
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func toggle() {
        panelController?.toggle()
    }
}
