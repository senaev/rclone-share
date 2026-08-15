import AppKit

/// Spike Share Extension. It only reports what macOS handed to it.
/// The goal is to prove that an ad-hoc signed `.appex` is registered and
/// activated from the Share menu and the screenshot Share button.
final class ShareViewController: NSViewController {

    private let infoLabel = NSTextField(wrappingLabelWithString: "Reading input…")

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 210))

        let title = NSTextField(labelWithString: "RcloneShare")
        title.font = .boldSystemFont(ofSize: 16)
        title.frame = NSRect(x: 20, y: 168, width: 300, height: 24)
        root.addSubview(title)

        infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        infoLabel.frame = NSRect(x: 20, y: 58, width: 420, height: 104)
        root.addSubview(infoLabel)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.frame = NSRect(x: 250, y: 16, width: 90, height: 30)
        root.addSubview(cancel)

        let done = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        done.frame = NSRect(x: 350, y: 16, width: 90, height: 30)
        done.keyEquivalent = "\r"
        root.addSubview(done)

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        infoLabel.stringValue = describeInput()
    }

    private func describeInput() -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
            return "No input items."
        }

        var lines: [String] = []
        for (index, item) in items.enumerated() {
            let attachments = item.attachments ?? []
            lines.append("item \(index): \(attachments.count) attachment(s)")
            for attachment in attachments {
                let types = attachment.registeredTypeIdentifiers.joined(separator: ", ")
                lines.append("  \(types)")
            }
        }
        return lines.joined(separator: "\n")
    }

    @objc private func cancelTapped() {
        let error = NSError(domain: "com.senaev.rclone-share", code: 0, userInfo: nil)
        extensionContext?.cancelRequest(withError: error)
    }

    @objc private func doneTapped() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
