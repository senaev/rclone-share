import AppKit

/// Menu bar app. It owns every rclone call, because the Share Extension is
/// sandboxed and cannot run a binary itself.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var gistWindow: GistWindowController?
    private let uploader = Uploader()
    private let uploadQueue = DispatchQueue(
        label: "com.senaev.rclone-share.upload",
        qos: .userInitiated
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        setUpStatusItem()
        setUpGistHotkey()
    }

    /// Entry point for `rclone-share://upload?job=…` sent by the extension, and
    /// for `rclone-share://gist`, which opens the gist form.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Log.app.info("Received \(url.absoluteString)")
            if url.host == UploadJob.gistHost {
                showGist()
            } else {
                handOff(url)
            }
        }
    }

    // MARK: - Uploads

    private func handOff(_ url: URL) {
        uploadQueue.async { [uploader] in
            do {
                let (job, jobFile) = try UploadJob.read(from: url)
                defer { try? FileManager.default.removeItem(at: jobFile) }

                guard let destination = Destination.named(job.destinationID) else {
                    throw RcloneError(message: "Unknown destination '\(job.destinationID)'.")
                }

                let result = try uploader.upload(
                    paths: job.paths.map { URL(fileURLWithPath: $0) },
                    to: destination
                )
                Self.report(result, destination: destination)
            } catch {
                Notifier.alert(error.localizedDescription)
            }
        }
    }

    private func upload(text: String, filename: String, to destination: Destination) {
        uploadQueue.async { [uploader, weak self] in
            do {
                let result = try uploader.upload(
                    text: text,
                    filename: filename,
                    to: destination
                )
                Self.report(result, destination: destination)
            } catch {
                // The form is shown again, otherwise the typed text is lost.
                DispatchQueue.main.async {
                    self?.gistWindow?.restore(
                        text: text,
                        filename: filename,
                        error: error.localizedDescription
                    )
                }
            }
        }
    }

    private func upload(_ paths: [URL], to destination: Destination) {
        uploadQueue.async { [uploader] in
            do {
                let result = try uploader.upload(paths: paths, to: destination)
                Self.report(result, destination: destination)
            } catch {
                Notifier.alert(error.localizedDescription)
            }
        }
    }

    private static func report(_ result: UploadResult, destination: Destination) {
        let link = result.link.absoluteString
        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        }

        let what = result.itemCount == 1 ? result.name : "\(result.itemCount) items"
        Notifier.notify("\(what) → \(destination.displayName). Link copied.")
    }

    // MARK: - Gist

    private func setUpGistHotkey() {
        let registered = HotkeyCenter.shared.register(
            keyCode: HotkeyCenter.gistKeyCode,
            modifiers: HotkeyCenter.gistModifiers
        ) { [weak self] in
            self?.showGist()
        }

        if registered {
            Log.app.info("Registered the gist hotkey")
        } else {
            // Another app owns the combination. The menu bar entry still works.
            Notifier.notify("Could not claim ⌘⇧' — another app uses it.")
        }
    }

    @objc private func showGist() {
        Log.app.info("Opening the gist form")
        if gistWindow == nil {
            gistWindow = GistWindowController { [weak self] text, filename, destination in
                self?.upload(text: text, filename: filename, to: destination)
            }
        }
        gistWindow?.present()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "arrow.up.circle",
            accessibilityDescription: "RcloneShare"
        )

        let menu = NSMenu()
        for destination in Destination.all {
            let entry = NSMenuItem(
                title: "Upload to \(destination.displayName)…",
                action: #selector(chooseFiles(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = destination.id
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        let gist = NSMenuItem(
            title: "New Gist…",
            action: #selector(showGist),
            keyEquivalent: "'"
        )
        gist.keyEquivalentModifierMask = [.command, .shift]
        gist.target = self
        menu.addItem(gist)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit RcloneShare",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func chooseFiles(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? String,
            let destination = Destination.named(id)
        else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        panel.message = "Upload to \(destination.displayName)"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        upload(panel.urls, to: destination)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
