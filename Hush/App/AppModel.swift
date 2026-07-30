import Foundation
import Observation
import CoreGraphics

@MainActor
@Observable
final class AppModel {
    private enum DefaultsKey {
        static let lastSettingsRoute = "window.lastSettingsRoute"
    }

    static let shared = AppModel()

    let assistantWorkspace: AssistantWorkspace

    var isOverlayVisible = false
    var isOverlayEnabled = true
    var mainWindowRoute = MainWindowRoute.assistant {
        didSet {
            rememberSettingsRouteIfNeeded(mainWindowRoute)
        }
    }
    var mainWindowRouteRequestID = 0

    private var showMainWindowAction: (@MainActor (MainWindowRoute) -> Void)?
    private var toggleMainWindowAction: (@MainActor (MainWindowRoute) -> Void)?
    private var hideMainWindowAction: (@MainActor () -> Void)?
    private var toggleOverlayAction: (@MainActor () -> Void)?
    private var updateOverlayContentSizeAction: (@MainActor (CGSize) -> Void)?
    private var syncRuntimeAction: (@MainActor (AppRuntimeSyncAction) -> Void)?
    private let defaults = UserDefaults.standard

    var shortcutConfigurationVersion = 0

    init() {
        self.assistantWorkspace = .shared
    }

    init(assistantWorkspace: AssistantWorkspace) {
        self.assistantWorkspace = assistantWorkspace
    }

    var preferredSettingsRoute: MainWindowRoute {
        if mainWindowRoute.isSettingsRoute {
            return mainWindowRoute.normalizedSettingsRoute
        }

        return MainWindowRoute.rememberedSettingsRoute(
            from: defaults.string(forKey: DefaultsKey.lastSettingsRoute)
        )
        
    }

    func requestMainWindow(_ route: MainWindowRoute) {
        mainWindowRoute = route
        mainWindowRouteRequestID &+= 1
    }

    func installRuntimeActions(
        showMainWindow: @escaping @MainActor (MainWindowRoute) -> Void,
        toggleMainWindow: @escaping @MainActor (MainWindowRoute) -> Void,
        hideMainWindow: @escaping @MainActor () -> Void,
        toggleOverlay: @escaping @MainActor () -> Void,
        updateOverlayContentSize: @escaping @MainActor (CGSize) -> Void,
        syncRuntimeAction: @escaping @MainActor (AppRuntimeSyncAction) -> Void
    ) {
        showMainWindowAction = showMainWindow
        toggleMainWindowAction = toggleMainWindow
        hideMainWindowAction = hideMainWindow
        toggleOverlayAction = toggleOverlay
        updateOverlayContentSizeAction = updateOverlayContentSize
        self.syncRuntimeAction = syncRuntimeAction
    }

    func showMainWindow(_ route: MainWindowRoute) {
        if let showMainWindowAction {
            showMainWindowAction(route)
        } else {
            requestMainWindow(route)
        }
    }

    func toggleMainWindow(_ route: MainWindowRoute) {
        if let toggleMainWindowAction {
            toggleMainWindowAction(route)
        } else {
            requestMainWindow(route)
        }
    }

    func hideMainWindow() {
        hideMainWindowAction?()
    }

    func toggleOverlay() {
        toggleOverlayAction?()
    }

    func updateOverlayContentSize(_ size: CGSize) {
        updateOverlayContentSizeAction?(size)
    }

    func syncRuntime(_ action: AppRuntimeSyncAction) {
        if action == .shortcuts {
            shortcutConfigurationVersion &+= 1
        }
        syncRuntimeAction?(action)
    }

    private func rememberSettingsRouteIfNeeded(_ route: MainWindowRoute) {
        guard route.isSettingsRoute,
              let token = route.rememberedSettingsRouteToken else { return }
        defaults.set(token, forKey: DefaultsKey.lastSettingsRoute)
    }
}
