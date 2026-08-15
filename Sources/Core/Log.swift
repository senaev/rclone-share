import os

/// Unified logging so failures inside the sandboxed extension are visible.
///
///   log stream --predicate 'subsystem == "com.senaev.rclone-share"'
///   log show --last 10m --predicate 'subsystem == "com.senaev.rclone-share"'
enum Log {
    static let shareExtension = Logger(
        subsystem: "com.senaev.rclone-share",
        category: "share-extension"
    )

    static let app = Logger(
        subsystem: "com.senaev.rclone-share",
        category: "app"
    )
}
