import Foundation

/// The custom URL contract, shared by the app, the Share Extension and scripts.
///
///   rclone-share://upload?job=<path>      hand-off from the extension
///   rclone-share://gist                   open the gist form
///   rclone-share://login-item?enable=1    start at login, or stop
enum AppURL {

    static let scheme = "rclone-share"

    enum Route {
        case upload(jobFile: URL)
        case gist
        case loginItem(enable: Bool)
    }

    static let jobQueryItem = "job"
    static let enableQueryItem = "enable"

    static func route(_ url: URL) -> Route? {
        guard url.scheme == scheme else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        switch url.host {
        case "upload":
            guard
                let path = queryItems.first(where: { $0.name == jobQueryItem })?.value,
                !path.isEmpty
            else { return nil }
            return .upload(jobFile: URL(fileURLWithPath: path))

        case "gist":
            return .gist

        case "login-item":
            let value = queryItems.first(where: { $0.name == enableQueryItem })?.value
            // No value means "turn it on", which is what a script usually wants.
            return .loginItem(enable: Self.isTrue(value ?? "1"))

        default:
            return nil
        }
    }

    private static func isTrue(_ value: String) -> Bool {
        ["1", "true", "yes", "on"].contains(value.lowercased())
    }
}
