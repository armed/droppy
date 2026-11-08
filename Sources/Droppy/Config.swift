import Carbon.HIToolbox
import Foundation

enum PanelAlignment {
    case start, center, end
}

struct PanelSides: OptionSet {
    let rawValue: Int
    static let top = PanelSides(rawValue: 1)
    static let bottom = PanelSides(rawValue: 2)
    static let left = PanelSides(rawValue: 4)
    static let right = PanelSides(rawValue: 8)
    static let all: PanelSides = [.top, .bottom, .left, .right]
}

struct PanelCorners: OptionSet {
    let rawValue: Int
    static let topLeft = PanelCorners(rawValue: 1)
    static let topRight = PanelCorners(rawValue: 2)
    static let bottomLeft = PanelCorners(rawValue: 4)
    static let bottomRight = PanelCorners(rawValue: 8)
    static let all: PanelCorners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RGBA: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

struct Config: Equatable {
    var hotkey = HotKeyBinding.default
    var position = PanelEdge.top
    var alignment = PanelAlignment.center
    var width: CGFloat = 1.0
    var height: CGFloat = 0.4
    var tabBar = TabBarPosition.bottom
    var hideOnFocusLoss = true
    var borderWidth: CGFloat = 1
    var borderSides = PanelSides.all
    // nil derives the colour from the terminal theme.
    var borderColor: RGBA?
    var cornerRadius: CGFloat = 0
    var cornerRadiusCorners = PanelCorners.all
    var opacity: Double = 1
    var shadow = true
    var animationDuration: TimeInterval = 0.2
    var autoEqualizeSplits = false
    var launchAtLogin = false
}

struct ConfigIssue: Equatable {
    var line: Int
    var message: String

    var summary: String { "Config line \(line): \(message)" }
}

struct ConfigParseResult {
    var config = Config()
    var issues: [ConfigIssue] = []
    var hotkeyLine: Int?
    // The file as Ghostty gets it: only the lines Droppy does not own, at their original line numbers.
    var ghosttyText = ""
}

enum ConfigParser {
    static let header = """
    # Droppy configuration. Lines are `key = value`; this file is the only configuration Droppy reads.
    # Splits can be equalized by hand with cmd+ctrl+=, or another trigger via `keybind = <trigger>=equalize_splits`.
    # Everything below is commented out at its default. The first section is Droppy's own;
    # every other key is passed to Ghostty's terminal core unchanged, see the reference section.

    # Global shortcut: modifiers (ctrl, opt, cmd, shift) and one key, joined by +.
    # hotkey = ctrl+grave

    # Screen edge the panel sticks to and slides from: top, bottom, left, right, center.
    # position = top

    # Placement along that edge when the panel does not fill it: start, center, end.
    # alignment = center

    # Panel size as a share of the screen's usable area.
    # width = 100%
    # height = 40%

    # Where the tab bar sits: bottom, top.
    # tab-bar = bottom

    # Hide the panel when another window takes focus. cmd+opt+p (toggle_window_float_on_top) overrides this until the config is reloaded.
    # hide-on-focus-loss = true

    # Line width in points; 0 turns the border off.
    # border-width = 1

    # Which sides carry the line: all, none, or a comma-separated list of top, bottom, left, right.
    # border-sides = all

    # auto derives a quiet colour from the terminal's own; or #rrggbb / #rrggbbaa.
    # border-color = auto

    # Corner rounding in points, 0 to 40; 0 keeps the corners square.
    # corner-radius = 0

    # Which corners are rounded: all, none, or a comma-separated list of top-left, top-right, bottom-left, bottom-right.
    # corner-radius-corners = all

    # Opacity of the whole panel, text and border included, 0.1 to 1.
    # opacity = 1

    # A drop shadow around the panel.
    # shadow = true

    # Seconds the panel takes to slide in and out, 0 to 2; 0 shows and hides it instantly.
    # animation-duration = 0.2

    # Equalize a tab's splits after each new split and after a pane closes.
    # auto-equalize-splits = false

    # Start Droppy when you log in, so the hotkey works right away.
    # launch-at-login = false


    """

    // The reference part is generated from Ghostty's documentation at build time.
    static var template: String {
        let generated = Bundle.main.url(forResource: "config", withExtension: "template")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return header + (generated ?? "")
    }

    static let ownedKeys: Set<String> = ["hotkey", "position", "alignment", "width", "height", "tab-bar", "hide-on-focus-loss",
                                       "border-width", "border-sides", "border-color", "corner-radius",
                                       "corner-radius-corners", "opacity", "shadow", "animation-duration",
                                       "auto-equalize-splits", "launch-at-login"]

