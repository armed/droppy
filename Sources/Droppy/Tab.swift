import AppKit

@MainActor
final class Tab {
    private let root: TerminalView

    init(root: TerminalView) {
        self.root = root
    }

    var views: [TerminalView] { [root] }
    var focusedView: TerminalView { root }
    var contentView: NSView { root }

    var title: String {
        focusedView.title.isEmpty ? "Terminal" : focusedView.title
    }

    func contains(_ view: TerminalView) -> Bool {
        views.contains { $0 === view }
    }

    // Returns true when the tab has no views left and must be closed.
    func remove(_ view: TerminalView) -> Bool {
        true
    }
}
