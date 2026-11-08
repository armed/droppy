import AppKit

enum TabBarPosition {
    case top, bottom
}

struct TabBarPalette {
    let bar: NSColor
    let selected: NSColor
    let text: NSColor
    let selectedText: NSColor

    init(terminalBackground: NSColor, opacity: CGFloat = 1) {
        let base = terminalBackground.usingColorSpace(.sRGB) ?? .black
        bar = (base.blended(withFraction: 0.35, of: .black) ?? .black).withAlphaComponent(opacity)
        selected = base.withAlphaComponent(opacity)
        let isDark = base.brightnessComponent < 0.5
        text = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.5)
        selectedText = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.92)
    }
}

final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var hovered = false { didSet { closeButton.isHidden = !hovered } }
    private var palette: TabBarPalette

    init(palette: TabBarPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        titleField.font = .systemFont(ofSize: 11.5)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .center
        addSubview(titleField)
        closeButton.title = "×"
        closeButton.font = .systemFont(ofSize: 14)
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(number: Int?, title: String, selected: Bool, palette: TabBarPalette) {
        self.palette = palette
        let color = selected ? palette.selectedText : palette.text
        let text = NSMutableAttributedString(string: title, attributes: [.foregroundColor: color])
        if let number {
            text.insert(
                NSAttributedString(string: "\(number) ", attributes: [.foregroundColor: palette.text.withAlphaComponent(0.35)]),
                at: 0
            )
        }
        titleField.attributedStringValue = text
        closeButton.contentTintColor = palette.text
        closeButton.attributedTitle = NSAttributedString(
            string: "×",
            attributes: [.foregroundColor: palette.text, .font: NSFont.systemFont(ofSize: 14)]
        )
        layer?.backgroundColor = (selected ? palette.selected : .clear).cgColor
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 22
        closeButton.frame = NSRect(x: 4, y: 0, width: 18, height: bounds.height)
        titleField.sizeToFit()
        let height = titleField.frame.height
        titleField.frame = NSRect(
            x: inset,
            y: (bounds.height - height) / 2,
            width: max(0, bounds.width - inset * 2),
            height: height
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    @objc private func closeClicked() {
        onClose?()
    }
}

final class TabBarView: NSView {
    static let height: CGFloat = 28
    private static let maxItemWidth: CGFloat = 240
    private static let plusWidth: CGFloat = 32

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?

    private var items: [TabItemView] = []
    private let plusButton = NSButton()
    private var palette = TabBarPalette(terminalBackground: .black)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        plusButton.isBordered = false
        plusButton.target = self
        plusButton.action = #selector(plusClicked)
        addSubview(plusButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(titles: [String], selected: Int, palette: TabBarPalette) {
        self.palette = palette
        layer?.backgroundColor = palette.bar.cgColor
        plusButton.attributedTitle = NSAttributedString(
            string: "+",
            attributes: [.foregroundColor: palette.text, .font: NSFont.systemFont(ofSize: 16)]
        )
        while items.count > titles.count { items.removeLast().removeFromSuperview() }
        while items.count < titles.count {
            let item = TabItemView(palette: palette)
            addSubview(item)
            items.append(item)
        }
        for (index, item) in items.enumerated() {
            item.configure(number: Self.shortcutNumber(at: index, count: titles.count), title: titles[index], selected: index == selected, palette: palette)
            item.onSelect = { [weak self] in self?.onSelect?(index) }
            item.onClose = { [weak self] in self?.onClose?(index) }
            item.needsLayout = true
        }
        needsLayout = true
    }

    // Ghostty binds cmd+1...8 to those tabs and cmd+9 to the last one, so with 9+ tabs only the last is reachable as 9.
    private static func shortcutNumber(at index: Int, count: Int) -> Int? {
        if index < 8 { return index + 1 }
        return index == count - 1 ? 9 : nil
    }

    override func layout() {
        super.layout()
        guard !items.isEmpty else { return }
        let available = bounds.width - Self.plusWidth
        let width = min(available / CGFloat(items.count), Self.maxItemWidth)
        for (index, item) in items.enumerated() {
            item.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        plusButton.frame = NSRect(x: width * CGFloat(items.count), y: 0, width: Self.plusWidth, height: bounds.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func plusClicked() {
        onNew?()
    }
}
