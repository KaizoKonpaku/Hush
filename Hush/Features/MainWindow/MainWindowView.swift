//
//  MainWindowView.swift
//  Test
//
//  macOS 26 native main app window
//

import AppKit
import SwiftUI

// MARK: - Main app window view

struct MainWindowView: View {
    @Environment(AppModel.self) var appModel
    @StateObject var permissionsManager = PermissionsManager()
    @StateObject var notificationManager = AppNotificationManager.shared
    @StateObject var providerStore = ProviderAccountStore.shared
    @State var sessionStore = SessionHistoryStore.shared
    @State var store = MainWindowStore()
    @State var isShowingShortcutResetConfirmation = false
    @State var isShowingPreferencesResetConfirmation = false
    @State var isShowingAssistantInspector = false
    @State var assistantInspectorSection: AssistantInspectorSection = .queries
    @AppStorage("settings.appearance") var appearanceMode = "system"
    @AppStorage("settings.notificationsEnabled") var notificationsEnabled = true
    @AppStorage("behaviours.confirmActions") var confirmActions = true
    @AppStorage("behaviours.defaultMode") var defaultMode = "none"
    @AppStorage("behaviours.allowFilesystemActions") var behavioursAllowFilesystem = "prompt"
    @AppStorage("behaviours.allowNetworkActions") var behavioursAllowNetwork = "prompt"
    @AppStorage("behaviours.live.autoListen") var liveAutoListen = true
    @AppStorage("behaviours.live.language") var liveLanguage = "system"
    @AppStorage("behaviours.live.audioSource") var liveAudioSource = "both"
    @AppStorage("behaviours.live.interruptWhenSpeak") var liveInterruptWhenSpeak = true
    @AppStorage("behaviours.live.reduceNoise") var liveReduceNoise = true
    @AppStorage("behaviours.text.sendOnEnter") var textSendOnEnter = true
    @AppStorage("behaviours.text.sendOnCmdEnter") var textSendOnCmdEnter = false
    @AppStorage("behaviours.text.streamResponses") var textStreamResponses = true
    @AppStorage("behaviours.text.markdown") var textMarkdown = true
    @AppStorage("behaviours.text.citations") var textCitations = true
    @AppStorage("behaviours.text.maxAnswerLength") var textMaxAnswerLength = "medium"
    @AppStorage("behaviours.capture.includeCursor") var captureIncludeCursor = true
    @AppStorage("behaviours.capture.quickMode") var captureQuickMode = "selection"
    @AppStorage("stealth.enabled") var stealthEnabled = false
    @AppStorage("stealth.launchWithoutFocus") var stealthLaunchWithoutFocus = true
    @AppStorage("stealth.stayOnTop") var stealthStayOnTop = true
    @AppStorage("stealth.hideFromDock") var stealthHideFromDock = false
    @AppStorage("stealth.hideFromActivityWindow") var stealthHideFromActivityWindow = false
    @AppStorage("stealth.hideFromMissionControl") var stealthHideFromMissionControl = false
    @AppStorage("stealth.hideFromStageManager") var stealthHideFromStageManager = false
    @AppStorage("stealth.opacity") var stealthOpacity = 0.92
    @AppStorage("stealth.mousePassthrough") var stealthMousePassthrough = false
    @AppStorage("stealth.noWindowShadow") var stealthNoWindowShadow = false
    @AppStorage("stealth.hideFromScreenCapture") var stealthHideFromScreenCapture = false
    @AppStorage("stealth.suppressNotificationHistory") var stealthSuppressNotificationHistory = false
    @AppStorage("stealth.suppressRecentItemsAndHandoff") var stealthSuppressRecentItemsAndHandoff = false
    @AppStorage("stealth.menuBarVisibility") var stealthMenuBarVisibility = "default"
    @AppStorage("general.launchAtLogin") var generalLaunchAtLogin = false
    @AppStorage("general.launchPresentation") var generalLaunchPresentation = LaunchPresentation.window.rawValue
    @AppStorage("general.showInMenuBar") var generalShowInMenuBar = true
    @AppStorage("general.restoreWindowLocations") var generalRestoreWindowLocations = false
    @AppStorage("accounts.syncPreferences") var accountsSyncPreferences = true
    @AppStorage("accounts.syncMemories") var accountsSyncMemories = false
    @AppStorage("accounts.useKeychain") var accountsUseKeychain = true
    @AppStorage("accounts.lockWithPassword") var accountsLockWithPassword = false
    @AppStorage("accounts.lockTimeout") var accountsLockTimeout = "5min"
    @AppStorage("intel.defaultModel") var intelDefaultModel = ""
    @AppStorage("intel.fastModel") var intelFastModel = ""
    @AppStorage("intel.advancedModel") var intelAdvancedModel = ""
    @AppStorage("intel.realtimeModel") var intelRealtimeModel = ""
    @AppStorage("assistant.selectedModelMode") var assistantSelectedModelMode = AssistantModelMode.defaultMode.rawValue
    @AppStorage("memory.keepHistory") var memoryKeepHistory = "session"
    @AppStorage("memory.autoIncludeContext") var memoryAutoIncludeContext = true
    @AppStorage("memory.longTermEnabled") var memoryLongTermEnabled = false
    @AppStorage("memory.longTermScope") var memoryLongTermScope = "global"
    @AppStorage("memory.autosaveTranscripts") var memoryAutosaveTranscripts = false
    @AppStorage("memory.transcriptFormat") var memoryTranscriptFormat = "markdown"
    @AppStorage("memory.includeMetadata") var memoryIncludeMetadata = true
    @AppStorage("memory.autoNameSessions") var memoryAutoNameSessions = true
    @AppStorage("nav.position") var navPosition = "remember"
    @AppStorage("nav.multiMonitor") var navMultiMonitor = "active"
    @AppStorage("nav.snapToEdges") var navSnapToEdges = false
    @AppStorage("nav.autoHide") var navAutoHide = "never"
    @AppStorage("nav.trackpadGestures") var navTrackpadGestures = true
    @AppStorage("nav.keyboardNavigation") var navKeyboardNavigation = true
    @AppStorage("nav.focusInputOnOpen") var navFocusInputOnOpen = true
    @AppStorage("notif.backgroundComplete") var notifBackgroundComplete = false
    @AppStorage("notif.errors") var notifErrors = true
    @AppStorage("notif.sound") var notifSound = true
    @AppStorage("notif.badge") var notifBadge = false
    @AppStorage("notif.alertStyle") var notifAlertStyle = "banner"
    @AppStorage("notif.previewContent") var notifPreviewContent = "partial"
    @AppStorage("notif.inAppEnabled") var notifInAppEnabled = true
    @AppStorage("notif.inAppAutoDismiss") var notifInAppAutoDismiss = true
    @AppStorage("notif.inAppDuration") var notifInAppDuration = "normal"
    @AppStorage("notif.inAppShowInfo") var notifInAppShowInfo = true
    @AppStorage("themes.accent.red") var themesAccentRed = 0.0
    @AppStorage("themes.accent.green") var themesAccentGreen = 0.48
    @AppStorage("themes.accent.blue") var themesAccentBlue = 1.0
    @AppStorage("themes.accent.preset") var themesAccentPreset = "blue"
    @AppStorage("themes.accentActionPills") var themesAccentActionPills = false
    @AppStorage("themes.materialStyle") var themesMaterialStyle = InterfaceMaterialStyle.medium.rawValue
    @AppStorage("themes.density") var themesDensity = "comfortable"
    @AppStorage("themes.fontFamily") var themesFontFamily = "system"
    @AppStorage("themes.fontSize") var themesFontSize = InterfaceFontSize.defaultRawValue
    @AppStorage("themes.lineHeight") var themesLineHeight = "normal"
    @AppStorage("themes.messageLayout") var themesMessageLayout = "bubbles"
    @AppStorage("themes.showAvatars") var themesShowAvatars = true
    @AppStorage("themes.renderMarkdown") var themesRenderMarkdown = "full"
    @AppStorage("themes.codeTheme") var themesCodeTheme = "xcode"
    @AppStorage("themes.codeLineNumbers") var themesCodeLineNumbers = false
    @AppStorage("themes.streamingStyle") var themesStreamingStyle = "typewriter"
    @AppStorage("themes.typingIndicator") var themesTypingIndicator = true
    @AppStorage("components.liveEnabled") var componentsLiveEnabled = true
    @AppStorage("components.textEnabled") var componentsTextEnabled = true
    @AppStorage("components.captureEnabled") var componentsCaptureEnabled = true
    @AppStorage("components.clipboardIntegration") var componentsClipboardIntegration = false
    @AppStorage("components.defaultExportFormat") var componentsDefaultExportFormat = "markdown"
    @AppStorage("components.autosaveSummaries") var componentsAutosaveSummaries = false
    @AppStorage("locations.useForContext") var locationsUseForContext = true
    @AppStorage("locations.precision") var locationsPrecision = "city"
    @AppStorage("locations.useForSuggestions") var locationsUseForSuggestions = true

