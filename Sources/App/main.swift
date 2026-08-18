import AppKit

/// Menu bar app. It owns every rclone call, because the Share Extension is
/// sandboxed and cannot run a binary itself.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?
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
        Log.app.info("Login item status: \(LoginItem.describe(LoginItem.status))")
    }

    /// The checkmark is refreshed every time the menu opens, because the setting
    /// can also be changed in System Settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshLoginItem()
    }

    /// Entry point for every `rclone-share://` URL. The extension uses it to
    /// hand over an upload, and scripts can reach the other actions.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Log.app.info("Received \(url.absoluteString)")

            switch AppURL.route(url) {
            case .upload(let jobFile):
                upload(jobFile: jobFile)
            case .gist:
                showGist()
            case .loginItem(let enable):
                setLoginItem(enable)
            case nil:
                Log.app.error("Unsupported URL: \(url.absoluteString)")
            }
        }
    }

    // MARK: - Uploads

    private func upload(jobFile: URL) {
        uploadQueue.async { [uploader] in
            do {
                let job = try UploadJob.read(from: jobFile)
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

        let login = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        login.target = self
        menu.addItem(login)
        loginItem = login
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit RcloneShare",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLoginItem() {
        setLoginItem(!LoginItem.isEnabled)
    }

    private func setLoginItem(_ enable: Bool) {
        if let problem = LoginItem.set(enable) {
            Notifier.alert(problem)
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        loginItem?.state = LoginItem.isEnabled ? .on : .off
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
