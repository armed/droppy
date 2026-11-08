import AppKit

@MainActor
final class JumpMode: PanelMode {
    private static let tabPool = Array("qwertyuiop")
    private static let panePool = Array("asdfghjklzxcvbnm")

    private unowned let host: PanelModeHost
    private var tab: Tab?
    private var tabs: [Character: Int] = [:]
    private var panes: [Character: TerminalView] = [:]

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
        tab?.setPaneOverlays(assigned.map { ($1, JumpBadge(letter: String($0), path: $1.pwd)) })
    }

    func handleKey(_ event: NSEvent) -> ModeAction {
        guard event.significantModifiers.isEmpty,
              let letter = KeyboardLayout.latinLetters[Int(event.keyCode)] else { return .stay }
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
        return .stay
    }
}

final class JumpBadge: NSView {
    init(letter: String, path: String?) {
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
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 18, bottom: 12, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
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
