import AppKit
import ApplicationServices
import Carbon
import QuartzCore
import SwiftUI

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private enum OverlayLayoutMinimums {
    static let minPanelHeight: CGFloat = 56
}

private enum OverlayNavigationPosition: String {
    case remember
    case center
    case topLeft
    case topRight
    case topMiddle
    case bottomLeft
    case bottomRight
    case bottomMiddle
}

@MainActor
final class AppCoordinator {
    private enum WindowFrameKey {
        static let restoreEnabled = "general.restoreWindowLocations"
        static let overlay = "window.frame.overlay"
        static let main = "window.frame.main"
    }

    private enum OverlayPreferenceKey {
        static let enabled = "overlay.isEnabled"
    }

    private let appModel: AppModel
    private var mainWindow: NSWindow?
    private var overlayPanel: NSPanel?
    private let menuBarManager = MenuBarManager()
    private let appNotificationManager = AppNotificationManager.shared
    private let launchAtLoginManager = LaunchAtLoginManager()
    private lazy var stealthModeManager = StealthModeManager(
        overlayPanelProvider: { [weak self] in self?.overlayPanel },
        mainWindowProvider: { [weak self] in self?.mainWindow }
    )

    private var eventMonitor: Any?
    private var hotKeyRefs: [GlobalShortcutAction: [EventHotKeyRef]] = [:]
    private var hotKeyRegistrationFailures = Set<GlobalShortcutAction>()
    private var hotKeyHandlerInstalled = false
    private var shortcutRecorderBeginObserver: NSObjectProtocol?
    private var shortcutRecorderEndObserver: NSObjectProtocol?
    private var overlayFrameObservers: [NSObjectProtocol] = []
    private var settingsFrameObservers: [NSObjectProtocol] = []
    private var pendingOverlayContentSize: NSSize?
    private var contentResizeWorkItem: DispatchWorkItem?
    private var overlayAutoHideWorkItem: DispatchWorkItem?
    private var lastAppliedOverlayContentSize: NSSize = .zero
    private var windowsHiddenFromScreen = false
    private var overlayWasVisibleBeforeHide = false
    private var mainWindowWasVisibleBeforeHide = false
    private var isShortcutRecording = false

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func start() {
        IntelligencePreferencesMigration.migrateIfNeeded()
        migrateLegacyShortcutsIfNeeded()
        appModel.isOverlayEnabled = overlayUserEnabled
        appModel.installRuntimeActions(
            showMainWindow: { [weak self] route in
                self?.showMainWindow(route: route)
            },
            toggleMainWindow: { [weak self] route in
                self?.toggleMainWindow(route: route)
            },
            hideMainWindow: { [weak self] in
                self?.hideMainWindow()
            },
            toggleOverlay: { [weak self] in
                self?.togglePanel()
            },
            updateOverlayContentSize: { [weak self] size in
                self?.handleOverlayContentSize(size)
            },
            syncRuntimeAction: { [weak self] action in
                self?.syncRuntime(action)
            }
        )
        menuBarManager.start { [weak self] in self?.togglePanel() }
        appNotificationManager.start()
        launchAtLoginManager.start()
        stealthModeManager.start()
        observeShortcutRecorderState()
        syncRuntime(.shortcuts)
        setupEventMonitor()
        launchInitialPresentation()
    }

    func stop() {
        menuBarManager.stop()
        appNotificationManager.stop()
        launchAtLoginManager.stop()
        stealthModeManager.stop()

        if let shortcutRecorderBeginObserver {
            NotificationCenter.default.removeObserver(shortcutRecorderBeginObserver)
        }
        if let shortcutRecorderEndObserver {
            NotificationCenter.default.removeObserver(shortcutRecorderEndObserver)
        }
        for observer in overlayFrameObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in settingsFrameObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        contentResizeWorkItem?.cancel()
        overlayAutoHideWorkItem?.cancel()
        hotKeyRefs.values.flatMap { $0 }.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        mainWindow = nil
    }

    @discardableResult
    private func ensureOverlayPanel() -> NSPanel? {
        if let overlayPanel {
            return overlayPanel
        }

        let hostingController = NSHostingController(
            rootView: OverlayView()
                .environment(appModel)
                .environmentObject(appModel.assistantWorkspace)
        )

        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 56),
            styleMask: [.fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.title = "HUSH"
        restoreOrPlaceOverlay(panel)
        observeFrameChanges(for: panel, key: WindowFrameKey.overlay, tokens: &overlayFrameObservers)
        lastAppliedOverlayContentSize = panel.frame.size

        overlayPanel = panel
        return panel
    }

