import AppKit
import GhosttyKit
import os

let log = Logger(subsystem: "dev.droppy.Droppy", category: "app")

struct PasteConfirmation {
    let text: String
    let contents: [(mime: String, data: Data)]
    let available: [String]
    let state: UnsafeMutableRawPointer
}

struct GhosttySettings: Equatable {
    var text = ""
}

// Only wakeup runs off the main thread; every other callback fires synchronously inside a call
// into libghostty, all of which happen on main. This wrapper only moves pointers into
// assumeIsolated without tripping the sending checker.
struct Handoff<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

enum CloseTabMode {
    case this, other, right
}

enum TerminalAction {
    case newTab
    case closeTab(CloseTabMode)
    case gotoTab(Int32)
    case moveTab(Int)
    case setTitle(String)
    case promptTitle
    case newSplit(SplitDirection)
    case gotoSplit(SplitFocusTarget)
    case resizeSplit(SplitDirection, UInt16)
    case equalizeSplits
    case toggleSplitZoom
    case quit
    case openConfig
    case reloadConfig
    case undo
    case redo
    case bell
    case notify(title: String, body: String)
    case commandFinished(exitCode: Int16, duration: UInt64)
    case progress(TabProgress?)
}

struct BellFeatures: OptionSet {
    let rawValue: UInt32
    static let system = BellFeatures(rawValue: 1 << 0)
    static let audio = BellFeatures(rawValue: 1 << 1)
    static let attention = BellFeatures(rawValue: 1 << 2)
    static let title = BellFeatures(rawValue: 1 << 3)
}

enum CommandFinishMode: String {
    case never, unfocused, always
}

struct CommandFinishActions: OptionSet {
    let rawValue: UInt32
    static let bell = CommandFinishActions(rawValue: 1 << 0)
    static let notify = CommandFinishActions(rawValue: 1 << 1)
}

enum GhosttyError: Error {
    case initFailed
    case configFailed
    case appFailed
}

@MainActor
final class GhosttyRuntime {
    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?
    private var observers: [NSObjectProtocol] = []

    var onCloseSurface: ((TerminalView, Bool) -> Void)?
    var onResizeKey: ((Bool) -> Void)?
    var onViewFocused: ((TerminalView) -> Void)?
    var onConfigChange: (() -> Void)?
    var onConfirmPaste: ((TerminalView, PasteConfirmation) -> Void)?
    private(set) var diagnostics: [String] = []
    var onAction: ((TerminalAction, TerminalView?) -> Bool)?

    var undoTimeout: TimeInterval {
        var milliseconds: UInt = 0
        let key = "undo-timeout"
        guard let config, ghostty_config_get(config, &milliseconds, key, UInt(key.utf8.count)) else { return 5 }
        return TimeInterval(milliseconds) / 1000
    }

    var scrollbarHidden: Bool {
        var name: UnsafePointer<CChar>?
        let key = "scrollbar"
        guard let config, ghostty_config_get(config, &name, key, UInt(key.utf8.count)), let name else { return false }
        return String(cString: name) == "never"
    }

    var bellFeatures: BellFeatures {
        var bits: UInt32 = 0
        let key = "bell-features"
        guard let config, ghostty_config_get(config, &bits, key, UInt(key.utf8.count)) else { return [.attention, .title] }
        return BellFeatures(rawValue: bits)
    }

    var commandFinishMode: CommandFinishMode {
        var name: UnsafePointer<CChar>?
        let key = "notify-on-command-finish"
        guard let config, ghostty_config_get(config, &name, key, UInt(key.utf8.count)), let name else { return .never }
        return CommandFinishMode(rawValue: String(cString: name)) ?? .never
    }

    var commandFinishActions: CommandFinishActions {
        var bits: UInt32 = 0
        let key = "notify-on-command-finish-action"
        guard let config, ghostty_config_get(config, &bits, key, UInt(key.utf8.count)) else { return .bell }
        return CommandFinishActions(rawValue: bits)
    }

