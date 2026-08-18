import AppKit

/// Form for sharing typed or pasted text. The text goes straight to the remote
/// through `rclone rcat`, so nothing is written to the local disk.
final class GistWindowController: NSWindowController {

    private let onSubmit: (_ text: String, _ filename: String, _ destination: Destination) -> Void

    private let filenameField = NSTextField()
    private let textView = NSTextView()
    private let destinationPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusLabel = NSTextField(labelWithString: "")

    private static let lastDestinationKey = "lastGistDestinationID"
    private static let hint = "⌘↩ to upload"

    init(onSubmit: @escaping (String, String, Destination) -> Void) {
        self.onSubmit = onSubmit

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "New Gist"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not loaded from a nib.")
    }

    // MARK: - Presenting

    /// Shows an empty form. The app is an accessory, so it has to activate
    /// itself before the text view can take keystrokes.
    func present() {
        filenameField.stringValue = Self.defaultFilename()
        textView.string = ""
        restoreLastDestination()
        showHint()
        focus()
    }

    /// Puts a failed submission back on screen so the text is not lost.
    func restore(text: String, filename: String, error: String) {
        filenameField.stringValue = filename
        textView.string = text
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = error
        focus()
    }

    private func focus() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
    }

    // MARK: - Actions

    @objc private func submit() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show(error: "The text is empty.")
            return
        }

        let filename = filenameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty else {
            show(error: "The name is empty.")
            return
        }

        guard let destination = Destination.all.first(
            where: { $0.displayName == destinationPicker.titleOfSelectedItem }
        ) else {
            show(error: "Pick a destination.")
            return
        }

        UserDefaults.standard.set(destination.id, forKey: Self.lastDestinationKey)
        window?.orderOut(nil)
        onSubmit(text, filename, destination)
    }

    @objc private func cancel() {
        window?.orderOut(nil)
    }

    private func show(error: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = error
    }

    private func showHint() {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = Self.hint
    }

    // MARK: - Layout

    private func build() {
        guard let window else { return }

        let nameLabel = NSTextField(labelWithString: "Name")
        filenameField.placeholderString = "snippet.txt"
        filenameField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        // Straight quotes and plain dashes matter when the text is code.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        textView.autoresizingMask = [.width]

        let destinationLabel = NSTextField(labelWithString: "Destination")
        for destination in Destination.all {
            destinationPicker.addItem(withTitle: destination.displayName)
        }

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"

        let uploadButton = NSButton(title: "Upload", target: self, action: #selector(submit))
        // Plain Return belongs to the text view, so the shortcut takes Command.
        uploadButton.keyEquivalent = "\r"
        uploadButton.keyEquivalentModifierMask = [.command]

        let root = NSView()
        let views = [
            nameLabel, filenameField, scrollView,
            destinationLabel, destinationPicker,
            statusLabel, cancelButton, uploadButton
        ]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        let margin: CGFloat = 20

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            nameLabel.centerYAnchor.constraint(equalTo: filenameField.centerYAnchor),

            filenameField.topAnchor.constraint(equalTo: root.topAnchor, constant: margin),
            filenameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 12),
            filenameField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),

            scrollView.topAnchor.constraint(equalTo: filenameField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            scrollView.bottomAnchor.constraint(equalTo: destinationPicker.topAnchor, constant: -16),

            destinationLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            destinationLabel.centerYAnchor.constraint(equalTo: destinationPicker.centerYAnchor),

            destinationPicker.leadingAnchor.constraint(
                equalTo: destinationLabel.trailingAnchor, constant: 12
            ),
            destinationPicker.widthAnchor.constraint(equalToConstant: 200),
            destinationPicker.bottomAnchor.constraint(
                equalTo: uploadButton.topAnchor, constant: -16
            ),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: margin),
            statusLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -12
            ),
            statusLabel.centerYAnchor.constraint(equalTo: uploadButton.centerYAnchor),

            uploadButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -margin),
            uploadButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -margin),
            uploadButton.widthAnchor.constraint(greaterThanOrEqualTo: cancelButton.widthAnchor),

            cancelButton.trailingAnchor.constraint(
                equalTo: uploadButton.leadingAnchor, constant: -12
            ),
            cancelButton.centerYAnchor.constraint(equalTo: uploadButton.centerYAnchor)
        ])

        window.contentView = root
        window.setContentSize(NSSize(width: 560, height: 420))
        window.minSize = NSSize(width: 420, height: 300)
    }

    // MARK: - State

    private func restoreLastDestination() {
        let stored = UserDefaults.standard.string(forKey: Self.lastDestinationKey)
        guard
            let stored,
            let destination = Destination.named(stored)
        else { return }
        destinationPicker.selectItem(withTitle: destination.displayName)
    }

    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "gist-\(formatter.string(from: Date())).txt"
    }
}
