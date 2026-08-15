import Foundation

/// How a public link is produced after an upload. Every remote needs its own
/// rule, so this is per destination and not a global setting.
enum LinkStrategy {
    /// `rclone link <path>` returns a public URL directly.
    case rcloneLink

    /// The workspace has public sharing disabled, so `rclone link` fails.
    /// The link is built from the item ID reported by `rclone lsjson --stat`.
    /// This works only because the landing folder is already shared with the
    /// intended audience.
    case googleDriveItemID
}

/// A hardcoded upload target. These become user-configurable later.
struct Destination: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// rclone remote name, as shown by `rclone listremotes`.
    let remote: String
    /// Folder on the remote that receives the uploads.
    let folder: String
    let linkStrategy: LinkStrategy

    static func == (lhs: Destination, rhs: Destination) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var remoteFolderPath: String { "\(remote):\(folder)" }

    func remotePath(_ relativePath: String) -> String {
        "\(remoteFolderPath)/\(relativePath)"
    }
}

extension Destination {
    /// `Shared from Mac` is shared with all@datadoghq.com as Viewers, which is
    /// what makes the ID based links readable by colleagues.
    static let googleDrive = Destination(
        id: "gdrive",
        displayName: "Google Drive",
        remote: "gdrive",
        folder: "Shared from Mac",
        linkStrategy: .googleDriveItemID
    )

    static let yandexDisk = Destination(
        id: "yadisk",
        displayName: "Yandex Disk",
        remote: "yadisk",
        folder: "_other",
        linkStrategy: .rcloneLink
    )

    static let all: [Destination] = [.googleDrive, .yandexDisk]

    static func named(_ id: String) -> Destination? {
        all.first { $0.id == id }
    }
}
