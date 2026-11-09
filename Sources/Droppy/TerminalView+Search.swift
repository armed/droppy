import AppKit
import GhosttyKit

extension TerminalView {
    var isSearchFieldFocused: Bool { searchBar?.isEditing ?? false }

    func beginSearch(needle: String) {
        guard surface != nil, let container = superview as? SplitContainerView else { return }
        if let bar = searchBar {
            if !needle.isEmpty {
                bar.needle = needle
                runSearch(needle)
            }
            bar.focus()
            return
        }
        let bar = SearchBarView(frame: NSRect(origin: .zero, size: SearchBarView.size))
        bar.onNeedle = { [weak self] in self?.needleChanged($0) }
        bar.onNavigate = { [weak self] in self?.navigateSearch(previous: $0) }
        bar.onClose = { [weak self] in self?.closeSearch() }
        bar.onFocus = { [weak self] in
            guard let self else { return }
            self.runtime?.onViewFocused?(self)
        }
        bar.onKeyEquivalent = { [weak self] in self?.performBindingKey($0) ?? false }
        searchBar = bar
        updatePaneTitle()
        container.addSubview(bar)
        container.relayout()
        if !needle.isEmpty {
            bar.needle = needle
            runSearch(needle)
        }
        bar.focus()
    }

    func closeSearch() {
        perform("end_search")
        endSearch()
    }

    func endSearch() {
        guard let bar = searchBar else { return }
        searchBar = nil
        updatePaneTitle()
        searchDebounce?.cancel()
        searchDebounce = nil
        if bar.isEditing { window?.makeFirstResponder(self) }
        bar.removeFromSuperview()
    }

    func navigateSearch(previous: Bool) {
        flushSearchDebounce()
        perform(previous ? "navigate_search:previous" : "navigate_search:next")
    }

    private func needleChanged(_ needle: String) {
        searchDebounce?.cancel()
        searchDebounce = nil
        if needle.isEmpty {
            searchBar?.total = nil
            searchBar?.selected = nil
        }
        // Short needles match nearly everywhere, so they wait for the typing to pause.
        if needle.isEmpty || needle.count >= 3 {
            runSearch(needle)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.searchDebounce = nil
                self?.runSearch(needle)
            }
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func flushSearchDebounce() {
        guard let work = searchDebounce, let needle = searchBar?.needle else { return }
        work.cancel()
        searchDebounce = nil
        runSearch(needle)
    }

    // The core reports matches but selects none until the first navigation. Selecting one right away, once per
    // needle, makes the counter read like a browser's. A selection the core drops later is left alone: restoring
    // it would scroll the viewport while the user may be reading scrollback. Total 0 is what the core reports
    // when the needle changes, so it re-arms this.
    func searchTotalChanged(_ total: Int?) {
        searchBar?.total = total
        guard let bar = searchBar else { return }
        guard let total, total > 0 else {
            searchAutoSelected = false
            return
        }
        guard bar.selected == nil, !searchAutoSelected else { return }
        searchAutoSelected = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.searchBar?.selected == nil else { return }
            self.perform("navigate_search:next")
        }
    }

    private func runSearch(_ needle: String) {
        searchAutoSelected = false
        perform("search:\(needle)")
    }
}