    // Ghostty resolves relative paths against the file it loads, which for the forwarded copy would be the
    // temp directory, so the path-valued keys are made absolute against the real config directory.
    static let pathKeys: Set<String> = ["custom-shader", "background-image"]

    static let widthRange: ClosedRange<CGFloat> = 0.2...1.0

    static func parse(_ text: String, baseDirectory: String? = nil) -> ConfigParseResult {
        var result = ConfigParseResult()
        var forwarded: [String] = []
        for (index, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let number = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else {
                forwarded.append(line.isEmpty || line.hasPrefix("#") ? "" : line)
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard ownedKeys.contains(key) else {
                forwarded.append(forwardedLine(line, key: key, equals: equals, baseDirectory: baseDirectory))
                continue
            }
            forwarded.append("")
            // Trimmed first so a value that itself starts with # (a colour) is not taken for a comment.
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if let comment = value.range(of: " #") ?? value.range(of: "\t#") { value = String(value[..<comment.lowerBound]) }
            value = value.trimmingCharacters(in: .whitespaces)
            if let message = apply(key: key, value: value, to: &result.config) {
                result.issues.append(ConfigIssue(line: number, message: message))
            } else if key == "hotkey" {
                result.hotkeyLine = number
            }
        }
        result.ghosttyText = forwarded.joined(separator: "\n")
        return result
    }

    private static func forwardedLine(_ line: String, key: String, equals: String.Index, baseDirectory: String?) -> String {
        guard pathKeys.contains(key), let baseDirectory else { return line }
        var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        let optional = value.hasPrefix("?")
        if optional { value.removeFirst() }
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasPrefix("~") else { return line }
        return "\(key) = \(optional ? "?" : "")\(baseDirectory)/\(value)"
    }

    private static func apply(key: String, value: String, to config: inout Config) -> String? {
        switch key {
        case "hotkey":
            guard let binding = parseHotKey(value) else { return "invalid hotkey" }
            config.hotkey = binding
        case "position":
            guard let edge = ["top": PanelEdge.top, "bottom": .bottom, "left": .left, "right": .right, "center": .center][value.lowercased()]
            else { return "unknown position" }
            config.position = edge
        case "alignment":
            guard let alignment = ["start": PanelAlignment.start, "center": .center, "end": .end][value.lowercased()]
            else { return "unknown alignment" }
            config.alignment = alignment
        case "width":
            guard let fraction = parsePercent(value) else { return "invalid width" }
            config.width = min(max(fraction, widthRange.lowerBound), widthRange.upperBound)
        case "height":
            guard let fraction = parsePercent(value) else { return "invalid height" }
            config.height = min(max(fraction, PanelGeometry.heightRange.lowerBound), PanelGeometry.heightRange.upperBound)
        case "tab-bar":
            guard let position = ["top": TabBarPosition.top, "bottom": .bottom][value.lowercased()]
            else { return "unknown tab-bar position" }
            config.tabBar = position
        case "border-width":
            guard let width = Double(value), width.isFinite, (0...20).contains(width) else { return "invalid border-width" }
            config.borderWidth = CGFloat(width)
        case "border-sides":
            guard let sides = parseSides(value) else { return "invalid border-sides" }
            config.borderSides = sides
        case "border-color":
            if value.lowercased() == "auto" {
                config.borderColor = nil
            } else {
                guard let color = parseColor(value) else { return "invalid border-color" }
                config.borderColor = color
            }
        case "corner-radius":
            guard let radius = Double(value), radius.isFinite, (0...40).contains(radius) else { return "invalid corner-radius" }
            config.cornerRadius = CGFloat(radius)
        case "corner-radius-corners":
            guard let corners = parseCorners(value) else { return "invalid corner-radius-corners" }
            config.cornerRadiusCorners = corners
        case "opacity":
            guard let opacity = Double(value), opacity.isFinite, (0.1...1).contains(opacity) else { return "invalid opacity" }
            config.opacity = opacity
        case "shadow":
            guard let flag = ["true": true, "false": false][value.lowercased()] else { return "expected true or false" }
            config.shadow = flag
        case "auto-equalize-splits":
            guard let flag = ["true": true, "false": false][value.lowercased()] else { return "expected true or false" }
            config.autoEqualizeSplits = flag
        case "launch-at-login":
            guard let flag = ["true": true, "false": false][value.lowercased()] else { return "expected true or false" }
            config.launchAtLogin = flag
        case "animation-duration":
            guard let seconds = Double(value), seconds.isFinite, (0...2).contains(seconds) else { return "invalid animation-duration" }
            config.animationDuration = seconds
        case "hide-on-focus-loss":
            guard let flag = ["true": true, "false": false][value.lowercased()] else { return "expected true or false" }
            config.hideOnFocusLoss = flag
        default:
            return nil
        }
        return nil
    }

    static func parseSides(_ value: String) -> PanelSides? {
        switch value.lowercased() {
        case "all": return .all
        case "none": return []
        default: break
        }
        let names: [String: PanelSides] = ["top": .top, "bottom": .bottom, "left": .left, "right": .right]
        var sides: PanelSides = []
        for part in value.lowercased().split(separator: ",", omittingEmptySubsequences: false) {
            guard let side = names[part.trimmingCharacters(in: .whitespaces)] else { return nil }
            sides.insert(side)
        }
        return sides
    }

    static func parseCorners(_ value: String) -> PanelCorners? {
        switch value.lowercased() {
        case "all": return .all
        case "none": return []
        default: break
        }
        let names: [String: PanelCorners] = [
            "top-left": .topLeft, "top-right": .topRight, "bottom-left": .bottomLeft, "bottom-right": .bottomRight,
        ]
        var corners: PanelCorners = []
        for part in value.lowercased().split(separator: ",", omittingEmptySubsequences: false) {
            guard let corner = names[part.trimmingCharacters(in: .whitespaces)] else { return nil }
            corners.insert(corner)
        }
        return corners
    }

    static func parseColor(_ value: String) -> RGBA? {
        guard value.hasPrefix("#"), [7, 9].contains(value.count), let number = UInt64(value.dropFirst(), radix: 16) else { return nil }
        let hasAlpha = value.count == 9
        let channel = { (shift: UInt64) in Double((number >> shift) & 0xFF) / 255 }
        return hasAlpha
            ? RGBA(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
            : RGBA(red: channel(16), green: channel(8), blue: channel(0), alpha: 1)
    }

    static func parsePercent(_ value: String) -> CGFloat? {
        guard value.hasSuffix("%"), let number = Double(value.dropLast().trimmingCharacters(in: .whitespaces)),
              number.isFinite, number > 0 else { return nil }
        return CGFloat(number / 100)
    }

    static func parseHotKey(_ value: String) -> HotKeyBinding? {
        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        for part in value.lowercased().split(separator: "+", omittingEmptySubsequences: false) {
            let name = part.trimmingCharacters(in: .whitespaces)
            switch name {
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "opt", "option", "alt": modifiers |= UInt32(optionKey)
            case "cmd", "command", "super": modifiers |= UInt32(cmdKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default:
                guard keyCode == nil, let code = keyCodes[name] else { return nil }
                keyCode = code
            }
        }
        guard modifiers != 0, let keyCode else { return nil }
        return HotKeyBinding(keyCode: keyCode, carbonModifiers: modifiers)
    }

    private static let keyCodes: [String: UInt32] = {
        var table: [String: UInt32] = [:]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E),
            ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J),
            ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X), ("y", kVK_ANSI_Y),
            ("z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
            ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
            ("grave", kVK_ANSI_Grave), ("backtick", kVK_ANSI_Grave), ("minus", kVK_ANSI_Minus), ("equal", kVK_ANSI_Equal),
            ("leftbracket", kVK_ANSI_LeftBracket), ("rightbracket", kVK_ANSI_RightBracket),
            ("backslash", kVK_ANSI_Backslash), ("semicolon", kVK_ANSI_Semicolon), ("quote", kVK_ANSI_Quote),
            ("comma", kVK_ANSI_Comma), ("period", kVK_ANSI_Period), ("slash", kVK_ANSI_Slash),
            ("space", kVK_Space), ("tab", kVK_Tab), ("escape", kVK_Escape), ("esc", kVK_Escape),
            ("return", kVK_Return), ("enter", kVK_Return), ("delete", kVK_Delete), ("backspace", kVK_Delete),
            ("up", kVK_UpArrow), ("down", kVK_DownArrow), ("left", kVK_LeftArrow), ("right", kVK_RightArrow),
            ("home", kVK_Home), ("end", kVK_End), ("pageup", kVK_PageUp), ("pagedown", kVK_PageDown),
        ]
        for (name, code) in letters { table[name] = UInt32(code) }
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() { table["f\(index + 1)"] = UInt32(code) }
        return table
    }()
}
