import Foundation

struct RcloneError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Thin wrapper around the rclone binary.
struct Rclone {
    /// A GUI process does not inherit the shell PATH, so the path is absolute.
    static let defaultExecutable = URL(fileURLWithPath: "/opt/homebrew/bin/rclone")

    let executable: URL

    init(executable: URL = Rclone.defaultExecutable) {
        self.executable = executable
    }

    /// Runs rclone and returns trimmed standard output.
    /// Throws `RcloneError` with the standard error text when the exit code is not 0.
    @discardableResult
    func run(_ arguments: [String], standardInput: Data? = nil) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RcloneError(message: "rclone was not found at \(executable.path)")
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw RcloneError(message: "rclone could not start: \(error.localizedDescription)")
        }

        // Write stdin first, then drain both output pipes on background queues.
        // Draining concurrently avoids a deadlock when one pipe buffer fills up.
        if let standardInput {
            inputPipe.fileHandleForWriting.write(standardInput)
        }
        try? inputPipe.fileHandleForWriting.close()

        let collector = OutputCollector()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)

        group.enter()
        queue.async {
            collector.setOutput(outputPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        queue.async {
            collector.setError(errorPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        let output = collector.outputText
        guard process.terminationStatus == 0 else {
            let details = collector.errorText.isEmpty ? output : collector.errorText
            throw RcloneError(
                message: details.isEmpty
                    ? "rclone exited with code \(process.terminationStatus)"
                    : details
            )
        }
        return output
    }

    /// Remote names from the rclone config, without the trailing colon.
    func remoteNames() throws -> [String] {
        try run(["listremotes"])
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { name in name.hasSuffix(":") ? String(name.dropLast()) : name }
    }
}

/// Small lock-guarded box so the two reader queues do not race.
private final class OutputCollector {
    private let lock = NSLock()
    private var output = Data()
    private var error = Data()

    func setOutput(_ data: Data) {
        lock.lock()
        output = data
        lock.unlock()
    }

    func setError(_ data: Data) {
        lock.lock()
        error = data
        lock.unlock()
    }

    var outputText: String { text(of: \.output) }
    var errorText: String { text(of: \.error) }

    private func text(of keyPath: KeyPath<OutputCollector, Data>) -> String {
        lock.lock()
        let data = self[keyPath: keyPath]
        lock.unlock()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
