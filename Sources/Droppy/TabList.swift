struct TabList<Element: AnyObject> {
    private(set) var items: [Element] = []
    private(set) var selectedIndex = 0

    var isEmpty: Bool { items.isEmpty }
    var selected: Element? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }

    func index(of element: Element) -> Int? {
        items.firstIndex { $0 === element }
    }

    mutating func insertAfterSelected(_ element: Element) {
        let index = items.isEmpty ? 0 : selectedIndex + 1
        items.insert(element, at: index)
        selectedIndex = index
    }

    @discardableResult
    mutating func remove(_ element: Element) -> Bool {
        guard let index = index(of: element) else { return false }
        items.remove(at: index)
        if index < selectedIndex {
            selectedIndex -= 1
        } else if index == selectedIndex {
            selectedIndex = max(0, min(index, items.count - 1))
        }
        return true
    }

    mutating func select(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    mutating func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    mutating func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + items.count - 1) % items.count
    }

    mutating func selectLast() {
        selectedIndex = max(0, items.count - 1)
    }
}
