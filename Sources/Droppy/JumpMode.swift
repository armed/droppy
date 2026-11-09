import AppKit
import Carbon.HIToolbox

@MainActor
final class JumpMode: PanelMode {
    private static let tabPool = Array("qwertyuiop")
    private static let panePool = Array("asdfghjklzxcvbnm")

    private unowned let host: PanelModeHost
    private var tab: Tab?
    private var tabs: [Character: Int] = [:]
    private var panes: [Character: TerminalView] = [:]

    private static let arrowKeys: [Int: SplitDirection] = [
        kVK_UpArrow: .up, kVK_DownArrow: .down, kVK_LeftArrow: .left, kVK_RightArrow: .right,
    ]

    init(host: PanelModeHost) {
        self.host = host
    }

    func enter() {
        refresh()
    }

    func leave() {
        host.setTabOverlays([:])
        tabs = [:]
        tab?.setPaneOverlays([])
        tab = nil
        panes = [:]
    }

    func refresh() {
        if tab !== host.selectedTab { tab?.setPaneOverlays([]) }
        tab = host.selectedTab
        tabs = Dictionary(uniqueKeysWithValues: zip(Self.tabPool, 0..<host.tabCount).map { ($0, $1) })
        host.setTabOverlays(Dictionary(uniqueKeysWithValues: tabs.map { ($1, TabJumpBadge(letter: String($0))) }))
        let assigned = zip(Self.panePool, tab?.panesByPosition ?? [])
        panes = Dictionary(uniqueKeysWithValues: assigned.map { ($0, $1) })
        updateBadges()
    }

    private func updateBadges() {
        guard let tab else { return }
        let overlays = panes.sorted { $0.key < $1.key }.map { letter, view in
            (view, JumpBadge(letter: String(letter), path: view.pwd, arrows: arrows(for: view)))
        }
        tab.setPaneOverlays(overlays)
    }

    private func arrows(for view: TerminalView) -> Set<SplitDirection> {
        guard let tab, view === tab.focusedView else { return [] }
        return Set([SplitDirection.up, .down, .left, .right].filter { tab.neighbor(of: view, $0) != nil })
    }

    func handleKey(_ event: NSEvent) -> ModeAction {
        let modifiers = event.significantModifiers.subtracting([.numericPad, .function])
        guard modifiers.isEmpty else { return .stay }
        if let direction = Self.arrowKeys[Int(event.keyCode)] {
            if let tab, tab.swapPane(tab.focusedView, toward: direction) {
                updateBadges()
            }
            return .stay
        }
        guard let letter = KeyboardLayout.latinLetters[Int(event.keyCode)] else { return .stay }
        if let index = tabs[letter] {
            host.selectTab(at: index)
        } else if let view = panes[letter] {
            return jump(to: view)
        }
        return .stay
    }

    func handleClick(on view: TerminalView) -> ModeAction {
        jump(to: view)
    }

    private func jump(to view: TerminalView) -> ModeAction {
        if tab?.focusedView === view { return .exit }
        host.focusPane(view)
        updateBadges()
        return .stay
    }
}

final class JumpBadge: NSView {
    init(letter: String, path: String?, arrows: Set<SplitDirection> = []) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer?.cornerRadius = 14

        let letterLabel = NSTextField(labelWithString: letter.uppercased())
        letterLabel.font = .systemFont(ofSize: 56, weight: .bold)
        letterLabel.textColor = .white
        var labels = [letterLabel]
        if let path {
            let pathLabel = NSTextField(labelWithString: (path as NSString).abbreviatingWithTildeInPath)
            pathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            pathLabel.textColor = NSColor.white.withAlphaComponent(0.85)
            pathLabel.lineBreakMode = .byTruncatingHead
            pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            labels.append(pathLabel)
        }
        let stack = NSStackView(views: labels)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        let arrowSize: CGFloat = 22
        func inset(_ base: CGFloat, _ direction: SplitDirection) -> CGFloat {
            arrows.contains(direction) ? base + arrowSize : base
        }
        stack.edgeInsets = NSEdgeInsets(
            top: inset(10, .up), left: inset(18, .left), bottom: inset(12, .down), right: inset(18, .right)
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let glyphs: [SplitDirection: String] = [.up: "▲", .down: "▼", .left: "◀", .right: "▶"]
        for direction in arrows {
            let arrow = NSTextField(labelWithString: glyphs[direction] ?? "")
            arrow.font = .systemFont(ofSize: 14, weight: .bold)
            arrow.textColor = .white
            arrow.translatesAutoresizingMaskIntoConstraints = false
            addSubview(arrow)
            switch direction {
            case .up, .down:
                arrow.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
                (direction == .up ? arrow.topAnchor.constraint(equalTo: topAnchor, constant: 4)
                    : arrow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)).isActive = true
            case .left, .right:
                arrow.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
                (direction == .left ? arrow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
                    : arrow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)).isActive = true
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class TabJumpBadge: NSView {
    init(letter: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer?.cornerRadius = 5

        let label = NSTextField(labelWithString: letter.uppercased())
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
