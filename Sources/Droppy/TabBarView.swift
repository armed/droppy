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
    var onRename: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    private static let dragThreshold: CGFloat = 4
    private var pressX: CGFloat?
    private var dragging = false

    private static let font = NSFont.systemFont(ofSize: 11.5)
    private let titleField = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var hovered = false { didSet { closeButton.isHidden = !hovered } }
    private var palette: TabBarPalette
    private let progressLayer = CALayer()
    private var progress: TabProgress?

    init(palette: TabBarPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(progressLayer)
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

    func configure(number: Int?, label: PaneLabel, selected: Bool, progress: TabProgress?, palette: TabBarPalette) {
        self.palette = palette
        self.progress = progress
        let color = selected ? palette.selectedText : palette.text
        let text = NSMutableAttributedString(attributedString: label.attributed(font: Self.font, color: color))
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
        needsLayout = true
        updateProgress()
    }

    private func updateProgress() {
        progressLayer.isHidden = progress == nil
        guard let progress else { return }
        let color: NSColor = switch progress.kind {
        case .error: .systemRed
        case .paused: .systemYellow
        case .normal, .indeterminate: .controlAccentColor
        }
        progressLayer.backgroundColor = color.withAlphaComponent(progress.kind == .indeterminate ? 0.5 : 1).cgColor
        let fraction = progress.kind == .indeterminate ? 1 : CGFloat(progress.percent ?? 100) / 100
        progressLayer.frame = NSRect(x: 0, y: 0, width: bounds.width * min(max(fraction, 0), 1), height: 2)
    }

    override func layout() {
        super.layout()
        updateProgress()
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
        if event.clickCount == 2 { onRename?() }
        pressX = superviewX(of: event)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressX else { return }
        let x = superviewX(of: event)
        if !dragging {
            guard abs(x - pressX) >= Self.dragThreshold else { return }
            dragging = true
            onDragBegan?()
        }
        onDragMoved?(x)
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { onDragEnded?() }
        pressX = nil
        dragging = false
    }

    private func superviewX(of event: NSEvent) -> CGFloat {
        (superview ?? self).convert(event.locationInWindow, from: nil).x
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rename Tab…", action: #selector(renameClicked), keyEquivalent: "").target = self
        return menu
    }

    @objc private func renameClicked() {
        onRename?()
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
    var onRename: ((Int) -> Void)?
    var onMove: ((Int, Int) -> Void)?

    private struct Drag {
        let index: Int
        var grab: CGFloat?
        var x: CGFloat = 0
    }

    private var drag: Drag?
    private var overlays: [Int: NSView] = [:]
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

    func setTabOverlays(_ new: [Int: NSView]) {
        overlays.values.forEach { $0.removeFromSuperview() }
        overlays = new
        overlays.values.forEach(addSubview)
        needsLayout = true
    }

    func update(labels: [PaneLabel], tooltips: [String?], progress: [TabProgress?], selected: Int, palette: TabBarPalette) {
        self.palette = palette
        layer?.backgroundColor = palette.bar.cgColor
        plusButton.attributedTitle = NSAttributedString(
            string: "+",
            attributes: [.foregroundColor: palette.text, .font: NSFont.systemFont(ofSize: 16)]
        )
        while items.count > labels.count { items.removeLast().removeFromSuperview() }
        while items.count < labels.count {
            let item = TabItemView(palette: palette)
            addSubview(item)
            items.append(item)
        }
        for (index, item) in items.enumerated() {
            item.configure(number: Self.shortcutNumber(at: index, count: labels.count), label: labels[index], selected: index == selected, progress: progress[index], palette: palette)
            item.toolTip = tooltips[index]
            item.onSelect = { [weak self] in self?.onSelect?(index) }
            item.onClose = { [weak self] in self?.onClose?(index) }
            item.onRename = { [weak self] in self?.onRename?(index) }
            item.onDragBegan = { [weak self] in self?.beginDrag(index) }
            item.onDragMoved = { [weak self] in self?.dragMoved(to: $0) }
            item.onDragEnded = { [weak self] in self?.endDrag() }
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
        let target = dropIndex(itemWidth: width)
        for (index, item) in items.enumerated() {
            var slot = index
            if let drag, index != drag.index {
                if drag.index < index, index <= target { slot -= 1 }
                if target <= index, index < drag.index { slot += 1 }
            }
            var x = CGFloat(slot) * width
            if drag?.index == index { x = draggedX(itemWidth: width) }
            item.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
        }
        for (index, overlay) in overlays {
            guard items.indices.contains(index) else {
                overlay.isHidden = true
                continue
            }
            overlay.isHidden = false
            let size = overlay.fittingSize
            overlay.frame = NSRect(
                x: items[index].frame.minX + 4,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
        plusButton.frame = NSRect(x: width * CGFloat(items.count), y: 0, width: Self.plusWidth, height: bounds.height)
    }

    private var itemWidth: CGFloat {
        min((bounds.width - Self.plusWidth) / CGFloat(max(items.count, 1)), Self.maxItemWidth)
    }

    private func draggedX(itemWidth width: CGFloat) -> CGFloat {
        guard let drag else { return 0 }
        let maxX = width * CGFloat(items.count - 1)
        return min(max(drag.x - (drag.grab ?? 0), 0), maxX)
    }

    private func dropIndex(itemWidth width: CGFloat) -> Int {
        guard drag != nil, width > 0 else { return 0 }
        return min(max(Int((draggedX(itemWidth: width) / width).rounded()), 0), items.count - 1)
    }

    private func beginDrag(_ index: Int) {
        guard items.indices.contains(index) else { return }
        drag = Drag(index: index)
        items[index].layer?.zPosition = 1
    }

    private func dragMoved(to x: CGFloat) {
        guard var current = drag else { return }
        if current.grab == nil { current.grab = x - CGFloat(current.index) * itemWidth }
        current.x = x
        drag = current
        needsLayout = true
    }

    private func endDrag() {
        guard let current = drag else { return }
        let target = dropIndex(itemWidth: itemWidth)
        drag = nil
        items[current.index].layer?.zPosition = 0
        needsLayout = true
        if target != current.index { onMove?(current.index, target) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func plusClicked() {
        onNew?()
    }
}
