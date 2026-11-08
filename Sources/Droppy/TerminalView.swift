import AppKit
import Carbon.HIToolbox
import GhosttyKit

@MainActor
final class TerminalView: NSView {
    private(set) var surface: ghostty_surface_t?
    weak var runtime: GhosttyRuntime?
    var willClose: (() -> Void)?

    var cellSize: NSSize = .zero
    private var cursor: NSCursor = .arrow

    var markedText = NSMutableAttributedString()
    var keyTextAccumulator: [String]?
    private var focused = false

    let id = UUID()
    var bell = false
    var progress: TabProgress?
    var title = ""
    var pwd: String?

    let scrollbar = ScrollbarView()
    let linkStatus = LinkStatusView()

    var searchBar: SearchBarView?
    var searchDebounce: DispatchWorkItem?
    var searchAutoSelected = false

    init(
        runtime: GhosttyRuntime,
        inheritFrom source: TerminalView? = nil,
        workingDirectory: String? = nil,
        context: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_WINDOW
    ) {
        self.runtime = runtime
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 400))

        guard let app = runtime.app else { return }
        var config: ghostty_surface_config_s
        if let sourceSurface = source?.surface {
            config = ghostty_surface_inherited_config(sourceSurface, context)
        } else {
            config = ghostty_surface_config_new()
            config.context = context
        }
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        if let workingDirectory {
            surface = workingDirectory.withCString { path in
                config.working_directory = path
                return ghostty_surface_new(app, &config)
            }
        } else {
            surface = ghostty_surface_new(app, &config)
        }
        if surface == nil { log.error("ghostty_surface_new failed") }
        scrollbar.isHidden = true
        scrollbar.onScrollToRow = { [weak self] in self?.perform("scroll_to_row:\($0)") }
        addSubview(scrollbar)
        addSubview(linkStatus)
        updateTrackingAreas()
        registerForDrops()
    }

    func scrollbarChanged(total: UInt64, offset: UInt64, len: UInt64) {
        scrollbar.update(total: total, offset: offset, len: len)
        scrollbar.isHidden = scrollbar.isHidden || runtime?.scrollbarHidden == true
    }

    func linkHovered(_ url: String) {
        linkStatus.show(url, maxWidth: bounds.width)
        linkStatus.frame.origin = .zero
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var needsConfirmClose: Bool {
        guard let surface else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    func close() {
        willClose?()
        willClose = nil
        endSearch()
        guard let surface else { return }
        self.surface = nil
        ghostty_surface_free(surface)
    }

    override var acceptsFirstResponder: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scrollbar.frame = NSRect(x: newSize.width - ScrollbarView.width, y: 0, width: ScrollbarView.width, height: newSize.height)
        syncSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncDisplay()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncDisplay()
    }

    // Ghostty replaces the view's layer with its own, so contentsScale must be driven from the window here.
    func syncDisplay() {
        guard let surface else { return }
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
            if let number = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                ghostty_surface_set_display_id(surface, number.uint32Value)
            }
        }
        let backing = convertToBacking(bounds)
        if bounds.width > 0, bounds.height > 0 {
            ghostty_surface_set_content_scale(
                surface,
                backing.width / bounds.width,
                backing.height / bounds.height
            )
        }
        syncSize()
    }

    private func syncSize() {
        guard let surface else { return }
        let backing = convertToBacking(bounds.size)
        guard backing.width > 0, backing.height > 0 else { return }
        ghostty_surface_set_size(surface, UInt32(backing.width), UInt32(backing.height))
    }

    func setVisible(_ visible: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, visible)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            setFocused(true)
            runtime?.onViewFocused?(self)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { setFocused(false) }
        return accepted
    }

    private func setFocused(_ value: Bool) {
        guard let surface, focused != value else { return }
        focused = value
        ghostty_surface_set_focus(surface, value)
    }

    func setCursor(_ shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_TEXT, GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: cursor = .iBeam
        case GHOSTTY_MOUSE_SHAPE_POINTER: cursor = .pointingHand
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: cursor = .crosshair
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: cursor = .operationNotAllowed
        case GHOSTTY_MOUSE_SHAPE_GRAB: cursor = .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING: cursor = .closedHand
        case GHOSTTY_MOUSE_SHAPE_COL_RESIZE, GHOSTTY_MOUSE_SHAPE_EW_RESIZE: cursor = .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_ROW_RESIZE, GHOSTTY_MOUSE_SHAPE_NS_RESIZE: cursor = .resizeUpDown
        default: cursor = .arrow
        }
        window?.invalidateCursorRects(for: self)
    }

    func setCursorHidden(_ hidden: Bool) {
        NSCursor.setHiddenUntilMouseMoves(hidden)
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: cursor)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: frame,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        sendButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, event)
    }

    override func mouseUp(with event: NSEvent) {
        sendButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if !sendButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, event) { super.rightMouseDown(with: event) }
    }

    override func rightMouseUp(with event: NSEvent) {
        if !sendButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, event) { super.rightMouseUp(with: event) }
    }

    override func otherMouseDown(with event: NSEvent) {
        sendButton(GHOSTTY_MOUSE_PRESS, otherButton(event), event)
    }

    override func otherMouseUp(with event: NSEvent) {
        sendButton(GHOSTTY_MOUSE_RELEASE, otherButton(event), event)
    }

    @discardableResult
    private func sendButton(
        _ state: ghostty_input_mouse_state_e,
        _ button: ghostty_input_mouse_button_e,
        _ event: NSEvent
    ) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_mouse_button(surface, state, button, event.modifierFlags.ghosttyMods)
    }

    private func otherButton(_ event: NSEvent) -> ghostty_input_mouse_button_e {
        switch event.buttonNumber {
        case 2: GHOSTTY_MOUSE_MIDDLE
        case 3: GHOSTTY_MOUSE_FOUR
        case 4: GHOSTTY_MOUSE_FIVE
        case 5: GHOSTTY_MOUSE_SIX
        case 6: GHOSTTY_MOUSE_SEVEN
        case 7: GHOSTTY_MOUSE_EIGHT
        default: GHOSTTY_MOUSE_UNKNOWN
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        sendPosition(event)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface, NSEvent.pressedMouseButtons == 0 else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, event.modifierFlags.ghosttyMods)
    }

    override func mouseMoved(with event: NSEvent) { sendPosition(event) }
    override func mouseDragged(with event: NSEvent) { sendPosition(event) }
    override func rightMouseDragged(with event: NSEvent) { sendPosition(event) }
    override func otherMouseDragged(with event: NSEvent) { sendPosition(event) }

    private func sendPosition(_ event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, frame.height - point.y, event.modifierFlags.ghosttyMods)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        if precise {
            x *= 2
            y *= 2
        }
        // Layout mirrors ghostty's packed ScrollMods: bit 0 is precision, bits 1-3 the momentum phase.
        var mods: Int32 = precise ? 1 : 0
        mods |= Int32(momentum(event.momentumPhase).rawValue) << 1
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    private func momentum(_ phase: NSEvent.Phase) -> ghostty_input_mouse_momentum_e {
        switch phase {
        case .began: GHOSTTY_MOUSE_MOMENTUM_BEGAN
        case .stationary: GHOSTTY_MOUSE_MOMENTUM_STATIONARY
        case .changed: GHOSTTY_MOUSE_MOMENTUM_CHANGED
        case .ended: GHOSTTY_MOUSE_MOMENTUM_ENDED
        case .cancelled: GHOSTTY_MOUSE_MOMENTUM_CANCELLED
        case .mayBegin: GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
        default: GHOSTTY_MOUSE_MOMENTUM_NONE
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, focused else { return false }
        return performBindingKey(event)
    }

    func performBindingKey(_ event: NSEvent) -> Bool {
        guard let surface else { return false }
        if handleResizeKey(event) { return true }
        var ghosttyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        let isBinding = (event.characters ?? "").withCString { text in
            ghosttyEvent.text = text
            return ghostty_surface_key_is_binding(surface, ghosttyEvent, nil)
        }
        guard isBinding else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if handleResizeKey(event) { return }
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        let translationMods = NSEvent.ModifierFlags(
            ghosttyMods: ghostty_surface_key_translation_mods(surface, event.modifierFlags.ghosttyMods)
        )
        // Hidden modifier bits matter for dead keys, so only the four known flags are overridden.
        var effectiveMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationMods.contains(flag) {
                effectiveMods.insert(flag)
            } else {
                effectiveMods.remove(flag)
            }
        }

        // The original event must be reused when nothing changed or Korean input breaks.
        let translationEvent: NSEvent
        if effectiveMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: effectiveMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: effectiveMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let hadMarkedText = markedText.length > 0
        let layoutBefore = hadMarkedText ? nil : KeyboardLayout.id

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([translationEvent])

        // A layout switch means an input method took the key.
        if !hadMarkedText && layoutBefore != KeyboardLayout.id { return }

        syncPreedit(clearIfNeeded: hadMarkedText)

        // Keys that merely end or cancel composition must not be encoded as terminal input.
        let composing = markedText.length > 0 || hadMarkedText

        if let committed = keyTextAccumulator, !committed.isEmpty {
            for text in committed where !Self.isComposingControl(text, composing: composing) {
                _ = sendKey(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else if !Self.isComposingControl(event.characters, composing: composing) {
            _ = sendKey(
                action,
                event: event,
                translationEvent: translationEvent,
                text: translationEvent.ghosttyCharacters,
                composing: composing
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        if Self.resizeDirection(event) != nil { return }
        _ = sendKey(GHOSTTY_ACTION_RELEASE, event: event)
    }

    // Matched by physical key so the shortcut survives non-Latin layouts.
    private static func resizeDirection(_ event: NSEvent) -> Bool? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command else { return nil }
        switch Int(event.keyCode) {
        case kVK_ANSI_J: return true
        case kVK_ANSI_K: return false
        default: return nil
        }
    }

    private func handleResizeKey(_ event: NSEvent) -> Bool {
        guard let grow = Self.resizeDirection(event) else { return false }
        runtime?.onResizeKey?(grow)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        let modifier: UInt32
        switch event.keyCode {
        case 0x39: modifier = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: modifier = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: modifier = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: modifier = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: modifier = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }
        if hasMarkedText() { return }

        var action = GHOSTTY_ACTION_RELEASE
        if event.modifierFlags.ghosttyMods.rawValue & modifier != 0 {
            let raw = event.modifierFlags.rawValue
            // The right-hand variants are only a press when their own device bit is set.
            let sidePressed: Bool = switch event.keyCode {
            case 0x3C: raw & 0x4 != 0
            case 0x3E: raw & 0x2000 != 0
            case 0x3D: raw & 0x40 != 0
            case 0x36: raw & 0x10 != 0
            default: true
            }
            if sidePressed { action = GHOSTTY_ACTION_PRESS }
        }
        _ = sendKey(action, event: event)
    }

    private func sendKey(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }
        var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing
        if let text = text?.keyEventText {
            return text.withCString { pointer in
                keyEvent.text = pointer
                return ghostty_surface_key(surface, keyEvent)
            }
        }
        return ghostty_surface_key(surface, keyEvent)
    }

    func sendCommittedText(_ text: String) {
        guard let surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        text.withCString { pointer in
            keyEvent.text = pointer
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let string = markedText.string
            string.withCString { pointer in
                ghostty_surface_preedit(surface, pointer, UInt(string.utf8.count))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    private static func isComposingControl(_ text: String?, composing: Bool) -> Bool {
        guard composing, let scalars = text?.unicodeScalars, scalars.count == 1 else { return false }
        return scalars.first!.value < 0x20
    }

    @objc func copy(_ sender: Any?) { perform("copy_to_clipboard") }
    @objc func paste(_ sender: Any?) { perform("paste_from_clipboard") }

    func perform(_ action: String) {
        guard let surface else { return }
        _ = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }
}