    @discardableResult
    private func ensureMainWindow() -> NSWindow {
        if let mainWindow {
            return mainWindow
        }

        let hostingController = NSHostingController(
            rootView: AppWindowRootView()
                .environment(appModel)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.title = "HUSH"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 980, height: 680))
        window.contentMinSize = NSSize(width: 660, height: 400)

        restoreOrCenter(window, key: WindowFrameKey.main)
        observeFrameChanges(for: window, key: WindowFrameKey.main, tokens: &settingsFrameObservers)
        stealthModeManager.applyNow()

        mainWindow = window
        return window
    }

    private func handleOverlayContentSize(_ size: CGSize) {
        guard let panel = overlayPanel else { return }
        scheduleOverlayResize(to: NSSize(width: size.width, height: size.height), for: panel)
    }

    private func scheduleOverlayResize(to requestedSize: NSSize, for panel: NSPanel) {
        let normalizedSize = NSSize(
            width: max(420, round(requestedSize.width)),
            height: max(OverlayLayoutMinimums.minPanelHeight, round(requestedSize.height))
        )

        let widthDelta = abs(lastAppliedOverlayContentSize.width - normalizedSize.width)
        let heightDelta = abs(lastAppliedOverlayContentSize.height - normalizedSize.height)
        guard widthDelta > 0.5 || heightDelta > 0.5 else {
            pendingOverlayContentSize = nil
            contentResizeWorkItem?.cancel()
            return
        }

        pendingOverlayContentSize = normalizedSize

        contentResizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.applyPendingOverlayResize(for: panel)
        }
        contentResizeWorkItem = workItem
        // Let SwiftUI/AppKit finish the current layout pass before resizing the host panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80), execute: workItem)
    }

    private func applyPendingOverlayResize(for panel: NSPanel) {
        guard let newSize = pendingOverlayContentSize else { return }
        pendingOverlayContentSize = nil

        let widthDelta = abs(lastAppliedOverlayContentSize.width - newSize.width)
        let heightDelta = abs(lastAppliedOverlayContentSize.height - newSize.height)
        guard widthDelta > 0.5 || heightDelta > 0.5 else { return }

        let oldFrame = panel.frame
        let newFrame = anchoredResizeFrame(
            oldFrame: oldFrame,
            newSize: newSize,
            visibleFrame: panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        )

        lastAppliedOverlayContentSize = newSize

        panel.setFrame(newFrame, display: false)
    }

    private func anchoredResizeFrame(oldFrame: NSRect, newSize: NSSize, visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else {
            return NSRect(
                x: oldFrame.midX - (newSize.width / 2),
                y: oldFrame.midY - (newSize.height / 2),
                width: newSize.width,
                height: newSize.height
            )
        }

        let xRatio = (oldFrame.midX - visibleFrame.minX) / max(visibleFrame.width, 1)
        let yRatio = (oldFrame.midY - visibleFrame.minY) / max(visibleFrame.height, 1)

        let newX: CGFloat
        if xRatio < 0.33 {
            newX = oldFrame.minX
        } else if xRatio > 0.67 {
            newX = oldFrame.maxX - newSize.width
        } else {
            newX = oldFrame.midX - (newSize.width / 2)
        }

        let newY: CGFloat
        if yRatio > 0.5 {
            // Near top: keep top fixed so panel grows downward.
            newY = oldFrame.maxY - newSize.height
        } else {
            // Near bottom: keep bottom fixed so panel grows upward.
            newY = oldFrame.minY
        }

        var frame = NSRect(x: newX, y: newY, width: newSize.width, height: newSize.height)

        if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
        if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
        if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
        if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }

        return frame
    }

    private func registerGlobalHotKeys() {
        guard !isShortcutRecording else { return }
        installHotKeyHandlerIfNeeded()

        hotKeyRefs.values.flatMap { $0 }.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        hotKeyRegistrationFailures.removeAll()

        for action in GlobalShortcutAction.allCases {
            let shortcut = GlobalShortcut.fromDefaults(action.defaultsKey, fallback: action.defaultShortcut)
            let hotKeyID = EventHotKeyID(signature: OSType(0x48555348), id: UInt32(action.rawValue))
            var registeredRefs: [EventHotKeyRef] = []

            for candidate in registrationShortcuts(for: shortcut) {
                var ref: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    candidate.keyCode,
                    candidate.carbonModifiers,
                    hotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &ref
                )

                if status == noErr, let ref {
                    registeredRefs.append(ref)
                }
            }

            if registeredRefs.isEmpty {
                hotKeyRegistrationFailures.insert(action)
            } else {
                hotKeyRefs[action] = registeredRefs
            }
        }
    }

    private func registrationShortcuts(for shortcut: GlobalShortcut) -> [GlobalShortcut] {
        var shortcuts: [GlobalShortcut] = [shortcut]

        let hasShift = shortcut.modifiers & UInt(shiftKey) != 0
        if shortcut.keyCode == UInt32(kVK_ANSI_Equal), hasShift {
            let baseModifiers = shortcut.modifiers & ~UInt(shiftKey)
            shortcuts.append(GlobalShortcut(keyCode: UInt32(kVK_ANSI_Equal), modifiers: baseModifiers))
            shortcuts.append(GlobalShortcut(keyCode: UInt32(kVK_ANSI_KeypadPlus), modifiers: baseModifiers))
        }

        var seen = Set<GlobalShortcut>()
        return shortcuts.filter { seen.insert($0).inserted }
    }

    private func migrateLegacyShortcutsIfNeeded() {
        migrateToggleOverlayShortcutIfNeeded()
        migrateOpenSettingsShortcutIfNeeded()
        migrateDeleteCaptureShortcutIfNeeded()
        migrateQuickCaptureShortcutIfNeeded()
        migrateStealthOpacityShortcutsIfNeeded()
    }

    private func migrateToggleOverlayShortcutIfNeeded() {
        let migrationKey = "shortcuts.migration.toggleOverlay.v3"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let savedToggleOverlay = GlobalShortcut.fromDefaults(
            GlobalShortcutAction.toggleOverlay.defaultsKey,
            fallback: GlobalShortcutAction.toggleOverlay.defaultShortcut
        )

        let legacyCmdShiftSpace = GlobalShortcut(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt(cmdKey | shiftKey)
        )
        let legacyOptionSpace = GlobalShortcut(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt(optionKey)
        )

        if savedToggleOverlay == legacyCmdShiftSpace || savedToggleOverlay == legacyOptionSpace {
            GlobalShortcutAction.toggleOverlay.defaultShortcut.save(
                to: GlobalShortcutAction.toggleOverlay.defaultsKey
            )
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func migrateOpenSettingsShortcutIfNeeded() {
        let migrationKey = "shortcuts.migration.openSettings.v1"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let savedOpenSettings = GlobalShortcut.fromDefaults(
            GlobalShortcutAction.openSettings.defaultsKey,
            fallback: GlobalShortcutAction.openSettings.defaultShortcut
        )

        let knownBrokenLegacyValue = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: UInt(cmdKey | shiftKey)
        )

        if savedOpenSettings == knownBrokenLegacyValue {
            GlobalShortcutAction.openSettings.defaultShortcut.save(
                to: GlobalShortcutAction.openSettings.defaultsKey
            )
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func migrateDeleteCaptureShortcutIfNeeded() {
        let migrationKey = "shortcuts.migration.deleteCapture.v3"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let savedDeleteCapture = GlobalShortcut.fromDefaults(
            GlobalShortcutAction.deleteCapture.defaultsKey,
            fallback: GlobalShortcutAction.deleteCapture.defaultShortcut
        )

        let legacyCmdShift = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt(cmdKey | shiftKey)
        )
        let legacyCmdControl = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt(cmdKey | controlKey)
        )

        if savedDeleteCapture == legacyCmdShift || savedDeleteCapture == legacyCmdControl {
            GlobalShortcutAction.deleteCapture.defaultShortcut.save(
                to: GlobalShortcutAction.deleteCapture.defaultsKey
            )
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func migrateQuickCaptureShortcutIfNeeded() {
        let migrationKey = "shortcuts.migration.quickCapture.v1"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let savedQuickCapture = GlobalShortcut.fromDefaults(
            GlobalShortcutAction.quickCapture.defaultsKey,
            fallback: GlobalShortcutAction.quickCapture.defaultShortcut
        )

        let legacyCmdShift = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt(cmdKey | shiftKey)
        )

        if savedQuickCapture == legacyCmdShift {
            GlobalShortcutAction.quickCapture.defaultShortcut.save(
                to: GlobalShortcutAction.quickCapture.defaultsKey
            )
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func migrateStealthOpacityShortcutsIfNeeded() {
        let migrationKey = "shortcuts.migration.stealthOpacity.v2"
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationKey) {
            return
        }

        let previousDefaultIncreaseOpacity = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_Equal),
            modifiers: UInt(cmdKey | optionKey | shiftKey)
        )
        let previousDefaultDecreaseOpacity = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_Minus),
            modifiers: UInt(cmdKey | optionKey)
        )
        let previousDefaultResetOpacity = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_0),
            modifiers: UInt(cmdKey | optionKey)
        )

        let oldControlIncreaseOpacity = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_Equal),
            modifiers: UInt(cmdKey | controlKey | shiftKey)
        )
        let oldControlDecreaseOpacity = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_Minus),
            modifiers: UInt(cmdKey | controlKey)
        )
        let oldControlResetOpacity = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_0),
            modifiers: UInt(cmdKey | controlKey)
        )

        migrateShortcutIfMatchingLegacyDefault(
            key: GlobalShortcutAction.decreaseStealthOpacity.defaultsKey,
            fallback: GlobalShortcutAction.decreaseStealthOpacity.defaultShortcut,
            legacyShortcut: previousDefaultDecreaseOpacity,
            replacement: GlobalShortcutAction.decreaseStealthOpacity.defaultShortcut
        )
        migrateShortcutIfMatchingLegacyDefault(
            key: GlobalShortcutAction.increaseStealthOpacity.defaultsKey,
            fallback: GlobalShortcutAction.increaseStealthOpacity.defaultShortcut,
            legacyShortcut: previousDefaultIncreaseOpacity,
            replacement: GlobalShortcutAction.increaseStealthOpacity.defaultShortcut
        )
        migrateShortcutIfMatchingLegacyDefault(
            key: GlobalShortcutAction.resetStealthOpacity.defaultsKey,
            fallback: GlobalShortcutAction.resetStealthOpacity.defaultShortcut,
            legacyShortcut: previousDefaultResetOpacity,
            replacement: GlobalShortcutAction.resetStealthOpacity.defaultShortcut
        )

        migrateShortcutIfMatchingLegacyDefault(
            key: GlobalShortcutAction.decreaseStealthOpacity.defaultsKey,
            fallback: GlobalShortcutAction.decreaseStealthOpacity.defaultShortcut,
            legacyShortcut: oldControlDecreaseOpacity,
            replacement: GlobalShortcutAction.decreaseStealthOpacity.defaultShortcut
        )
        migrateShortcutIfMatchingLegacyDefault(
            key: GlobalShortcutAction.increaseStealthOpacity.defaultsKey,
            fallback: GlobalShortcutAction.increaseStealthOpacity.defaultShortcut,
            legacyShortcut: oldControlIncreaseOpacity,
            replacement: GlobalShortcutAction.increaseStealthOpacity.defaultShortcut
        )
        migrateShortcutIfMatchingLegacyDefault(
            key: GlobalShortcutAction.resetStealthOpacity.defaultsKey,
            fallback: GlobalShortcutAction.resetStealthOpacity.defaultShortcut,
            legacyShortcut: oldControlResetOpacity,
            replacement: GlobalShortcutAction.resetStealthOpacity.defaultShortcut
        )

        defaults.set(true, forKey: migrationKey)
    }

    private func migrateShortcutIfMatchingLegacyDefault(
        key: String,
        fallback: GlobalShortcut,
        legacyShortcut: GlobalShortcut,
        replacement: GlobalShortcut
    ) {
        let savedShortcut = GlobalShortcut.fromDefaults(key, fallback: fallback)
        if savedShortcut == legacyShortcut {
            replacement.save(to: key)
        }
    }

    private func installHotKeyHandlerIfNeeded() {
        guard !hotKeyHandlerInstalled else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard
                let userData,
                let event
            else { return OSStatus(eventNotHandledErr) }

            let coordinator = Unmanaged<AppCoordinator>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                coordinator.handleGlobalShortcutEvent(event)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        hotKeyHandlerInstalled = true
    }

    private func handleGlobalShortcutEvent(_ event: EventRef) {
        guard !isShortcutRecording else { return }
        guard let action = action(from: event) else { return }
        performShortcutAction(action)
    }

    private func syncRuntime(_ action: AppRuntimeSyncAction) {
        switch action {
        case .menuBar:
            menuBarManager.sync()
        case .launchAtLogin:
            launchAtLoginManager.sync()
        case .navigation:
            applyNavigationPreferences()
        case .stealth:
            stealthModeManager.applyNow()
            appNotificationManager.syncEnabledState()
        case .shortcuts:
            guard !isShortcutRecording else { return }
            registerGlobalHotKeys()
        }
    }

    private func observeShortcutRecorderState() {
        shortcutRecorderBeginObserver = NotificationCenter.default.addObserver(
            forName: .hushShortcutRecorderDidBegin,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isShortcutRecording = true
                self.hotKeyRefs.values.flatMap { $0 }.forEach { UnregisterEventHotKey($0) }
                self.hotKeyRefs.removeAll()
            }
        }

        shortcutRecorderEndObserver = NotificationCenter.default.addObserver(
            forName: .hushShortcutRecorderDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isShortcutRecording = false
                self.registerGlobalHotKeys()
            }
        }
    }

    private func performShortcutAction(_ action: GlobalShortcutAction) {
        let workspace = appModel.assistantWorkspace

        switch action {
        case .toggleOverlay:
            togglePanel()
        case .deleteCapture:
            workspace.deleteFocusedCapture()
        case .live:
            focusOverlayForInteraction()
            workspace.toggleTranscriptWithFeedback()
        case .cycleLiveMode:
            focusOverlayForInteraction()
            workspace.cycleLiveAudioSourceWithFeedback()
        case .text:
            focusOverlayForInteraction()
            workspace.toggleTextWithFeedback()
        case .capture:
            focusOverlayForInteraction()
            workspace.handleCaptureActionWithFeedback(mode: .full)
        case .quickCapture:
            focusOverlayForInteraction()
            workspace.handleQuickCaptureActionWithFeedback()
        case .openSettings:
            toggleAppWindow()
        case .toggleStealth:
            toggleStealthMode()
        case .decreaseStealthOpacity:
            adjustStealthOpacity(by: -0.05)
        case .increaseStealthOpacity:
            adjustStealthOpacity(by: 0.05)
        case .resetStealthOpacity:
            resetStealthOpacity()
        case .moveLeft:
            moveOverlayPanel(deltaX: -30, deltaY: 0)
        case .moveRight:
            moveOverlayPanel(deltaX: 30, deltaY: 0)
        case .moveUp:
            moveOverlayPanel(deltaX: 0, deltaY: 24)
        case .moveDown:
            moveOverlayPanel(deltaX: 0, deltaY: -24)
        case .focusCapturePrevious:
            workspace.focusPreviousCapture()
        case .focusCaptureNext:
            workspace.focusNextCapture()
        case .toggleAutoscroll:
            workspace.toggleAutoScrollResults()
        case .resultsScrollUp:
            workspace.scrollResults(to: .top)
        case .resultsScrollDown:
            workspace.scrollResults(to: .bottom)
        case .hideUnhideFromScreen:
            togglePanel()
        case .process:
            focusOverlayForInteraction()
            workspace.runProcessWithFeedback()
        case .newSession:
            workspace.startNewSessionWithFeedback()
        }
    }

    private func action(from event: EventRef) -> GlobalShortcutAction? {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return nil }
        return GlobalShortcutAction(rawValue: Int(hotKeyID.id))
    }

    private func toggleAppWindow() {
        toggleMainWindow(route: appModel.mainWindowRoute)
    }

    private func toggleStealthMode() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "stealth.enabled"), forKey: "stealth.enabled")
        syncRuntime(.menuBar)
        syncRuntime(.stealth)
    }

    private func adjustStealthOpacity(by delta: Double) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "stealth.enabled") else { return }

        let currentOpacity = defaults.object(forKey: "stealth.opacity") as? Double ?? StealthPreferences.defaultOverlayOpacity
        let clampedOpacity = min(max(currentOpacity + delta, 0.2), 1.0)
        let roundedOpacity = (clampedOpacity * 100).rounded() / 100

        guard abs(roundedOpacity - currentOpacity) > 0.0001 else { return }

        defaults.set(roundedOpacity, forKey: "stealth.opacity")
        syncRuntime(.stealth)
    }

    private func resetStealthOpacity() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "stealth.enabled") else { return }

        let defaultOpacity = StealthPreferences.defaultOverlayOpacity
        let currentOpacity = defaults.object(forKey: "stealth.opacity") as? Double ?? defaultOpacity

        guard abs(currentOpacity - defaultOpacity) > 0.0001 else { return }

        defaults.set(defaultOpacity, forKey: "stealth.opacity")
        syncRuntime(.stealth)
    }

    private func moveOverlayPanel(deltaX: CGFloat, deltaY: CGFloat) {
        guard overlayUserEnabled || overlayPanel?.isVisible == true else { return }

        if overlayPanel?.isVisible != true, shouldPreferAssistantWindowOverOverlay() {
            showMainWindow(route: .assistant)
            return
        }

        guard let panel = ensureOverlayPanel() else { return }
        if !panel.isVisible {
            showOverlayPanel()
        }
        let currentOrigin = panel.frame.origin
        var nextOrigin = NSPoint(x: currentOrigin.x + deltaX, y: currentOrigin.y + deltaY)

        if UserDefaults.standard.bool(forKey: "nav.snapToEdges"),
           let visibleFrame = panel.screen?.visibleFrame ?? targetOverlayScreen()?.visibleFrame {
            nextOrigin = snappedOverlayOrigin(
                for: nextOrigin,
                panelSize: panel.frame.size,
                visibleFrame: visibleFrame
            )
        }

        panel.setFrameOrigin(nextOrigin)
        scheduleOverlayAutoHideIfNeeded()
    }

    private func focusOverlayForInteraction() {
        guard overlayUserEnabled else { return }

        if shouldPreferAssistantWindowOverOverlay() {
            showMainWindow(route: .assistant)
            return
        }

        if let panel = ensureOverlayPanel() {
            if !panel.isVisible {
                showOverlayPanel()
            }
            activateAppForInteraction()
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
            scheduleOverlayAutoHideIfNeeded()
        }
    }

    private func toggleWindowsHiddenFromScreen() {
        if windowsHiddenFromScreen {
            windowsHiddenFromScreen = false
            if overlayWasVisibleBeforeHide {
                showOverlayPanel()
            }
            if mainWindowWasVisibleBeforeHide {
                showMainWindow(route: appModel.mainWindowRoute)
            }
            return
        }

        windowsHiddenFromScreen = true
        overlayWasVisibleBeforeHide = overlayPanel?.isVisible ?? false
        mainWindowWasVisibleBeforeHide = mainWindow?.isVisible ?? false
        cancelOverlayAutoHide()
        overlayPanel?.orderOut(nil)
        mainWindow?.orderOut(nil)
        appModel.isOverlayVisible = false
    }

    private func setupEventMonitor() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel, .gesture]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleObservedUserActivity()
            }
            return event
        }
    }

    private func togglePanel() {
        if overlayUserEnabled {
            setOverlayUserEnabled(false)
            hideOverlayPanel(userInitiated: false)
            appModel.isOverlayVisible = false
            return
        }

        setOverlayUserEnabled(true)
        windowsHiddenFromScreen = false
        showOverlayPanel(allowWhileAssistantVisible: true, ignoreUserPreference: true)
    }

    private func showOverlayPanel(
        allowWhileAssistantVisible: Bool = false,
        ignoreUserPreference: Bool = false
    ) {
        guard ignoreUserPreference || overlayUserEnabled else {
            appModel.isOverlayVisible = false
            return
        }

        if shouldPreferAssistantWindowOverOverlay(), !allowWhileAssistantVisible {
            showMainWindow(route: .assistant)
            appModel.isOverlayVisible = false
            return
        }

        _ = ensureOverlayPanel()
        stealthModeManager.prepareOverlayForPresentation()
        overlayPanel?.alphaValue = stealthModeManager.currentOverlayOpacity()
        overlayPanel?.makeKeyAndOrderFront(nil)
        appModel.isOverlayVisible = true
        scheduleOverlayAutoHideIfNeeded()
    }

    private func showOverlayPanelOnLaunch() {
        guard overlayUserEnabled else {
            appModel.isOverlayVisible = false
            return
        }

        if shouldPreferAssistantWindowOverOverlay() {
            appModel.isOverlayVisible = false
            return
        }

        _ = ensureOverlayPanel()
        stealthModeManager.prepareOverlayForPresentation()
        overlayPanel?.alphaValue = stealthModeManager.currentOverlayOpacity()
        overlayPanel?.orderFrontRegardless()
        appModel.isOverlayVisible = true
        scheduleOverlayAutoHideIfNeeded()
    }

    private func launchInitialPresentation() {
        let behavior = LaunchPresentation.load().initialBehavior
        let launchesWithoutFocus = shouldLaunchWithoutFocus()

        if behavior.showsMainWindow {
            if launchesWithoutFocus {
                showMainWindowOnLaunch(route: .assistant)
            } else {
                showMainWindow(route: .assistant)
            }
        }

        if behavior.showsOverlay {
            if launchesWithoutFocus {
                showOverlayPanelOnLaunch()
            } else {
                showOverlayPanel()
            }
        }
    }

    private func showMainWindow(route: MainWindowRoute) {
        appModel.requestMainWindow(route)
        windowsHiddenFromScreen = false
        activateAppForInteraction()
        configureMainWindowForPresentation()
    }

    private func showMainWindowOnLaunch(route: MainWindowRoute) {
        appModel.requestMainWindow(route)
        windowsHiddenFromScreen = false
        configureMainWindowForLaunch()
    }

    private func toggleMainWindow(route: MainWindowRoute) {
        if let mainWindow, mainWindow.isVisible, appModel.mainWindowRoute.matchesToggleTarget(route) {
            hideMainWindow()
            return
        }

        showMainWindow(route: route)
    }

    private func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    private func configureMainWindowForPresentation() {
        let window = ensureMainWindow()

        window.title = "HUSH"
        if !window.isVisible {
            restoreOrCenter(window, key: WindowFrameKey.main)
        }
        observeFrameChanges(for: window, key: WindowFrameKey.main, tokens: &settingsFrameObservers)
        stealthModeManager.applyNow()
        window.makeKeyAndOrderFront(nil)
    }

    private func configureMainWindowForLaunch() {
        let window = ensureMainWindow()

        window.title = "HUSH"
        if !window.isVisible {
            restoreOrCenter(window, key: WindowFrameKey.main)
        }
        observeFrameChanges(for: window, key: WindowFrameKey.main, tokens: &settingsFrameObservers)
        stealthModeManager.applyNow()
        window.orderFrontRegardless()
    }

    private func activateAppForInteraction() {
        _ = NSRunningApplication.current.activate(options: [])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func shouldLaunchWithoutFocus() -> Bool {
        let preferences = StealthPreferences.load()
        return preferences.isEnabled && preferences.launchWithoutFocus
    }

    private var overlayUserEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: OverlayPreferenceKey.enabled) != nil else {
            return true
        }

        return defaults.bool(forKey: OverlayPreferenceKey.enabled)
    }

    private func setOverlayUserEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: OverlayPreferenceKey.enabled)
        appModel.isOverlayEnabled = isEnabled
    }

    private func shouldPreferAssistantWindowOverOverlay() -> Bool {
        guard let mainWindow, mainWindow.isVisible else { return false }
        return appModel.mainWindowRoute == .assistant
    }

    private func applyNavigationPreferences() {
        if let panel = overlayPanel {
            placeOverlay(panel, animated: panel.isVisible)
        }
        scheduleOverlayAutoHideIfNeeded()
    }

    private func overlayAutoHideInterval() -> TimeInterval? {
        switch UserDefaults.standard.string(forKey: "nav.autoHide") ?? "never" {
        case "10s":
            return 10
        case "30s":
            return 30
        case "60s":
            return 60
        default:
            return nil
        }
    }

    private func handleObservedUserActivity() {
        guard overlayPanel?.isVisible == true else { return }
        scheduleOverlayAutoHideIfNeeded()
    }

    private func scheduleOverlayAutoHideIfNeeded() {
        cancelOverlayAutoHide()

        guard overlayPanel?.isVisible == true, let interval = overlayAutoHideInterval() else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.hideOverlayPanelIfNeeded()
            }
        }

        overlayAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    private func cancelOverlayAutoHide() {
        overlayAutoHideWorkItem?.cancel()
        overlayAutoHideWorkItem = nil
    }

    private func hideOverlayPanelIfNeeded() {
        hideOverlayPanel(userInitiated: false)
    }

    private func hideOverlayPanel(userInitiated: Bool) {
        guard let panel = overlayPanel, panel.isVisible else {
            if userInitiated {
                setOverlayUserEnabled(false)
                appModel.isOverlayVisible = false
            }
            return
        }

        cancelOverlayAutoHide()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                panel.orderOut(nil)
                panel.alphaValue = self.stealthModeManager.currentOverlayOpacity()
                self.appModel.isOverlayVisible = false
                if userInitiated {
                    self.setOverlayUserEnabled(false)
                }
            }
        }
    }

    private func centerWindowPrecisely(_ window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }
        let x = visibleFrame.minX + ((visibleFrame.width - window.frame.width) / 2)
        let y = visibleFrame.minY + ((visibleFrame.height - window.frame.height) / 2)
        window.setFrameOrigin(NSPoint(x: round(x), y: round(y)))
    }

    private func restoreOrPlaceOverlay(_ panel: NSPanel) {
        placeOverlay(panel, animated: false)
    }

    private func restoreOrCenter(_ window: NSWindow, key: String) {
        if shouldRestoreWindowLocations(),
           let frame = storedFrame(for: key) {
            window.setFrame(frame, display: false)
            return
        }
        centerWindowPrecisely(window)
    }

    private func shouldRestoreWindowLocations() -> Bool {
        UserDefaults.standard.bool(forKey: WindowFrameKey.restoreEnabled)
    }

    private func storedFrame(for key: String) -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let frame = NSRectFromString(raw)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    private func observeFrameChanges(for window: NSWindow, key: String, tokens: inout [NSObjectProtocol]) {
        guard tokens.isEmpty else { return }

        let moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in self.persistWindowFrame(window, key: key) }
        }

        let resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in self.persistWindowFrame(window, key: key) }
        }

        tokens = [moveObserver, resizeObserver]
    }

    private func persistWindowFrame(_ window: NSWindow, key: String) {
        guard shouldPersistWindowFrame(for: key) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: key)
    }

    private func shouldPersistWindowFrame(for key: String) -> Bool {
        if key == WindowFrameKey.overlay {
            let navPosition = UserDefaults.standard.string(forKey: "nav.position") ?? OverlayNavigationPosition.remember.rawValue
            if navPosition == OverlayNavigationPosition.remember.rawValue {
                return true
            }
        }

        return shouldRestoreWindowLocations()
    }

    private func placeOverlay(_ panel: NSPanel, animated: Bool) {
        if let frame = rememberedOverlayFrame() {
            panel.setFrame(frame, display: true, animate: animated)
            return
        }

        guard let visibleFrame = targetOverlayScreen()?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            panel.center()
            return
        }

        let frame = overlayFrame(for: panel.frame.size, in: visibleFrame)
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func rememberedOverlayFrame() -> NSRect? {
        let navPosition = OverlayNavigationPosition(
            rawValue: UserDefaults.standard.string(forKey: "nav.position") ?? OverlayNavigationPosition.remember.rawValue
        ) ?? .remember

        guard navPosition == .remember else { return nil }
        return storedFrame(for: WindowFrameKey.overlay)
    }

    private func targetOverlayScreen() -> NSScreen? {
        let multiMonitorPreference = UserDefaults.standard.string(forKey: "nav.multiMonitor") ?? "active"

        switch multiMonitorPreference {
        case "primary":
            return NSScreen.screens.first ?? NSScreen.main
        default:
            if let overlayScreen = overlayPanel?.screen {
                return overlayScreen
            }

            let mouseLocation = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        }
    }

    private func overlayFrame(for panelSize: NSSize, in visibleFrame: NSRect) -> NSRect {
        let position = OverlayNavigationPosition(
            rawValue: UserDefaults.standard.string(forKey: "nav.position") ?? OverlayNavigationPosition.remember.rawValue
        ) ?? .remember

        let inset: CGFloat = 14
        let origin: NSPoint

        switch position {
        case .remember, .center:
            origin = NSPoint(
                x: visibleFrame.midX - (panelSize.width / 2),
                y: visibleFrame.midY - (panelSize.height / 2)
            )
        case .topLeft:
            origin = NSPoint(
                x: visibleFrame.minX + inset,
                y: visibleFrame.maxY - panelSize.height - inset
            )
        case .topRight:
            origin = NSPoint(
                x: visibleFrame.maxX - panelSize.width - inset,
                y: visibleFrame.maxY - panelSize.height - inset
            )
        case .topMiddle:
            origin = NSPoint(
                x: visibleFrame.midX - (panelSize.width / 2),
                y: visibleFrame.maxY - panelSize.height - inset
            )
        case .bottomLeft:
            origin = NSPoint(
                x: visibleFrame.minX + inset,
                y: visibleFrame.minY + inset
            )
        case .bottomRight:
            origin = NSPoint(
                x: visibleFrame.maxX - panelSize.width - inset,
                y: visibleFrame.minY + inset
            )
        case .bottomMiddle:
            origin = NSPoint(
                x: visibleFrame.midX - (panelSize.width / 2),
                y: visibleFrame.minY + inset
            )
        }

        return NSRect(
            x: round(origin.x),
            y: round(origin.y),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func snappedOverlayOrigin(
        for origin: NSPoint,
        panelSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let threshold: CGFloat = 18
        var adjusted = origin

        if abs(origin.x - visibleFrame.minX) <= threshold {
            adjusted.x = visibleFrame.minX
        } else if abs((origin.x + panelSize.width) - visibleFrame.maxX) <= threshold {
            adjusted.x = visibleFrame.maxX - panelSize.width
        }

        if abs(origin.y - visibleFrame.minY) <= threshold {
            adjusted.y = visibleFrame.minY
        } else if abs((origin.y + panelSize.height) - visibleFrame.maxY) <= threshold {
            adjusted.y = visibleFrame.maxY - panelSize.height
        }

        adjusted.x = min(max(adjusted.x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        adjusted.y = min(max(adjusted.y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        return NSPoint(x: round(adjusted.x), y: round(adjusted.y))
    }
}
