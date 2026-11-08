import AppKit
import GhosttyKit

extension TerminalView {
    func registerForDrops() {
        registerForDraggedTypes([.fileURL, .string])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let text: String
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            text = urls.map { Self.shellEscaped($0.path) }.joined(separator: " ")
        } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            text = string
        } else {
            return false
        }
        guard let surface else { return false }
        text.withCString { ghostty_surface_paste_text(surface, $0, UInt(text.utf8.count)) }
        window?.makeFirstResponder(self)
        return true
    }

    private static let shellSpecials = Set("\\ ()[]{}<>\"'`!#$&;|*?\t")

    static func shellEscaped(_ path: String) -> String {
        var result = ""
        for character in path {
            if shellSpecials.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
