import AppKit
import GhosttyKit

extension TerminalView: NSMenuItemValidation {
    // Only reached via super.rightMouseDown, i.e. when Ghostty did not consume the click (mouse not captured by the app).
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item("Copy", #selector(copy(_:))))
        menu.addItem(item("Paste", #selector(paste(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Split Right", #selector(splitRight(_:))))
        menu.addItem(item("Split Left", #selector(splitLeft(_:))))
        menu.addItem(item("Split Down", #selector(splitDown(_:))))
        menu.addItem(item("Split Up", #selector(splitUp(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Close Pane", #selector(closePaneFromMenu(_:))))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let surface else { return false }
        if item.action == #selector(copy(_:)) { return ghostty_surface_has_selection(surface) }
        return true
    }

    @objc private func splitRight(_ sender: Any?) { perform("new_split:right") }
    @objc private func splitLeft(_ sender: Any?) { perform("new_split:left") }
    @objc private func splitDown(_ sender: Any?) { perform("new_split:down") }
    @objc private func splitUp(_ sender: Any?) { perform("new_split:up") }
    @objc private func closePaneFromMenu(_ sender: Any?) { perform("close_surface") }
}
