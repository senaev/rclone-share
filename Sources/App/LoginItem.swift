import Foundation
import ServiceManagement

/// Starts the app at login, so the hotkey survives a reboot.
///
/// `SMAppService` is the supported route since macOS 13. It may answer
/// `requiresApproval`, because the user has the final say in
/// System Settings → General → Login Items & Extensions.
enum LoginItem {

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// Applies the setting and reports a problem worth showing the user.
    @discardableResult
    static func set(_ enable: Bool) -> String? {
        do {
            if enable {
                try SMAppService.mainApp.register()
                Log.app.info("Registered the login item, status \(describe(status))")

                if status == .requiresApproval {
                    return "Approve RcloneShare in System Settings → Login Items."
                }
            } else {
                try SMAppService.mainApp.unregister()
                Log.app.info("Unregistered the login item, status \(describe(status))")
            }
            return nil
        } catch {
            let problem = (error as NSError).debugDescription
            Log.app.error("Login item change failed: \(problem)")
            return error.localizedDescription
        }
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        case .notRegistered: return "notRegistered"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
}
