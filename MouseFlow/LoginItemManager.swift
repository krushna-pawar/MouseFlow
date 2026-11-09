// Manages login item registration using SMAppService (macOS 13+).

import Foundation
import ServiceManagement

final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var requiresApproval: Bool = false

    init() {
        refresh()
    }

    /// Queries the actual macOS system service status as the single source of truth.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        requiresApproval = (status == .requiresApproval)
    }

    /// Registers or unregisters MouseFlow with the system login items.
    func setEnabled(_ enable: Bool) {
        let service = SMAppService.mainApp
        do {
            if enable {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status != .notRegistered {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("[MouseFlow] Failed to update launch at login: %@", error.localizedDescription)
        }

        refresh()

        if enable && service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// Opens System Settings -> General -> Login Items for user approval.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
