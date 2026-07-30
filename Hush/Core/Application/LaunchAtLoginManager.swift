import Foundation
import ServiceManagement

final class LaunchAtLoginManager {
    private let defaults = UserDefaults.standard

    func start() {
        sync()
    }

    func stop() { }

    func sync() {
        let shouldLaunchAtLogin = defaults.bool(forKey: "general.launchAtLogin")

        do {
            if shouldLaunchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best-effort: ignore registration errors in dev/sideload builds.
        }
    }
}
