import AppKit
import CoreGraphics

final class StealthModeManager {
    private let defaults = UserDefaults.standard
    private let overlayPanelProvider: () -> NSPanel?
    private let mainWindowProvider: () -> NSWindow?

    private var screenObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?

    init(
        overlayPanelProvider: @escaping () -> NSPanel?,
        mainWindowProvider: @escaping () -> NSWindow?
    ) {
        self.overlayPanelProvider = overlayPanelProvider
        self.mainWindowProvider = mainWindowProvider
    }

    func start() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyDisplayPolicy()
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyDisplayPolicy()
        }

        applyNow()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
    }

    func applyNow() {
        let settings = StealthPreferences.load(from: defaults)
        if settings.isEnabled {
            applyActivationPolicy(settings: settings)
            applyDisplayPolicy(settings: settings)
            applyWindowSettings(settings: settings)
            applyPrivacySettings(settings: settings)
        } else {
            applyDefaultPresentation()
        }
    }

    func currentOverlayOpacity() -> CGFloat {
        let settings = StealthPreferences.load(from: defaults)
        return settings.isEnabled ? settings.overlayOpacity : 1.0
    }

    func prepareOverlayForPresentation() {
        applyNow()
    }

    private func applyActivationPolicy(settings: StealthPreferences) {
        // On macOS, hiding from Cmd+Tab / Force Quit relies on accessory activation policy,
        // which also removes Dock presence. To avoid implicit side effects, only apply
        // accessory policy when Dock hiding is explicitly enabled.
        if settings.hideFromDock {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func applyWindowSettings(settings: StealthPreferences) {
        guard let panel = overlayPanelProvider() else { return }

        panel.level = settings.stayOnTop ? .statusBar : .floating
        panel.ignoresMouseEvents = settings.mousePassthrough
        panel.hasShadow = !settings.noWindowShadow
        panel.isExcludedFromWindowsMenu = settings.hideFromActivityWindow
        panel.sharingType = settings.hideFromScreenCapture ? .none : .readOnly

        panel.alphaValue = settings.overlayOpacity

        if let mainWindow = mainWindowProvider() {
            mainWindow.level = settings.stayOnTop ? .statusBar : .normal
            mainWindow.isExcludedFromWindowsMenu = settings.hideFromActivityWindow
            mainWindow.hasShadow = !settings.noWindowShadow
            mainWindow.sharingType = settings.hideFromScreenCapture ? .none : .readOnly
        }
    }

    private func applyDisplayPolicy() {
        applyDisplayPolicy(settings: StealthPreferences.load(from: defaults))
    }

    private func applyDisplayPolicy(settings: StealthPreferences) {
        guard let panel = overlayPanelProvider() else { return }

        let baseBehavior: NSWindow.CollectionBehavior
        switch settings.displayPolicy {
        case .all:
            baseBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        case .primary:
            baseBehavior = [.fullScreenAuxiliary]
            if let primaryScreen = NSScreen.screens.first {
                move(panel: panel, to: primaryScreen)
            }
        case .internalDisplay:
            baseBehavior = [.fullScreenAuxiliary]
            if let screen = NSScreen.screens.first(where: { $0.isBuiltInDisplay }) ?? NSScreen.screens.first {
                move(panel: panel, to: screen)
            }
        }

        panel.collectionBehavior = adjustedCollectionBehavior(
            from: baseBehavior,
            hideFromMissionControl: settings.hideFromMissionControl,
            hideFromStageManager: settings.hideFromStageManager
        )

        if let mainWindow = mainWindowProvider() {
            mainWindow.collectionBehavior = adjustedCollectionBehavior(
                from: baseBehavior,
                hideFromMissionControl: settings.hideFromMissionControl,
                hideFromStageManager: settings.hideFromStageManager
            )
        }
    }

    private func move(panel: NSPanel, to screen: NSScreen) {
        let panelFrame = panel.frame
        let newOrigin = NSPoint(
            x: screen.frame.midX - panelFrame.width / 2,
            y: screen.frame.midY - panelFrame.height / 2
        )
        panel.setFrameOrigin(newOrigin)
    }

    private func applyDefaultPresentation() {
        _ = NSApp.setActivationPolicy(.regular)

        if let panel = overlayPanelProvider() {
            panel.level = .floating
            panel.ignoresMouseEvents = false
            panel.hasShadow = true
            panel.isExcludedFromWindowsMenu = false
            panel.sharingType = .readOnly
            panel.alphaValue = 1.0
            panel.collectionBehavior = adjustedCollectionBehavior(
                from: [.canJoinAllSpaces, .fullScreenAuxiliary],
                hideFromMissionControl: false,
                hideFromStageManager: false
            )
        }

        if let mainWindow = mainWindowProvider() {
            mainWindow.level = .normal
            mainWindow.hasShadow = true
            mainWindow.isExcludedFromWindowsMenu = false
            mainWindow.sharingType = .readOnly
            mainWindow.collectionBehavior = adjustedCollectionBehavior(
                from: [.managed],
                hideFromMissionControl: false,
                hideFromStageManager: false
            )
        }

        NSApp.activate(ignoringOtherApps: false)
    }

    private func applyPrivacySettings(settings: StealthPreferences) {
        if settings.suppressNotificationHistory {
            setIfChanged(false, forKey: "settings.notificationsEnabled")
            setIfChanged(false, forKey: "notif.backgroundComplete")
            setIfChanged(false, forKey: "notif.errors")
            setIfChanged(false, forKey: "notif.sound")
            setIfChanged(false, forKey: "notif.inAppEnabled")
            setIfChanged(false, forKey: "notif.inAppShowInfo")
            setIfChanged("none", forKey: "notif.alertStyle")
            setIfChanged("none", forKey: "notif.previewContent")
        }

        if settings.suppressRecentItemsAndHandoff {
            setIfChanged(0, forKey: "NSRecentDocumentsLimit")
            NSDocumentController.shared.clearRecentDocuments(nil)
        }
    }

    private func setIfChanged(_ value: Bool, forKey key: String) {
        guard defaults.bool(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
    }

    private func setIfChanged(_ value: Int, forKey key: String) {
        guard defaults.integer(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
    }

    private func setIfChanged(_ value: String, forKey key: String) {
        guard defaults.string(forKey: key) != value else { return }
        defaults.set(value, forKey: key)
    }

    private func adjustedCollectionBehavior(
        from base: NSWindow.CollectionBehavior,
        hideFromMissionControl: Bool,
        hideFromStageManager: Bool
    ) -> NSWindow.CollectionBehavior {
        var behavior = base

        let hideFromOverviewSurfaces = hideFromMissionControl || hideFromStageManager

        if hideFromOverviewSurfaces {
            // Hide from overview-style surfaces.
            behavior.remove(.managed)
            behavior.insert(.transient)
        } else {
            // Explicitly participate in Mission Control / Expose.
            behavior.remove(.transient)
            behavior.insert(.managed)
        }

        return behavior
    }

}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltInDisplay: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }
}
