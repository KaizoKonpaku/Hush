import AppKit
import AVFoundation
import ApplicationServices
import Combine
import CoreGraphics
import Photos
import Speech
import UserNotifications

enum AppPermissionKind: CaseIterable, Identifiable {
    case notifications
    case camera
    case photos
    case screenRecording
    case accessibility
    case inputMonitoring
    case microphone
    case speechRecognition

    var id: Self { self }

    var title: String {
        switch self {
        case .notifications:
            return "Notifications"
        case .camera:
            return "Camera"
        case .photos:
            return "Photos"
        case .screenRecording:
            return "Screen Recording"
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        case .microphone:
            return "Microphone"
        case .speechRecognition:
            return "Speech Recognition"
        }
    }

    var description: String {
        switch self {
        case .notifications:
            return "Needed for background-complete alerts and failure updates."
        case .camera:
            return "Needed when HUSH captures camera-based input."
        case .photos:
            return "Needed when HUSH opens images from your photo library."
        case .screenRecording:
            return "Needed for capture and live system-audio transcription."
        case .accessibility:
            return "Needed for global shortcuts and accessibility-based control."
        case .inputMonitoring:
            return "Needed when macOS requires keyboard event access for shortcuts."
        case .microphone:
            return "Needed for live transcription from your microphone."
        case .speechRecognition:
            return "Needed to turn live audio into text inside HUSH."
        }
    }

    var searchKeywords: [String] {
        switch self {
        case .notifications:
            return ["allow notifications", "system permission", "alerts permission", "privacy"]
        case .camera:
            return ["camera access", "video input", "privacy"]
        case .photos:
            return ["photo library", "images access", "privacy"]
        case .screenRecording:
            return ["screen capture permission", "capture access", "privacy"]
        case .accessibility:
            return ["accessibility", "automation permission", "control apps", "privacy"]
        case .inputMonitoring:
            return ["keyboard monitoring", "key events", "input access", "privacy"]
        case .microphone:
            return ["mic access", "audio input", "speech input", "privacy"]
        case .speechRecognition:
            return ["speech to text", "transcription permission", "voice recognition", "privacy"]
        }
    }

    var icon: String {
        switch self {
        case .notifications:
            return "bell.badge.fill"
        case .camera:
            return "camera.fill"
        case .photos:
            return "photo.on.rectangle.angled"
        case .screenRecording:
            return "record.circle.fill"
        case .accessibility:
            return "figure.wave.circle.fill"
        case .inputMonitoring:
            return "keyboard.fill"
        case .microphone:
            return "mic.fill"
        case .speechRecognition:
            return "waveform.circle.fill"
        }
    }

    var settingsAnchor: String {
        switch self {
        case .notifications:
            return ""
        case .camera:
            return "Privacy_Camera"
        case .photos:
            return "Privacy_Photos"
        case .screenRecording:
            return "Privacy_ScreenCapture"
        case .accessibility:
            return "Privacy_Accessibility"
        case .inputMonitoring:
            return "Privacy_ListenEvent"
        case .microphone:
            return "Privacy_Microphone"
        case .speechRecognition:
            return "Privacy_SpeechRecognition"
        }
    }
}

enum AppPermissionState: Equatable {
    case granted
    case notDetermined
    case needsApproval
    case denied
    case restricted

    var statusLabel: String {
        switch self {
        case .granted:
            return "Granted"
        case .notDetermined:
            return "Not Requested"
        case .needsApproval:
            return "Needs Approval"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }
}

enum AppPermissionResolutionAction: Equatable {
    case none
    case request
    case openSystemSettings

    var buttonTitle: String? {
        switch self {
        case .none:
            return nil
        case .request:
            return "Request"
        case .openSystemSettings:
            return "Open Settings"
        }
    }
}

extension AppPermissionState {
    var resolutionAction: AppPermissionResolutionAction {
        switch self {
        case .granted, .restricted:
            return .none
        case .notDetermined, .needsApproval:
            return .request
        case .denied:
            return .openSystemSettings
        }
    }
}

enum AppPermissionAccess {
    static func notificationState() async -> AppPermissionState {
        let settings = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }

        return mapNotificationAuthorizationStatus(settings.authorizationStatus)
    }

