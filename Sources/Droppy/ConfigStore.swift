import AppKit
import UniformTypeIdentifiers

@MainActor
final class ConfigStore {
    static var url: URL {
        let environment = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return base.appendingPathComponent("droppy/config")
    }

    private(set) var result = ConfigParseResult()
    var onChange: ((ConfigParseResult) -> Void)?

    private var lastText: String?
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounce: DispatchWorkItem?

    func load() {
        lastText = Self.readText()
        result = ConfigParser.parse(lastText ?? "", baseDirectory: Self.url.resolvingSymlinksInPath().deletingLastPathComponent().path)
        for issue in result.issues { log.error("\(issue.summary, privacy: .public)") }
    }

    func reload() {
        let text = Self.readText()
        guard text != lastText else { return }
        load()
        onChange?(result)
    }

    func forceReload() {
        lastText = nil
        reload()
        rearm()
    }

    // Editors replace the file atomically and dotfiles setups symlink it, so the directories on both sides
    // are watched along with the file itself, and everything is re-resolved after each event.
    func startWatching() {
        rearm()
    }

    private func rearm() {
        for source in sources { source.cancel() }
        sources = []
        let link = Self.url
        let target = link.resolvingSymlinksInPath()
        for path in Set([link.deletingLastPathComponent().path, target.deletingLastPathComponent().path, target.path]) {
            let descriptor = Darwin.open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .rename, .delete, .link],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    private func scheduleReload() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reload()
                self.rearm()
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private static func readText() -> String? {
        try? String(contentsOf: url.resolvingSymlinksInPath(), encoding: .utf8)
    }

    // A copy in the temp directory keeps the reference read-only and out of any dotfiles repository.
    func openReference() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("droppy-config-reference.txt")
        try? FileManager.default.removeItem(at: url)
        do {
            try ConfigParser.template.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        } catch {
            log.error("cannot write config reference: \(String(describing: error), privacy: .public)")
            return
        }
        openInTextEditor(url)
    }

    func openInEditor() {
        let url = Self.url
        if !FileManager.default.fileExists(atPath: url.resolvingSymlinksInPath().path) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try ConfigParser.template.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                log.error("cannot create config: \(String(describing: error), privacy: .public)")
                return
            }
            rearm()
        }
        openInTextEditor(url)
    }

    private func openInTextEditor(_ url: URL) {
        let workspace = NSWorkspace.shared
        if let editor = workspace.urlForApplication(toOpen: .plainText) {
            workspace.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(url)
        }
    }
}
