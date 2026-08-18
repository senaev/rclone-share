import Foundation

/// Hand-off payload from the Share Extension to the main app.
///
/// A sandboxed app extension cannot run rclone, and app groups need a team ID
/// that ad-hoc signing does not provide. So the extension writes this job into
/// its own container tmp and opens a custom URL. Opening a URL needs no
/// entitlement, and the main app is not sandboxed, so it can read the paths.
struct UploadJob: Codable {
    let destinationID: String
    /// Absolute local paths. Either the originals selected by the user, or
    /// copies the extension had to materialise from in-memory attachments.
    let paths: [String]

    // MARK: - Transport

    /// Writes the job as JSON and returns the URL that launches the app.
    func makeOpenURL() throws -> URL {
        let jobURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("job-\(UUID().uuidString).json")

        try JSONEncoder().encode(self).write(to: jobURL, options: .atomic)

        var components = URLComponents()
        components.scheme = AppURL.scheme
        components.host = "upload"
        components.queryItems = [URLQueryItem(name: AppURL.jobQueryItem, value: jobURL.path)]

        guard let url = components.url else {
            throw RcloneError(message: "Could not build the hand-off URL.")
        }
        return url
    }

    /// Reads back a job written by `makeOpenURL()`.
    static func read(from jobFile: URL) throws -> UploadJob {
        let data = try Data(contentsOf: jobFile)
        return try JSONDecoder().decode(UploadJob.self, from: data)
    }
}
