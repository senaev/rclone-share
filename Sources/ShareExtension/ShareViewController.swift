import AppKit
import UniformTypeIdentifiers

/// Share menu entry. It only collects the payload and the chosen destination,
/// then hands the work to the main app. It never runs rclone, because an app
/// extension is always sandboxed.
final class ShareViewController: NSViewController {

    private static let lastDestinationKey = "lastDestinationID"

    private let summaryLabel = NSTextField(wrappingLabelWithString: "Reading the selection…")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let destinationPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let uploadButton = NSButton(title: "Upload", target: nil, action: nil)

    private var payload: [URL] = []

    // MARK: - Layout

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 240))

        let title = NSTextField(labelWithString: "Upload to rclone")
        title.font = .boldSystemFont(ofSize: 15)
        title.frame = NSRect(x: 20, y: 200, width: 300, height: 22)
        root.addSubview(title)

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.frame = NSRect(x: 20, y: 152, width: 420, height: 40)
        root.addSubview(summaryLabel)

        let destinationTitle = NSTextField(labelWithString: "Destination")
        destinationTitle.frame = NSRect(x: 20, y: 114, width: 90, height: 20)
        root.addSubview(destinationTitle)

        destinationPicker.frame = NSRect(x: 112, y: 110, width: 328, height: 26)
        for destination in Destination.all {
            destinationPicker.addItem(withTitle: destination.displayName)
        }
        restoreLastDestination()
        root.addSubview(destinationPicker)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        statusLabel.frame = NSRect(x: 20, y: 58, width: 420, height: 44)
        root.addSubview(statusLabel)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.frame = NSRect(x: 250, y: 20, width: 90, height: 30)
        cancelButton.keyEquivalent = "\u{1b}"
        root.addSubview(cancelButton)

        uploadButton.target = self
        uploadButton.action = #selector(upload)
        uploadButton.frame = NSRect(x: 350, y: 20, width: 90, height: 30)
        uploadButton.keyEquivalent = "\r"
        uploadButton.isEnabled = false
        root.addSubview(uploadButton)

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        Log.shareExtension.info("Share Extension opened")

        resolveAttachments { [weak self] urls, error in
            guard let self else { return }
            if let error {
                Log.shareExtension.error("Could not resolve attachments: \(error, privacy: .public)")
                self.summaryLabel.stringValue = "—"
                self.statusLabel.stringValue = error
                self.uploadButton.isEnabled = false
                return
            }
            Log.shareExtension.info("Resolved \(urls.count) item(s)")
            self.payload = urls
            self.summaryLabel.stringValue = Self.summary(of: urls)
            self.uploadButton.isEnabled = !urls.isEmpty
        }
    }

    // MARK: - Actions

    @objc private func cancel() {
        let error = NSError(domain: UploadJob.urlScheme, code: 0, userInfo: nil)
        extensionContext?.cancelRequest(withError: error)
    }

    @objc private func upload() {
        let index = destinationPicker.indexOfSelectedItem
        guard index >= 0, index < Destination.all.count, !payload.isEmpty else { return }

        let destination = Destination.all[index]
        UserDefaults.standard.set(destination.id, forKey: Self.lastDestinationKey)

        let job = UploadJob(destinationID: destination.id, paths: payload.map(\.path))

        do {
            let url = try job.makeOpenURL()
            uploadButton.isEnabled = false
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = "Handing over to RcloneShare…"
            handOff(url)
        } catch {
            Log.shareExtension.error("Could not write the job: \(error.localizedDescription, privacy: .public)")
            show(error.localizedDescription)
        }
    }

    /// Launches the main app, which does the upload.
    ///
    /// `NSExtensionContext.open` reports failure for share extensions on macOS,
    /// so LaunchServices is asked directly. It also returns a real error, which
    /// is worth logging.
    private func handOff(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    Log.shareExtension.error(
                        "NSWorkspace.open failed: \(error.localizedDescription, privacy: .public)"
                    )
                    self.fallBack(to: url, after: error)
                    return
                }

                Log.shareExtension.info("Handed off to the app")
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    private func fallBack(to url: URL, after error: Error) {
        extensionContext?.open(url) { [weak self] opened in
            DispatchQueue.main.async {
                guard let self else { return }
                if opened {
                    Log.shareExtension.info("Handed off through the extension context")
                    self.extensionContext?.completeRequest(returningItems: nil)
                } else {
                    self.show("Could not start RcloneShare.\n\(error.localizedDescription)")
                }
            }
        }
    }

    private func show(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
        uploadButton.isEnabled = !payload.isEmpty
    }

    // MARK: - Attachments

    /// Turns the shared items into local file paths the main app can read.
    /// A file URL is used as is. Anything held in memory, such as an image or
    /// text, is written into the extension container first.
    private func resolveAttachments(completion: @escaping ([URL], String?) -> Void) {
        guard
            let items = extensionContext?.inputItems as? [NSExtensionItem],
            case let providers = items.flatMap({ $0.attachments ?? [] }),
            !providers.isEmpty
        else {
            completion([], "Nothing was shared.")
            return
        }

        // Index keeps the original order stable while loads finish out of order.
        var resolved: [Int: URL] = [:]
        let lock = NSLock()
        let group = DispatchGroup()

        for (index, provider) in providers.enumerated() {
            group.enter()
            load(provider) { url in
                if let url {
                    lock.lock()
                    resolved[index] = url
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = resolved.sorted { $0.key < $1.key }.map(\.value)
            completion(urls, urls.isEmpty ? "Could not read the shared items." : nil)
        }
    }

    private func load(_ provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        let fileURLType = UTType.fileURL.identifier

        if provider.hasItemConformingToTypeIdentifier(fileURLType) {
            // Preferred path: no copy, the app reads the original file.
            provider.loadItem(forTypeIdentifier: fileURLType) { item, _ in
                if let url = item as? URL {
                    completion(url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                guard let text = item as? String else {
                    completion(nil)
                    return
                }
                completion(Self.stage(Data(text.utf8), name: "\(Self.stamp()).txt"))
            }
            return
        }

        // Anything else, for example an image straight from the screenshot
        // thumbnail, is materialised through a file representation.
        guard let type = provider.registeredTypeIdentifiers.first else {
            completion(nil)
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
            guard let url, let data = try? Data(contentsOf: url) else {
                completion(nil)
                return
            }
            // The handed URL is deleted when this handler returns, so copy it.
            let name = provider.suggestedName ?? url.lastPathComponent
            completion(Self.stage(data, name: name))
        }
    }

    /// Writes data into the extension container and returns its path.
    private static func stage(_ data: Data, name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("payload-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(name)
            try data.write(to: target, options: .atomic)
            return target
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func restoreLastDestination() {
        let saved = UserDefaults.standard.string(forKey: Self.lastDestinationKey)
        if let saved, let index = Destination.all.firstIndex(where: { $0.id == saved }) {
            destinationPicker.selectItem(at: index)
        }
    }

    private static func summary(of urls: [URL]) -> String {
        switch urls.count {
        case 0: return "Nothing was shared."
        case 1: return urls[0].lastPathComponent
        default:
            let names = urls.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
            let extra = urls.count > 3 ? " and \(urls.count - 3) more" : ""
            return "\(urls.count) items: \(names)\(extra)\nThey go into one timestamped folder."
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}
