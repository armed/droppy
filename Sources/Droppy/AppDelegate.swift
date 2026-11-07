import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var runtime: GhosttyRuntime?
    private var panelController: PanelController?
    private var hotKey: GlobalHotKey?

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

    // Cmd+Q is deliberately not bound: an accidental press would kill every shell.
    private func setUpMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Droppy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
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