    private var bellAudioPath: String? {
        var path = ghostty_config_path_s()
        let key = "bell-audio-path"
        guard let config, ghostty_config_get(config, &path, key, UInt(key.utf8.count)), let raw = path.path else { return nil }
        return (String(cString: raw) as NSString).expandingTildeInPath
    }

    private var bellAudioVolume: Float {
        var volume = 0.5
        let key = "bell-audio-volume"
        guard let config, ghostty_config_get(config, &volume, key, UInt(key.utf8.count)) else { return 0.5 }
        return Float(min(max(volume, 0), 1))
    }

    private var bellSound: NSSound?

    func playBell(_ features: BellFeatures) {
        if features.contains(.audio), let path = bellAudioPath, let sound = NSSound(contentsOfFile: path, byReference: true) {
            sound.volume = bellAudioVolume
            bellSound = sound
            sound.play()
        } else if features.contains(.system) || features.contains(.audio) {
            NSSound.beep()
        }
    }

    var backgroundOpacity: CGFloat {
        var opacity = 1.0
        guard let config, ghostty_config_get(config, &opacity, "background-opacity", 18) else { return 1 }
        return CGFloat(min(max(opacity, 0), 1))
    }

    // Nil when unset. The core stores no alpha for it, so only the three channels apply.
    var splitDividerColor: NSColor? {
        var color = ghostty_config_color_s()
        let key = "split-divider-color"
        guard let config, ghostty_config_get(config, &color, key, UInt(key.utf8.count)) else { return nil }
        return NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1)
    }

    var foregroundColor: NSColor {
        var color = ghostty_config_color_s()
        guard let config, ghostty_config_get(config, &color, "foreground", 10) else { return .white }
        return NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1)
    }

    var backgroundColor: NSColor {
        var color = ghostty_config_color_s()
        guard let config, ghostty_config_get(config, &color, "background", 10) else { return .black }
        return NSColor(
            srgbRed: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
        )
    }

    init(settings: GhosttySettings) throws {
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            throw GhosttyError.initFailed
        }
        guard let config = Self.makeConfig(settings) else { throw GhosttyError.configFailed }
        self.config = config
        diagnostics = Self.diagnostics(of: config)

        var runtime = Self.runtimeConfig(userdata: Unmanaged.passUnretained(self).toOpaque())
        guard let app = ghostty_app_new(&runtime, config) else { throw GhosttyError.appFailed }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setFocus(true) }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.setFocus(false) }
        })
        observers.append(center.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if let app = self?.app { ghostty_app_keyboard_changed(app) }
            }
        })
    }

    // Droppy's file is the only source: nothing under ~/.config/ghostty or Application Support is read.
    private static func makeConfig(_ settings: GhosttySettings) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        if let path = writeFile(defaultKeybinds, name: "defaults") {
            ghostty_config_load_file(config, path)
        }
        if !settings.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let path = writeFile(settings.text, name: "config") {
            ghostty_config_load_file(config, path)
        }
        ghostty_config_finalize(config)
        return config
    }

    // Loaded before the user's file so its keybinds win; a separate file keeps the user's line numbers intact.
    private static let defaultKeybinds = """
    keybind = cmd+alt+left=move_tab:-1
    keybind = cmd+alt+right=move_tab:1
    keybind = cmd+alt+up=unbind
    keybind = cmd+alt+down=unbind
    keybind = cmd+shift+left=goto_split:left
    keybind = cmd+shift+right=goto_split:right
    keybind = cmd+shift+up=goto_split:up
    keybind = cmd+shift+down=goto_split:down
    """

    // The C API only loads files. Keeping the user's line numbers makes Ghostty's diagnostics point at the real file.
    private static func writeFile(_ text: String, name: String) -> String? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dev.droppy.Droppy", isDirectory: true)
        let url = directory.appendingPathComponent("\(name)-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            log.error("cannot write ghostty config: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func diagnostics(of config: ghostty_config_t) -> [String] {
        (0..<ghostty_config_diagnostics_count(config)).compactMap { index in
            let diagnostic = ghostty_config_get_diagnostic(config, index)
            guard let message = diagnostic.message else { return nil }
            let text = String(cString: message)
            log.error("ghostty config: \(text, privacy: .public)")
            return text
        }
    }

    func reload(_ settings: GhosttySettings) {
        guard let app, let fresh = Self.makeConfig(settings) else { return }
        diagnostics = Self.diagnostics(of: fresh)
        ghostty_app_update_config(app, fresh)
        if let old = config { ghostty_config_free(old) }
        config = fresh
        onConfigChange?()
    }

    private func setFocus(_ focused: Bool) {
        if let app { ghostty_app_set_focus(app, focused) }
    }

    func tick() {
        if let app { ghostty_app_tick(app) }
    }

    // Closures formed in a main-actor context trap on entry when called from another thread,
    // and wakeup is invoked from Ghostty's IO and renderer threads.
    private nonisolated static func runtimeConfig(userdata: UnsafeMutableRawPointer) -> ghostty_runtime_config_s {
        ghostty_runtime_config_s(
            userdata: userdata,
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in GhosttyRuntime.wakeup(userdata) },
            action_cb: { app, target, action in GhosttyRuntime.action(app: app, target: target, action: action) },
            read_clipboard_cb: { userdata, location, state, mimes, count, list in
                GhosttyRuntime.readClipboard(userdata, location, state, mimes, count, list)
            },
            confirm_read_clipboard_cb: { userdata, confirm, state, request in
                GhosttyRuntime.confirmReadClipboard(userdata, confirm, state, request)
            },
            write_clipboard_cb: { _, location, contents, count, confirm in
                GhosttyRuntime.writeClipboard(location, contents, count, confirm)
            },
            close_surface_cb: { userdata, processAlive in GhosttyRuntime.closeSurface(userdata, processAlive: processAlive) }
        )
    }

    // The runtime is owned by the app delegate for the whole process, so this pointer never dangles.
    private nonisolated static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let address = UInt(bitPattern: userdata)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
                Unmanaged<GhosttyRuntime>.fromOpaque(pointer).takeUnretainedValue().tick()
            }
        }
    }

    private nonisolated static func action(
        app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        guard let app, let runtimePointer = ghostty_app_userdata(app) else { return false }
        let surfacePointer = target.tag == GHOSTTY_TARGET_SURFACE
            ? ghostty_surface_userdata(target.target.surface)
            : nil
        let pointers = Handoff((runtimePointer, surfacePointer))

        return MainActor.assumeIsolated {
            let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(pointers.value.0).takeUnretainedValue()
            let view = pointers.value.1.map { Unmanaged<TerminalView>.fromOpaque($0).takeUnretainedValue() }
            switch action.tag {
            case GHOSTTY_ACTION_MOUSE_SHAPE:
                view?.setCursor(action.action.mouse_shape)
                return view != nil
            case GHOSTTY_ACTION_MOUSE_VISIBILITY:
                view?.setCursorHidden(action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN)
                return view != nil
            case GHOSTTY_ACTION_CELL_SIZE:
                view?.cellSize = NSSize(
                    width: CGFloat(action.action.cell_size.width),
                    height: CGFloat(action.action.cell_size.height)
                )
                return view != nil
            case GHOSTTY_ACTION_SCROLLBAR:
                let bar = action.action.scrollbar
                view?.scrollbarChanged(total: bar.total, offset: bar.offset, len: bar.len)
                return view != nil
            case GHOSTTY_ACTION_MOUSE_OVER_LINK:
                let link = action.action.mouse_over_link
                let url = link.url.map { String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: link.len), as: UTF8.self) } ?? ""
                view?.linkHovered(url)
                return view != nil
            case GHOSTTY_ACTION_NEW_TAB:
                return runtime.onAction?(.newTab, view) ?? false
            case GHOSTTY_ACTION_CLOSE_TAB:
                let mode: CloseTabMode = switch action.action.close_tab_mode {
                case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER: .other
                case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT: .right
                default: .this
                }
                return runtime.onAction?(.closeTab(mode), view) ?? false
            case GHOSTTY_ACTION_GOTO_TAB:
                return runtime.onAction?(.gotoTab(action.action.goto_tab.rawValue), view) ?? false
            case GHOSTTY_ACTION_MOVE_TAB:
                return runtime.onAction?(.moveTab(action.action.move_tab.amount), view) ?? false
            case GHOSTTY_ACTION_SET_TITLE:
                guard let title = action.action.set_title.title else { return false }
                return runtime.onAction?(.setTitle(String(cString: title)), view) ?? false
            case GHOSTTY_ACTION_PROMPT_TITLE:
                guard action.action.prompt_title != GHOSTTY_PROMPT_TITLE_WINDOW else { return false }
                return runtime.onAction?(.promptTitle, view) ?? false
            case GHOSTTY_ACTION_NEW_SPLIT:
                let direction: SplitDirection = switch action.action.new_split {
                case GHOSTTY_SPLIT_DIRECTION_LEFT: .left
                case GHOSTTY_SPLIT_DIRECTION_UP: .up
                case GHOSTTY_SPLIT_DIRECTION_DOWN: .down
                default: .right
                }
                return runtime.onAction?(.newSplit(direction), view) ?? false
            case GHOSTTY_ACTION_GOTO_SPLIT:
                let target: SplitFocusTarget = switch action.action.goto_split {
                case GHOSTTY_GOTO_SPLIT_PREVIOUS: .previous
                case GHOSTTY_GOTO_SPLIT_NEXT: .next
                case GHOSTTY_GOTO_SPLIT_UP: .direction(.up)
                case GHOSTTY_GOTO_SPLIT_DOWN: .direction(.down)
                case GHOSTTY_GOTO_SPLIT_LEFT: .direction(.left)
                default: .direction(.right)
                }
                return runtime.onAction?(.gotoSplit(target), view) ?? false
            case GHOSTTY_ACTION_RESIZE_SPLIT:
                let resize = action.action.resize_split
                let direction: SplitDirection = switch resize.direction {
                case GHOSTTY_RESIZE_SPLIT_UP: .up
                case GHOSTTY_RESIZE_SPLIT_DOWN: .down
                case GHOSTTY_RESIZE_SPLIT_LEFT: .left
                default: .right
                }
                return runtime.onAction?(.resizeSplit(direction, resize.amount), view) ?? false
            case GHOSTTY_ACTION_EQUALIZE_SPLITS:
                return runtime.onAction?(.equalizeSplits, view) ?? false
            case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
                return runtime.onAction?(.toggleSplitZoom, view) ?? false
            case GHOSTTY_ACTION_START_SEARCH:
                guard let view else { return false }
                let needle = action.action.start_search.needle.map { String(cString: $0) } ?? ""
                DispatchQueue.main.async { view.beginSearch(needle: needle) }
                return true
            case GHOSTTY_ACTION_END_SEARCH:
                guard let view else { return false }
                DispatchQueue.main.async { view.endSearch() }
                return true
            case GHOSTTY_ACTION_SEARCH_TOTAL:
                let total = action.action.search_total.total
                view?.searchTotalChanged(total >= 0 ? total : nil)
                return view != nil
            case GHOSTTY_ACTION_SEARCH_SELECTED:
                let selected = action.action.search_selected.selected
                view?.searchBar?.selected = selected >= 0 ? selected : nil
                return view != nil
            case GHOSTTY_ACTION_OPEN_URL:
                return LinkOpener.open(action.action.open_url)
            case GHOSTTY_ACTION_RELOAD_CONFIG:
                return runtime.onAction?(.reloadConfig, view) ?? false
            case GHOSTTY_ACTION_OPEN_CONFIG:
                return runtime.onAction?(.openConfig, view) ?? false
            case GHOSTTY_ACTION_PWD:
                guard let view, let pwd = action.action.pwd.pwd else { return false }
                view.pwd = String(cString: pwd)
                return true
            case GHOSTTY_ACTION_UNDO:
                return runtime.onAction?(.undo, view) ?? false
            case GHOSTTY_ACTION_REDO:
                return runtime.onAction?(.redo, view) ?? false
            case GHOSTTY_ACTION_SECURE_INPUT:
                SecureInput.shared.set(action.action.secure_input)
                return true
            case GHOSTTY_ACTION_RING_BELL:
                return runtime.onAction?(.bell, view) ?? false
            case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
                let notification = action.action.desktop_notification
                let title = notification.title.map { String(cString: $0) } ?? ""
                let body = notification.body.map { String(cString: $0) } ?? ""
                return runtime.onAction?(.notify(title: title, body: body), view) ?? false
            case GHOSTTY_ACTION_COMMAND_FINISHED:
                let finished = action.action.command_finished
                return runtime.onAction?(.commandFinished(exitCode: finished.exit_code, duration: finished.duration), view) ?? false
            case GHOSTTY_ACTION_PROGRESS_REPORT:
                let report = action.action.progress_report
                let percent = report.progress >= 0 ? Int(report.progress) : nil
                let progress: TabProgress? = switch report.state {
                case GHOSTTY_PROGRESS_STATE_SET: TabProgress(kind: .normal, percent: percent)
                case GHOSTTY_PROGRESS_STATE_ERROR: TabProgress(kind: .error, percent: percent)
                case GHOSTTY_PROGRESS_STATE_INDETERMINATE: TabProgress(kind: .indeterminate, percent: nil)
                case GHOSTTY_PROGRESS_STATE_PAUSE: TabProgress(kind: .paused, percent: percent)
                default: nil
                }
                return runtime.onAction?(.progress(progress), view) ?? false
            case GHOSTTY_ACTION_QUIT:
                return runtime.onAction?(.quit, view) ?? false
            default:
                return false
            }
        }
    }

    // The surface cannot be freed from inside its own callback, so the close is deferred; the
    // closure holds a strong reference, so a late run can never touch a freed view.
    private nonisolated static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
        guard let userdata else { return }
        let viewPointer = Handoff(userdata)
        MainActor.assumeIsolated {
            let view = Unmanaged<TerminalView>.fromOpaque(viewPointer.value).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { view.runtime?.onCloseSurface?(view, processAlive) }
            }
        }
    }

    private nonisolated static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        _ location: ghostty_clipboard_e,
        _ state: UnsafeMutableRawPointer?,
        _ mimes: UnsafePointer<UnsafePointer<CChar>?>?,
        _ count: Int,
        _ list: Bool
    ) -> ghostty_clipboard_read_result_e {
        guard let userdata, let state, location == GHOSTTY_CLIPBOARD_STANDARD else {
            return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED
        }
        let requestsText = list || (0..<count).contains { index in
            mimes?[index].map { String(cString: $0) == "text/plain" } ?? false
        }
        guard requestsText else { return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE }

        let viewPointer = Handoff(userdata), statePointer = Handoff(state)
        return MainActor.assumeIsolated {
            let view = Unmanaged<TerminalView>.fromOpaque(viewPointer.value).takeUnretainedValue()
            guard let surface = view.surface else { return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED }
            guard let text = NSPasteboard.general.string(forType: .string) else {
                return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE
            }
            complete(surface: surface, state: statePointer.value, text: text)
            return GHOSTTY_CLIPBOARD_READ_STARTED
        }
    }

    private static func complete(surface: ghostty_surface_t, state: UnsafeMutableRawPointer, text: String) {
        completeRequest(surface: surface, state: state, contents: [("text/plain", Data(text.utf8))], available: ["text/plain"], confirmed: false)
    }

    static func completeRequest(
        surface: ghostty_surface_t,
        state: UnsafeMutableRawPointer,
        contents: [(mime: String, data: Data)],
        available: [String],
        confirmed: Bool
    ) {
        var strings: [UnsafeMutablePointer<CChar>] = []
        var buffers: [UnsafeMutableRawPointer] = []
        defer {
            strings.forEach { free($0) }
            buffers.forEach { $0.deallocate() }
        }
        var items: [ghostty_clipboard_content_s] = []
        for entry in contents {
            guard let mime = strdup(entry.mime) else { continue }
            strings.append(mime)
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(entry.data.count, 1), alignment: 1)
            buffers.append(buffer)
            entry.data.withUnsafeBytes { source in
                if let base = source.baseAddress { buffer.copyMemory(from: base, byteCount: source.count) }
            }
            items.append(ghostty_clipboard_content_s(mime: mime, data: buffer.assumingMemoryBound(to: CChar.self), len: entry.data.count))
        }
        var names: [UnsafePointer<CChar>?] = available.compactMap { strdup($0) }.map { pointer in
            strings.append(pointer)
            return UnsafePointer(pointer)
        }
        items.withUnsafeBufferPointer { itemPointer in
            names.withUnsafeMutableBufferPointer { namePointer in
                var request = ghostty_clipboard_complete_s(
                    contents: itemPointer.baseAddress,
                    contents_len: itemPointer.count,
                    available: UnsafePointer(OpaquePointer(namePointer.baseAddress)),
                    available_len: namePointer.count,
                    confirmed: confirmed,
                    remember: false
                )
                ghostty_surface_complete_clipboard_request(surface, &request, state)
            }
        }
    }

    // The callback's pointers die when it returns, so everything the sheet needs is copied before it is shown.
    // Only an unsafe paste reaches the user; OSC 52 requests stay denied, as the core would otherwise let a
    // program read or replace the clipboard.
    private nonisolated static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        _ confirm: UnsafePointer<ghostty_clipboard_confirm_s>?,
        _ state: UnsafeMutableRawPointer?,
        _ request: ghostty_clipboard_request_e
    ) {
        guard let userdata, let state else { return }
        let viewPointer = Handoff(userdata), statePointer = Handoff(state), confirmPointer = Handoff(confirm)
        MainActor.assumeIsolated {
            let view = Unmanaged<TerminalView>.fromOpaque(viewPointer.value).takeUnretainedValue()
            guard let surface = view.surface else { return }
            guard request == GHOSTTY_CLIPBOARD_REQUEST_PASTE, let pending = confirmPointer.value?.pointee,
                  let handler = view.runtime?.onConfirmPaste else {
                ghostty_surface_deny_clipboard_request(surface, statePointer.value)
                return
            }
            var contents: [(mime: String, data: Data)] = []
            for index in 0..<pending.contents_len {
                guard let item = pending.contents?[index], let mime = item.mime else { continue }
                let data = item.len > 0 && item.data != nil ? Data(bytes: item.data!, count: item.len) : Data()
                contents.append((String(cString: mime), data))
            }
            var available: [String] = []
            for index in 0..<pending.available_len {
                if let name = pending.available?[index] { available.append(String(cString: name)) }
            }
            let text = contents.first { $0.mime == "text/plain" }.flatMap { String(data: $0.data, encoding: .utf8) } ?? ""
            handler(view, PasteConfirmation(text: text, contents: contents, available: available, state: statePointer.value))
        }
    }

    private nonisolated static func writeClipboard(
        _ location: ghostty_clipboard_e,
        _ contents: UnsafePointer<ghostty_clipboard_content_s>?,
        _ count: Int,
        _ confirm: Bool
    ) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD, !confirm, let contents else { return }
        for index in 0..<count {
            let item = contents[index]
            guard let mime = item.mime, String(cString: mime) == "text/plain", let data = item.data else { continue }
            let text = String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self), count: item.len), as: UTF8.self)
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            return
        }
    }
}
