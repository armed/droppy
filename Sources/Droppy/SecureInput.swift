import AppKit
import Carbon
import GhosttyKit

// Secure event input is process-global and every enable must be balanced by a disable, so the system state
// is derived from one `desired` value and flipped only when it differs from what was last applied.
@MainActor
final class SecureInput {
    static let shared = SecureInput()

    private(set) var requested = false
    var panelVisible = false { didSet { apply() } }
    private var applied = false
    private var observers: [NSObjectProtocol] = []

    private var desired: Bool { requested && panelVisible && NSApp.isActive }

    private init() {
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        }
    }

    func set(_ mode: ghostty_action_secure_input_e) {
        switch mode {
        case GHOSTTY_SECURE_INPUT_ON: requested = true
        case GHOSTTY_SECURE_INPUT_OFF: requested = false
        default: requested.toggle()
        }
        apply()
    }

    func toggle() { set(GHOSTTY_SECURE_INPUT_TOGGLE) }

    func shutdown() {
        requested = false
        apply()
    }

    private func apply() {
        guard applied != desired else { return }
        let status = applied ? DisableSecureEventInput() : EnableSecureEventInput()
        if status == noErr {
            applied = !applied
        } else {
            log.warning("secure input change failed: \(status, privacy: .public)")
        }
    }
}
