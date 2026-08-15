import Foundation

/// User feedback through osascript, the same approach as the shell version this
/// app replaces. It needs no notification permission and no entitlement, which
/// matters while the build is only ad-hoc signed.
enum Notifier {
    static func notify(_ message: String, title: String = "RcloneShare") {
        run("display notification \(quoted(message)) with title \(quoted(title))")
    }

    static func alert(_ message: String, title: String = "RcloneShare upload failed") {
        run("display alert \(quoted(title)) message \(quoted(message)) as critical")
    }

    private static func run(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    /// AppleScript string literal. Backslashes must be escaped before quotes.
    private static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
