import Foundation
import GhosttyKit

@MainActor
final class TabManager {
    private let runtime: GhosttyRuntime
    private var list = TabList<Tab>()
    private var closed: [(date: Date, item: ClosedItem)] = []
    private static let undoLimit = 10

    var onChange: (() -> Void)?
    var autoEqualizeSplits = false

    init(runtime: GhosttyRuntime) {
        self.runtime = runtime
    }

    var tabs: [Tab] { list.items }
    var selected: Tab? { list.selected }
    var selectedIndex: Int { list.selectedIndex }
    var isEmpty: Bool { list.isEmpty }

    func tab(containing view: TerminalView) -> Tab? {
        list.items.first { $0.contains(view) }
    }

    @discardableResult
    func newTab(inheriting source: TerminalView?) -> Tab {
        let view = TerminalView(runtime: runtime, inheritFrom: source, context: GHOSTTY_SURFACE_CONTEXT_TAB)
        let tab = Tab(root: view)
        list.insertAfterSelected(tab)
        onChange?()
        return tab
    }

    func split(_ tab: Tab, direction: SplitDirection) {
        let source = tab.focusedView
        let view = TerminalView(runtime: runtime, inheritFrom: source, context: GHOSTTY_SURFACE_CONTEXT_SPLIT)
        tab.split(source, direction: direction, adding: view, equalizing: autoEqualizeSplits)
        onChange?()
    }

    func move(from source: Int, to destination: Int) {
        list.move(from: source, to: destination)
        onChange?()
    }

    func select(at index: Int) {
        list.select(at: index)
        onChange?()
    }

    func selectNext() {
        list.selectNext()
        onChange?()
    }

    func selectPrevious() {
        list.selectPrevious()
        onChange?()
    }

    func selectLast() {
        list.selectLast()
        onChange?()
    }

    func remove(_ tab: Tab) {
        guard let index = list.index(of: tab) else { return }
        let snapshot = tab.snapshot()
        recordClosed(.tab(ClosedTab(index: index, userTitle: tab.userTitle, tree: snapshot.tree, focusedIndex: snapshot.focusedIndex)))
        list.remove(tab)
        tab.views.forEach { $0.close() }
        onChange?()
    }

    var canUndo: Bool {
        dropExpired()
        return !closed.isEmpty
    }

    func paneRecord(closing view: TerminalView, in tab: Tab) -> ClosedPane {
        let snapshot = tab.snapshot()
        return ClosedPane(tab: tab, tree: snapshot.tree, closedIndex: tab.views.firstIndex { $0 === view } ?? 0)
    }

    func recordClosed(_ item: ClosedItem) {
        closed.append((Date(), item))
        if closed.count > Self.undoLimit { closed.removeFirst(closed.count - Self.undoLimit) }
    }

    // Entries that no longer fit the current layout are skipped in favour of older ones.
    @discardableResult
    func undoClose() -> Bool {
        dropExpired()
        while let entry = closed.popLast() {
            let restored = switch entry.item {
            case .tab(let record): restore(record)
            case .pane(let record): restore(record)
            }
            if restored {
                onChange?()
                return true
            }
        }
        return false
    }

    private func dropExpired() {
        let limit = runtime.undoTimeout
        closed.removeAll { Date().timeIntervalSince($0.date) > limit }
    }

    private func makeViews(from tree: SplitNode<PaneState>) -> SplitNode<TerminalView> {
        tree.map {
            $0.live ?? TerminalView(runtime: runtime, workingDirectory: $0.cwd, context: GHOSTTY_SURFACE_CONTEXT_TAB)
        }
    }

    private func restore(_ record: ClosedTab) -> Bool {
        let tree = record.tree.map {
            TerminalView(runtime: runtime, workingDirectory: $0.cwd, context: GHOSTTY_SURFACE_CONTEXT_TAB)
        }
        let leaves = tree.leaves
        let tab = Tab(tree: tree, focused: leaves[min(record.focusedIndex, leaves.count - 1)])
        tab.userTitle = record.userTitle
        list.insert(tab, at: record.index, select: true)
        return true
    }

    private func restore(_ record: ClosedPane) -> Bool {
        guard let tab = record.tab, list.index(of: tab) != nil else { return false }
        let survivors = record.tree.leaves.enumerated().filter { $0.offset != record.closedIndex }.map(\.element.live)
        guard survivors.count == tab.views.count, zip(survivors, tab.views).allSatisfy({ $0 === $1 }) else { return false }
        let tree = makeViews(from: record.tree)
        tab.replaceTree(tree, focused: tree.leaves[record.closedIndex])
        list.select(at: list.index(of: tab) ?? list.selectedIndex)
        return true
    }
}
