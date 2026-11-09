import AppKit

struct PaneLabel {
    var folder: String
    var process: String?
    var prefix = ""

    var plain: String { prefix + (process.map { "\($0) · \(folder)" } ?? folder) }

    func attributed(font: NSFont, color: NSColor) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        guard let process else { return NSAttributedString(string: prefix + folder, attributes: attrs) }
        let result = NSMutableAttributedString(string: prefix + process, attributes: attrs)
        let dotFont = NSFont.systemFont(ofSize: font.pointSize * 0.55)
        result.append(NSAttributedString(string: " ", attributes: attrs))
        result.append(NSAttributedString(string: "●", attributes: [
            .font: dotFont,
            .foregroundColor: NSColor.controlAccentColor,
            .baselineOffset: (font.capHeight - dotFont.capHeight) / 2,
        ]))
        result.append(NSAttributedString(string: " \(folder)", attributes: attrs))
        return result
    }
}

@MainActor
final class PaneTitleView: NSView {
    static let margin: CGFloat = 6
    static let height: CGFloat = 20

    private let label = NSTextField(labelWithString: "")
    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let color = NSColor.white.withAlphaComponent(0.9)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = Self.height / 2
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ text: PaneLabel?, in bounds: NSRect, avoiding scrollbar: CGFloat) {
        guard let text else {
            isHidden = true
            return
        }
        label.attributedStringValue = text.attributed(font: Self.font, color: Self.color)
        let leading: CGFloat = 10
        let maxWidth = max(bounds.width - scrollbar - 2 * Self.margin, 0)
        let textSize = label.sizeThatFits(NSSize(width: maxWidth, height: Self.height))
        let width = min(textSize.width + leading + 10, maxWidth)
        label.frame = NSRect(x: leading, y: (Self.height - textSize.height) / 2, width: max(width - leading - 10, 0), height: textSize.height)
        frame = NSRect(
            x: bounds.maxX - scrollbar - Self.margin - width,
            y: bounds.maxY - Self.margin - Self.height,
            width: width,
            height: Self.height
        )
        isHidden = false
    }
}
