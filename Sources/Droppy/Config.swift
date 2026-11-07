import Carbon.HIToolbox
import Foundation

enum PanelAlignment {
    case start, center, end
}

struct Config: Equatable {
    var hotkey = HotKeyBinding.default
    var position = PanelEdge.top
    var alignment = PanelAlignment.center
    var width: CGFloat = 1.0
    var height: CGFloat = 0.4
    var tabBar = TabBarPosition.bottom
    var hideOnFocusLoss = true
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
}

enum ConfigParser {
    static let template = """
    # Droppy configuration. Lines are `key = value`; everything shown is the default.

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

    # Hide the panel when another window takes focus.
    # hide-on-focus-loss = true

    """

    static let widthRange: ClosedRange<CGFloat> = 0.2...1.0

    static func parse(_ text: String) -> ConfigParseResult {
        var result = ConfigParseResult()
        for (index, rawLine) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let number = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else {
                result.issues.append(ConfigIssue(line: number, message: "expected key = value"))
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var value = String(line[line.index(after: equals)...])
            if let comment = value.range(of: " #") ?? value.range(of: "\t#") { value = String(value[..<comment.lowerBound]) }
            value = value.trimmingCharacters(in: .whitespaces)
            if let message = apply(key: key, value: value, to: &result.config) {
                result.issues.append(ConfigIssue(line: number, message: message))
            } else if key == "hotkey" {
                result.hotkeyLine = number
            }
        }
        return result
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
        case "hide-on-focus-loss":
            guard let flag = ["true": true, "false": false][value.lowercased()] else { return "expected true or false" }
            config.hideOnFocusLoss = flag
        default:
            return "unknown key \(key)"
        }
        return nil
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
