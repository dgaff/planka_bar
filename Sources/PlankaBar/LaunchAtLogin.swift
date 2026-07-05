import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). No helper app needed.
/// Note: macOS requires the app to live in a stable location (e.g. /Applications)
/// for login-item registration to survive reliably.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message on failure, nil on success.
    @discardableResult
    static func set(enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
    }
}
