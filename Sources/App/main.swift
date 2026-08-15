import AppKit

/// Menu bar app. It owns every rclone call, because the Share Extension is
/// sandboxed and cannot run a binary itself.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let uploader = Uploader()
    private let uploadQueue = DispatchQueue(
        label: "com.senaev.rclone-share.upload",
        qos: .userInitiated
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
    }

    /// Entry point for `rclone-share://upload?job=…` sent by the extension.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handOff(url)
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
