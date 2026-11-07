import GhosttyKit

@MainActor
final class TabManager {
    private let runtime: GhosttyRuntime
    private var list = TabList<Tab>()

    var onChange: (() -> Void)?

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
        tab.split(source, direction: direction, adding: view)
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
        guard list.remove(tab) else { return }
        tab.views.forEach { $0.close() }
        onChange?()
    }
}
