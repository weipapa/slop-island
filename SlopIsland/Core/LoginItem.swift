import Foundation
import ServiceManagement

/// Launch-at-login control backed by `SMAppService.mainApp` (macOS 13+).
/// The deployment target is macOS 14, so the modern API is always available.
enum LoginItem {

    /// Whether SlopIsland is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the app as a login item. Throws on failure so the
    /// caller can surface the error and roll back the UI toggle.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
