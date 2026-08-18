import Foundation

/// Hand-off payload from the Share Extension to the main app.
///
/// A sandboxed app extension cannot run rclone, and app groups need a team ID
/// that ad-hoc signing does not provide. So the extension writes this job into
/// its own container tmp and opens a custom URL. Opening a URL needs no
/// entitlement, and the main app is not sandboxed, so it can read the paths.
struct UploadJob: Codable {
    static let urlScheme = "rclone-share"
    static let uploadHost = "upload"
    /// `rclone-share://gist` opens the gist form. It carries no payload and
    /// exists so the form can be opened by a script or another launcher.
    static let gistHost = "gist"
    static let jobQueryItem = "job"

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
        components.scheme = Self.urlScheme
        components.host = Self.uploadHost
        components.queryItems = [URLQueryItem(name: Self.jobQueryItem, value: jobURL.path)]

        guard let url = components.url else {
            throw RcloneError(message: "Could not build the hand-off URL.")
        }
        return url
    }

    /// Reads back a job from a URL produced by `makeOpenURL()`.
    static func read(from url: URL) throws -> (job: UploadJob, jobFile: URL) {
        guard
            url.scheme == urlScheme,
            url.host == uploadHost,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let path = components.queryItems?
                .first(where: { $0.name == jobQueryItem })?.value,
            !path.isEmpty
        else {
            throw RcloneError(message: "Unsupported URL: \(url.absoluteString)")
        }

        let jobFile = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: jobFile)
        return (try JSONDecoder().decode(UploadJob.self, from: data), jobFile)
    }
}
