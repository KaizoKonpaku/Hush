import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appCoordinator = AppCoordinator(appModel: .shared)

    func applicationDidFinishLaunching(_ notification: Notification) {
        appCoordinator.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        AppModel.shared.showMainWindow(AppModel.shared.mainWindowRoute)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appCoordinator.stop()
    }
}
