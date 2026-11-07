import Carbon.HIToolbox

struct HotKeyBinding: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_Grave),
        carbonModifiers: UInt32(controlKey)
    )
}

@MainActor
final class GlobalHotKey {
    private static let signature: OSType = 0x4452_5059
    private static var handlerInstalled = false
    private static var active: GlobalHotKey?

    private let handler: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @discardableResult
    func register(_ binding: HotKeyBinding) -> Bool {
        unregister()
        Self.installHandlerIfNeeded()
        Self.active = self
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if Self.active === self { Self.active = nil }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                MainActor.assumeIsolated { GlobalHotKey.active?.handler() }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
        handlerInstalled = true
    }
}
