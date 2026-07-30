import AppKit
import Combine
import UserNotifications

@MainActor
final class AppNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationManager()

    private enum NotificationTrigger {
        case backgroundComplete
        case error
    }

    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var alertSetting: UNNotificationSetting = .disabled
    @Published private(set) var systemAlertStyle: UNAlertStyle = .none
    @Published private(set) var soundSetting: UNNotificationSetting = .disabled
    @Published private(set) var badgeSetting: UNNotificationSetting = .disabled

    private var badgeCount = 0
    private var isStarted = false
    private var appDidBecomeActiveObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        center.delegate = self

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.clearBadge()
                self?.refreshSystemSettings()
            }
        }

        syncEnabledState()
    }

    func stop() {
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
        }
        appDidBecomeActiveObserver = nil
        center.delegate = nil
        isStarted = false
        clearBadge()
    }

    func syncEnabledState() {
        guard notificationsEnabled, badgeEnabled else {
            clearBadge()
            refreshSystemSettings()
            return
        }

        refreshSystemSettings()
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await notificationSettings()
        apply(settings)

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            let granted = await requestAuthorization()
            let refreshedSettings = await notificationSettings()
            apply(refreshedSettings)
            return granted
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func refreshSystemSettings() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let settings = await notificationSettings()
            apply(settings)
        }
    }

    var isPermissionGranted: Bool {
        isAuthorizationGranted(authorizationStatus)
    }

    var authorizationStatusTitle: String {
        switch authorizationStatus {
        case .authorized:
            return "Allowed"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Temporary"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }

    var systemAlertStyleTitle: String {
        guard isPermissionGranted else {
            return "None"
        }

        guard alertSetting == .enabled else {
            return "None"
        }

        switch systemAlertStyle {
        case .banner:
            return "Banner"
        case .alert:
            return "Alert"
        case .none:
            return "None"
        @unknown default:
            return "Banner"
        }
    }

    var systemAlertStyleStorageValue: String {
        guard isPermissionGranted else {
            return "none"
        }

        guard alertSetting == .enabled else {
            return "none"
        }

        switch systemAlertStyle {
        case .banner:
            return "banner"
        case .alert:
            return "alert"
        case .none:
            return "none"
        @unknown default:
            return "banner"
        }
    }

    func openSystemNotificationSettings() {
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ]

        for candidate in candidateURLs {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        if let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    func postBackgroundCompletion(title: String, message: String) {
        guard shouldSendSystemNotification(for: .backgroundComplete) else { return }
        guard NSApp.isActive == false else { return }

        scheduleNotification(title: title, message: message)
    }

    func postError(title: String, message: String) {
        guard shouldSendSystemNotification(for: .error) else { return }
        guard NSApp.isActive == false else { return }

        scheduleNotification(title: title, message: message)
    }

    private var notificationsEnabled: Bool {
        defaults.object(forKey: "settings.notificationsEnabled") as? Bool ?? true
    }

    private var badgeEnabled: Bool {
        defaults.object(forKey: "notif.badge") as? Bool ?? false
    }

    private func shouldSendSystemNotification(for trigger: NotificationTrigger) -> Bool {
        guard notificationsEnabled else { return false }
        guard (defaults.string(forKey: "notif.alertStyle") ?? "banner") != "none" else { return false }

        switch trigger {
        case .backgroundComplete:
            return defaults.object(forKey: "notif.backgroundComplete") as? Bool ?? false
        case .error:
            return defaults.object(forKey: "notif.errors") as? Bool ?? true
        }
    }

    private func scheduleNotification(title: String, message: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await requestAuthorizationIfNeeded() else { return }

            let content = notificationContent(title: title, message: message)
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            do {
                try await center.add(request)
                incrementBadgeIfNeeded()
            } catch {
                return
            }
        }
    }

    private func notificationContent(title: String, message: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let preview = previewPayload(title: title, message: message)
        content.title = preview.title
        content.body = preview.message

        if defaults.object(forKey: "notif.sound") as? Bool ?? true {
            content.sound = .default
        }

        return content
    }

    private func previewPayload(title: String, message: String) -> (title: String, message: String) {
        switch defaults.string(forKey: "notif.previewContent") ?? "partial" {
        case "full":
            return (title, message)
        case "none":
            return ("HUSH", "Open HUSH to view the latest update.")
        default:
            return (title, truncatedPreview(message))
        }
    }

    private func truncatedPreview(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "Open HUSH to view the latest update."
        }

        let limit = 96
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func incrementBadgeIfNeeded() {
        guard badgeEnabled else {
            clearBadge()
            return
        }

        badgeCount += 1
        NSApp.dockTile.badgeLabel = "\(badgeCount)"
    }

    private func clearBadge() {
        badgeCount = 0
        NSApp.dockTile.badgeLabel = nil
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func apply(_ settings: UNNotificationSettings) {
        authorizationStatus = settings.authorizationStatus
        alertSetting = settings.alertSetting
        systemAlertStyle = settings.alertStyle
        soundSetting = settings.soundSetting
        badgeSetting = settings.badgeSetting

        if isAuthorizationGranted(settings.authorizationStatus) == false {
            defaults.set(false, forKey: "settings.notificationsEnabled")
        }

        let syncedAlertStyle = syncedAlertStyleValue(from: settings)
        if defaults.string(forKey: "notif.alertStyle") != syncedAlertStyle {
            defaults.set(syncedAlertStyle, forKey: "notif.alertStyle")
        }
    }

    private func syncedAlertStyleValue(from settings: UNNotificationSettings) -> String {
        guard isAuthorizationGranted(settings.authorizationStatus) else {
            return "none"
        }

        guard settings.alertSetting == .enabled else {
            return "none"
        }

        switch settings.alertStyle {
        case .banner:
            return "banner"
        case .alert:
            return "alert"
        case .none:
            return "none"
        @unknown default:
            return "banner"
        }
    }

    private func isAuthorizationGranted(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        Task { @MainActor in
            AppModel.shared.showMainWindow(.section(.notifications))
        }
    }
}
