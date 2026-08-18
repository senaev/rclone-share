import Foundation
import os

/// Logging that can be read without admin rights.
///
/// Unified logging alone is not enough here: `log show` and `log stream` refuse
/// to open the local store unless the caller is an admin, so every line also
/// goes to a file.
///
///   tail -f ~/Library/Logs/RcloneShare.log
///
/// The Share Extension is sandboxed, so its own lines land in the container:
///   ~/Library/Containers/com.senaev.rclone-share.shareext/Data/Library/Logs
struct AppLog {

    private static let subsystem = "com.senaev.rclone-share"
    private static let queue = DispatchQueue(label: "com.senaev.rclone-share.log")

    private let category: String
    private let logger: Logger

    init(category: String) {
        self.category = category
        self.logger = Logger(subsystem: Self.subsystem, category: category)
    }

    func info(_ message: String) { write("INFO ", message) }
    func warning(_ message: String) { write("WARN ", message) }
    func error(_ message: String) { write("ERROR", message) }

    private func write(_ level: String, _ message: String) {
        logger.log(level: .default, "\(message, privacy: .public)")
        Self.append("\(Self.stamp()) \(level) [\(category)] \(message)\n")
    }

    // MARK: - File

    static let fileURL: URL? = {
        guard let library = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return library.appendingPathComponent("Logs/RcloneShare.log")
    }()

    private static func append(_ line: String) {
        queue.async {
            guard let fileURL, let data = line.data(using: .utf8) else { return }

            let manager = FileManager.default
            if !manager.fileExists(atPath: fileURL.path) {
                try? manager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                manager.createFile(atPath: fileURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

enum Log {
    static let shareExtension = AppLog(category: "share-extension")
    static let app = AppLog(category: "app")
}
