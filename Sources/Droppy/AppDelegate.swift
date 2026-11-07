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

        setUpStatusItem()

        let hotKey = GlobalHotKey { [weak self] in self?.panelController?.toggle() }
        if !hotKey.register(.default) { log.error("hotkey registration failed") }
        self.hotKey = hotKey
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
