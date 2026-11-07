import AppKit
import Carbon.HIToolbox

final class SearchField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}

@MainActor
final class SearchBarView: NSVisualEffectView, NSTextFieldDelegate {
    static let size = NSSize(width: 250, height: 30)
    static let margin: CGFloat = 8
    private static let countWidth: CGFloat = 62

    var onNeedle: ((String) -> Void)?
    var onNavigate: ((_ previous: Bool) -> Void)?
    var onClose: (() -> Void)?
    var onFocus: (() -> Void)? {
        get { field.onFocus }
        set { field.onFocus = newValue }
    }
    // Keys with the command modifier that the terminal would act on (tabs, splits, search navigation).
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    var total: Int? { didSet { updateCount() } }
    var selected: Int? { didSet { updateCount() } }

    private let field = SearchField()
    private let count = NSTextField(labelWithString: "")

    var needle: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    var isEditing: Bool {
        guard let editor = field.currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .menu
        state = .active
        blendingMode = .withinWindow
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.zPosition = 500

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Search"
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.delegate = self
        addSubview(field)

        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        addSubview(count)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let fieldHeight: CGFloat = 18
        let inset = Self.margin
        field.frame = NSRect(
            x: inset, y: (bounds.height - fieldHeight) / 2,
            width: bounds.width - inset * 2 - Self.countWidth, height: fieldHeight
        )
        count.frame = NSRect(
            x: bounds.width - inset - Self.countWidth, y: (bounds.height - 14) / 2,
            width: Self.countWidth, height: 14
        )
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func updateCount() {
        switch (selected, total) {
        case (let selected?, let total?): count.stringValue = "\(selected + 1)/\(total)"
        case (let selected?, nil): count.stringValue = "\(selected + 1)/?"
        case (nil, let total?): count.stringValue = "-/\(total)"
        default: count.stringValue = ""
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        onNeedle?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            onNavigate?(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    // The app has no Edit menu, so the editing shortcuts are routed by physical key, which also covers
    // non-Latin layouts.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, isEditing, let editor = field.currentEditor() else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        guard mods.contains(.command) else { return false }
        if mods == .command {
            switch Int(event.keyCode) {
            case kVK_ANSI_A: editor.selectAll(nil); return true
            case kVK_ANSI_C: editor.copy(nil); return true
            case kVK_ANSI_V: editor.paste(nil); return true
            case kVK_ANSI_X: editor.cut(nil); return true
            case kVK_ANSI_Z: editor.undoManager?.undo(); return true
            default: break
            }
        } else if mods == [.command, .shift], Int(event.keyCode) == kVK_ANSI_Z {
            editor.undoManager?.redo()
            return true
        }
        return onKeyEquivalent?(event) ?? false
    }
}
