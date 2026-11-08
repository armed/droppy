import AppKit

@MainActor
final class LinkStatusView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 4
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ url: String, maxWidth: CGFloat) {
        guard !url.isEmpty else {
            isHidden = true
            return
        }
        label.stringValue = url
        let size = label.sizeThatFits(NSSize(width: maxWidth - 12, height: 20))
        let width = min(size.width + 12, maxWidth)
        setFrameSize(NSSize(width: width, height: size.height + 4))
        label.frame = NSRect(x: 6, y: 2, width: width - 12, height: size.height)
        isHidden = false
    }
}
