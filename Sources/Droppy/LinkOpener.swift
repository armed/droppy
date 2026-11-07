import AppKit
import GhosttyKit
import UniformTypeIdentifiers

enum LinkOpener {
    static func open(_ action: ghostty_action_open_url_s) -> Bool {
        guard let pointer = action.url else { return false }
        let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: Int(action.len))
        let value = String(decoding: bytes, as: UTF8.self)
        switch action.kind {
        case GHOSTTY_ACTION_OPEN_URL_KIND_OSC8, GHOSTTY_ACTION_OPEN_URL_KIND_UNKNOWN:
            if let url = untrustedURL(value) {
                NSWorkspace.shared.open(url)
            } else {
                log.error("blocked link target")
            }
            // Reporting it handled stops the core from retrying with an unrestricted opener.
            return true
        default:
            openTrusted(trustedURL(value))
            return true
        }
    }

    // A match the user clicked in the terminal text: a URL, or a file path when it has no scheme.
    static func trustedURL(_ value: String) -> URL {
        if let candidate = URL(string: value), candidate.scheme != nil { return candidate }
        return URL(filePath: NSString(string: value).standardizingPath)
    }

    private static func openTrusted(_ url: URL) {
        let workspace = NSWorkspace.shared
        guard url.isFileURL else {
            workspace.open(url)
            return
        }
        let editor = workspace.urlForApplication(toOpen: url) ?? workspace.urlForApplication(toOpen: .plainText)
        guard let editor else {
            workspace.open(url)
            return
        }
        workspace.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    // OSC 8 targets are chosen by whatever program printed them, and a plain match may be a path. The policy
    // follows Ghostty's own app: web and mail links and non-executable local files open, everything else
    // (custom schemes, which Ghostty would ask about) is refused.
    static func untrustedURL(_ value: String) -> URL? {
        guard !value.isEmpty, !value.unicodeScalars.contains(where: isUnsafeScalar) else { return nil }
        let url: URL
        if let candidate = URL(string: value), candidate.scheme != nil {
            url = candidate
        } else {
            url = URL(filePath: NSString(string: value).standardizingPath)
        }
        switch url.scheme?.lowercased() {
        case "http", "https": return url.host?.isEmpty == false ? url : nil
        case "mailto": return url.path.isEmpty ? nil : url
        case "file": return safeFile(url)
        default: return nil
        }
    }

    private static func safeFile(_ url: URL) -> URL? {
        guard url.query == nil, url.fragment == nil else { return nil }
        if let host = url.host, !host.isEmpty, host.caseInsensitiveCompare("localhost") != .orderedSame { return nil }
        // Classified by the real target so a harmless-looking symlink cannot hide an executable.
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let values = try? target.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isExecutableKey, .isRegularFileKey]),
              values.isDirectory == true || values.isRegularFile == true else { return nil }
        if unsafeExtensions.contains(target.pathExtension.lowercased()) { return nil }
        if let type = values.contentType, [UTType.application, .executable, .script].contains(where: { type.conforms(to: $0) }) { return nil }
        if values.isDirectory != true, values.isExecutable == true { return nil }
        return target
    }

    private static let unsafeExtensions: Set<String> = [
        "action", "app", "applescript", "class", "command", "desktop", "inetloc", "jar", "mobileconfig", "mpkg",
        "pkg", "scpt", "terminal", "tool", "url", "webloc", "workflow",
    ]

    // Control, invisible and text-reversing characters can make the shown target differ from the opened one.
    private static func isUnsafeScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200B...0x200F, 0x202A...0x202E, 0x2028...0x2029, 0x2060, 0x2066...0x2069, 0xFEFF:
            true
        default:
            false
        }
    }
}
