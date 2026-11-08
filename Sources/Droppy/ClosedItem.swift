import Foundation

@MainActor
final class PaneState {
    let cwd: String?
    weak var live: TerminalView?

    init(cwd: String?, live: TerminalView) {
        self.cwd = cwd
        self.live = live
    }
}

struct ClosedTab {
    let index: Int
    let userTitle: String?
    let tree: SplitNode<PaneState>
    let focusedIndex: Int
}

struct ClosedPane {
    weak var tab: Tab?
    let tree: SplitNode<PaneState>
    let closedIndex: Int
}

enum ClosedItem {
    case tab(ClosedTab)
    case pane(ClosedPane)
}