    var currentRoute: MainWindowRoute { store.currentRoute }
    var hasPreviousSection: Bool { store.hasPreviousSection }
    var hasNextSection: Bool { store.hasNextSection }

    var body: some View {
        NavigationSplitView {
            mainWindowSidebar
        } detail: {
            NavigationStack {
                mainWindowDetail
            }
            .inspector(isPresented: assistantInspectorBinding) {
                assistantInspector
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
            }
        }
        .tint(themesAccentColor)
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, minHeight: 400)
        .toolbar {
            mainWindowToolbar
        }
        .background(
            MainWindowTrackpadNavigationMonitor(
                isEnabled: navTrackpadGestures,
                onPrevious: goToPreviousSection,
                onNext: goToNextSection
            )
            .frame(width: 0, height: 0)
        )
        .confirmationDialog(
            "Reset shortcuts to defaults?",
            isPresented: $isShowingShortcutResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                resetAllShortcutsToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore every shortcut to HUSH's built-in default.")
        }
        .confirmationDialog(
            "Reset HUSH preferences?",
            isPresented: $isShowingPreferencesResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                resetAllPreferencesToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets interface, navigation, model, prompt, and shortcut preferences without deleting accounts or session history.")
        }
        .onAppear {
            IntelligencePreferencesMigration.migrateIfNeeded()
            applyAccentPreset(themesAccentPreset)
            permissionsManager.refresh()
            store.reset(to: appModel.mainWindowRoute)
            appModel.mainWindowRoute = store.currentRoute
            Task {
                await providerStore.refreshConfiguredProviders(using: [:])
            }
        }
        .onChange(of: themesAccentPreset) { _, newValue in
            applyAccentPreset(newValue)
        }
        .onChange(of: liveAudioSource) { _, _ in
            appModel.assistantWorkspace.liveAudioSourceDidChange()
        }
        .onChange(of: liveLanguage) { _, _ in
            appModel.assistantWorkspace.liveLanguageDidChange()
        }
        .onChange(of: liveAutoListen) { _, _ in
            appModel.assistantWorkspace.liveAutoListenDidChange()
        }
        .onChange(of: runtimeSyncState) { _, _ in
            syncRuntimeSettings()
        }
        .task(id: appModel.mainWindowRouteRequestID) {
            guard appModel.mainWindowRouteRequestID > 0 else { return }
            await Task.yield()
            _ = store.navigate(to: appModel.mainWindowRoute)
        }
        .onChange(of: currentRoute) { _, newRoute in
            if newRoute != .assistant {
                isShowingAssistantInspector = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionsManager.refresh()
        }
        .onMoveCommand { direction in
            guard navKeyboardNavigation else { return }

            switch direction {
            case .left:
                goToPreviousSection()
            case .right:
                goToNextSection()
            default:
                break
            }
        }
    }

    func performOnMainActor(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            action()
        }
    }

    func goToPreviousSection() {
        guard store.goToPreviousSection() else { return }
        syncMainWindowRoute()
    }

    func goToNextSection() {
        guard store.goToNextSection() else { return }
        syncMainWindowRoute()
    }

    func navigate(to route: MainWindowRoute) {
        guard store.navigate(to: route) else { return }
        syncMainWindowRoute()
    }

    func syncMainWindowRoute() {
        performOnMainActor {
            appModel.mainWindowRoute = store.currentRoute
        }
    }

    var assistantInspectorBinding: Binding<Bool> {
        Binding(
            get: { currentRoute == .assistant && isShowingAssistantInspector },
            set: { isShowingAssistantInspector = $0 }
        )
    }
}

#Preview("Main window") {
    MainWindowView()
        .frame(width: 800, height: 520)
}
