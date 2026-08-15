import Foundation

struct UploadResult {
    let link: URL
    /// Name of the uploaded item, or of the batch folder for several items.
    let name: String
    let itemCount: Int
}

/// Uploads to a `Destination` and returns a shareable link.
/// The behaviour mirrors the Automator Quick Actions this app replaces.
struct Uploader {
    let rclone: Rclone

    init(rclone: Rclone = Rclone()) {
        self.rclone = rclone
    }

    /// Uploads files or folders. Several items go into one timestamped folder,
    /// and the returned link points at that folder.
    func upload(paths: [URL], to destination: Destination) throws -> UploadResult {
        guard !paths.isEmpty else {
            throw RcloneError(message: "Nothing was selected.")
        }

        if paths.count == 1 {
            let source = paths[0]
            let name = source.lastPathComponent
            let target = destination.remotePath(name)
            let isDirectory = Self.isDirectory(source)

            try copy(from: source, to: target, isDirectory: isDirectory)
            let link = try publicLink(for: target, isDirectory: isDirectory, to: destination)
            return UploadResult(link: link, name: name, itemCount: 1)
        }

        let batchName = Self.timestamp()
        let batchPath = destination.remotePath(batchName)
        try rclone.run(["mkdir", batchPath])

        for source in paths {
            let target = "\(batchPath)/\(source.lastPathComponent)"
            try copy(from: source, to: target, isDirectory: Self.isDirectory(source))
        }

        let link = try publicLink(for: batchPath, isDirectory: true, to: destination)
        return UploadResult(link: link, name: batchName, itemCount: paths.count)
    }

    /// Uploads typed text as a file, without touching the local disk.
    func upload(text: String, filename: String, to destination: Destination) throws -> UploadResult {
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw RcloneError(message: "The filename is empty.")
        }

        let target = destination.remotePath(name)
        try rclone.run(["rcat", target], standardInput: Data(text.utf8))
        let link = try publicLink(for: target, isDirectory: false, to: destination)
        return UploadResult(link: link, name: name, itemCount: 1)
    }

    // MARK: - Steps

    private func copy(from source: URL, to target: String, isDirectory: Bool) throws {
        // `copy` keeps a folder as a folder. `copyto` renames a single file.
        try rclone.run([isDirectory ? "copy" : "copyto", source.path, target])
    }

    private func publicLink(
        for remotePath: String,
        isDirectory: Bool,
        to destination: Destination
    ) throws -> URL {
        switch destination.linkStrategy {
        case .rcloneLink:
            let output = try rclone.run(["link", remotePath])
            guard output.hasPrefix("http"), let url = URL(string: output) else {
                throw RcloneError(
                    message: "The item uploaded, but no public link was returned:\n\n\(output)"
                )
            }
            return url

        case .googleDriveItemID:
            let id = try itemID(of: remotePath, isDirectory: isDirectory)
            let text = isDirectory
                ? "https://drive.google.com/drive/folders/\(id)"
                : "https://drive.google.com/file/d/\(id)/view"
            guard let url = URL(string: text) else {
                throw RcloneError(message: "Could not build a link from ID \(id).")
            }
            return url
        }
    }

    /// `lsjson --stat` reports an ID for files but not for directories, so a
    /// directory ID is read from its parent listing instead.
    private func itemID(of remotePath: String, isDirectory: Bool) throws -> String {
        if isDirectory {
            let (parent, name) = Self.split(remotePath)
            let json = try rclone.run(["lsjson", "--dirs-only", parent])
            guard
                let data = json.data(using: .utf8),
                let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                throw RcloneError(message: "Could not list \(parent) to find the folder ID.")
            }
            guard
                let entry = entries.first(where: { $0["Name"] as? String == name }),
                let id = entry["ID"] as? String,
                !id.isEmpty
            else {
                throw RcloneError(
                    message: "The folder uploaded, but no Google Drive ID was found for '\(name)'."
                )
            }
            return id
        }

        let json = try rclone.run(["lsjson", "--stat", remotePath])
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["ID"] as? String,
            !id.isEmpty
        else {
            throw RcloneError(
                message: "The file uploaded, but its Google Drive ID could not be found."
            )
        }
        return id
    }

    /// Splits `remote:folder/name` into `remote:folder` and `name`.
    private static func split(_ remotePath: String) -> (parent: String, name: String) {
        guard let slash = remotePath.lastIndex(of: "/") else {
            return (remotePath, "")
        }
        return (
            String(remotePath[remotePath.startIndex..<slash]),
            String(remotePath[remotePath.index(after: slash)...])
        )
    }

    // MARK: - Helpers

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Matches `date "+%Y-%m-%d_%H-%M-%S"` used by the shell version.
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}
