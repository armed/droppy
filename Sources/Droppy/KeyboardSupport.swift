import AppKit
import Carbon.HIToolbox
import GhosttyKit

extension NSEvent.ModifierFlags {
    var ghosttyMods: ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        if rawValue & 0x4 != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if rawValue & 0x2000 != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if rawValue & 0x40 != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if rawValue & 0x10 != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
        return ghostty_input_mods_e(mods)
    }

    init(ghosttyMods mods: ghostty_input_mods_e) {
        self.init()
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { insert(.command) }
    }
}

extension NSEvent {
    func ghosttyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var event = ghostty_input_key_s()
        event.action = action
        event.keycode = UInt32(keyCode)
        event.text = nil
        event.composing = false
        event.mods = modifierFlags.ghosttyMods
        event.consumed_mods = (translationMods ?? modifierFlags)
            .subtracting([.control, .command])
            .ghosttyMods
        event.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp {
            // Non-Latin layouts map command+key to the Latin letter, but the bare key to their own script;
            // Ghostty's unicode shortcuts (cmd+t, cmd+shift+d, cmd+[) need the Latin one.
            let modifier: NSEvent.ModifierFlags = modifierFlags.contains(.command) ? .command : []
            if let scalar = characters(byApplyingModifiers: modifier)?.unicodeScalars.first {
                event.unshifted_codepoint = scalar.value
            }
        }
        return event
    }

    // Ghostty encodes control characters itself from the physical key, so they must not be sent as text.
    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return nil }
        }
        return characters
    }
}

extension String {
    var keyEventText: String? {
        guard let scalar = unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F else { return nil }
        return self
    }
}

enum KeyboardLayout {
    static var id: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
