import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var runtime: GhosttyRuntime?
    private var panelController: PanelController?
    private var hotKey: GlobalHotKey?
    private var activeBinding: HotKeyBinding?
    private let configStore = ConfigStore()
    private var hotkeyIssue: ConfigIssue?
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
        panelController?.onOpenConfig = { [weak self] in self?.configStore.openInEditor() }

        setUpMainMenu()
        setUpStatusItem()

        let hotKey = GlobalHotKey { [weak self] in self?.panelController?.toggle() }
        self.hotKey = hotKey
        configStore.onChange = { [weak self] _ in self?.applyConfig() }
        configStore.load()
        applyConfig()
        configStore.startWatching()
    }

    private func applyConfig() {
        let config = configStore.result.config
        panelController?.apply(config)
        applyHotKey(config.hotkey)
        rebuildStatusMenu()
    }

    // A binding that cannot be registered leaves the previous one in place.
    private func applyHotKey(_ binding: HotKeyBinding) {
        hotkeyIssue = nil
        guard let hotKey, binding != activeBinding else { return }
        if hotKey.register(binding) {
            activeBinding = binding
            return
        }
        log.error("hotkey registration failed")
        hotkeyIssue = ConfigIssue(line: configStore.result.hotkeyLine ?? 0, message: "hotkey is unavailable")
        let fallback = activeBinding ?? .default
        if hotKey.register(fallback) { activeBinding = fallback }
    }

    private func setUpMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Open Config", action: #selector(openConfig), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
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
        statusItem = item
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle", action: #selector(toggle), keyEquivalent: "").target = self
        if let issue = configStore.result.issues.first ?? hotkeyIssue {
            menu.addItem(.separator())
            let item = menu.addItem(withTitle: issue.summary, action: nil, keyEquivalent: "")
            item.isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Config", action: #selector(openConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func openConfig() {
        configStore.openInEditor()
    }

    @objc private func reloadConfig() {
        configStore.forceReload()
    }

    @objc private func toggle() {
        panelController?.toggle()
    }
}