    static func cameraState() -> AppPermissionState {
        mapMediaAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    static func photosState() -> AppPermissionState {
        mapPhotoLibraryAuthorizationStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    static func screenCaptureState() -> AppPermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .needsApproval
    }

    static func accessibilityState() -> AppPermissionState {
        AXIsProcessTrusted() ? .granted : .needsApproval
    }

    static func inputMonitoringState() -> AppPermissionState {
        CGPreflightListenEventAccess() ? .granted : .needsApproval
    }

    static func microphoneState() -> AppPermissionState {
        mapMicrophoneAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    static func speechRecognitionState() -> AppPermissionState {
        mapSpeechRecognitionAuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
    }

    static func mapNotificationAuthorizationStatus(_ status: UNAuthorizationStatus) -> AppPermissionState {
        switch status {
        case .authorized, .provisional:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .granted
        }
    }

    static func mapMediaAuthorizationStatus(_ status: AVAuthorizationStatus) -> AppPermissionState {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    static func mapPhotoLibraryAuthorizationStatus(_ status: PHAuthorizationStatus) -> AppPermissionState {
        switch status {
        case .authorized:
            return .granted
        case .limited:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        @unknown default:
            return .granted
        }
    }

    static func mapMicrophoneAuthorizationStatus(_ status: AVAuthorizationStatus) -> AppPermissionState {
        mapMediaAuthorizationStatus(status)
    }

    static func mapSpeechRecognitionAuthorizationStatus(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> AppPermissionState {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }
        return CGRequestListenEventAccess()
    }

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func requestNotificationAccess() async -> Bool {
        await AppNotificationManager.shared.requestAuthorizationIfNeeded()
    }

    static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func requestPhotosAccess() async -> Bool {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch currentStatus {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    switch status {
                    case .authorized, .limited:
                        continuation.resume(returning: true)
                    case .notDetermined, .restricted, .denied:
                        continuation.resume(returning: false)
                    @unknown default:
                        continuation.resume(returning: true)
                    }
                }
            }
        case .restricted, .denied:
            return false
        @unknown default:
            return true
        }
    }

    static func requestSpeechRecognitionAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var notifications: AppPermissionState = .notDetermined
    @Published private(set) var camera: AppPermissionState = .notDetermined
    @Published private(set) var photos: AppPermissionState = .notDetermined
    @Published private(set) var screenRecording: AppPermissionState = .needsApproval
    @Published private(set) var accessibility: AppPermissionState = .needsApproval
    @Published private(set) var inputMonitoring: AppPermissionState = .needsApproval
    @Published private(set) var microphone: AppPermissionState = .notDetermined
    @Published private(set) var speechRecognition: AppPermissionState = .notDetermined

    init() {
        refresh()
    }

    func refresh() {
        camera = AppPermissionAccess.cameraState()
        photos = AppPermissionAccess.photosState()
        screenRecording = AppPermissionAccess.screenCaptureState()
        accessibility = AppPermissionAccess.accessibilityState()
        inputMonitoring = AppPermissionAccess.inputMonitoringState()
        microphone = AppPermissionAccess.microphoneState()
        speechRecognition = AppPermissionAccess.speechRecognitionState()

        Task { [weak self] in
            let state = await AppPermissionAccess.notificationState()
            await MainActor.run {
                self?.notifications = state
            }
        }
    }

    func state(for permission: AppPermissionKind) -> AppPermissionState {
        switch permission {
        case .notifications:
            return notifications
        case .camera:
            return camera
        case .photos:
            return photos
        case .screenRecording:
            return screenRecording
        case .accessibility:
            return accessibility
        case .inputMonitoring:
            return inputMonitoring
        case .microphone:
            return microphone
        case .speechRecognition:
            return speechRecognition
        }
    }

    func request(_ permission: AppPermissionKind) async {
        switch permission {
        case .notifications:
            _ = await AppPermissionAccess.requestNotificationAccess()
            AppNotificationManager.shared.refreshSystemSettings()
            refresh()
        case .camera:
            _ = await AppPermissionAccess.requestCameraAccess()
            refresh()
        case .photos:
            _ = await AppPermissionAccess.requestPhotosAccess()
            refresh()
        case .screenRecording:
            _ = AppPermissionAccess.requestScreenCaptureAccess()
            refreshAfterPrompt()
        case .accessibility:
            _ = AppPermissionAccess.requestAccessibilityAccess()
            refreshAfterPrompt()
        case .inputMonitoring:
            _ = AppPermissionAccess.requestInputMonitoringAccess()
            refreshAfterPrompt()
        case .microphone:
            _ = await AppPermissionAccess.requestMicrophoneAccess()
            refresh()
        case .speechRecognition:
            _ = await AppPermissionAccess.requestSpeechRecognitionAccess()
            refresh()
        }
    }

    func openSystemSettings(for permission: AppPermissionKind? = nil) {
        if let permission {
            if permission == .notifications {
                AppNotificationManager.shared.openSystemNotificationSettings()
                return
            }

            let urlString = "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsAnchor)"
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }

        if let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    private func refreshAfterPrompt() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }
}
