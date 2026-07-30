import Foundation
import CoreGraphics

enum StealthDisplayPolicy: String, CaseIterable {
    case all
    case primary
    case internalDisplay
}

struct StealthPreferences {
    static let defaultOverlayOpacity = 0.92

    var isEnabled: Bool
    var launchWithoutFocus: Bool
    var stayOnTop: Bool
    var hideFromDock: Bool
    var hideFromActivityWindow: Bool
    var hideFromMissionControl: Bool
    var hideFromStageManager: Bool
    var mousePassthrough: Bool
    var noWindowShadow: Bool
    var hideFromScreenCapture: Bool
    var suppressNotificationHistory: Bool
    var suppressRecentItemsAndHandoff: Bool
    var overlayOpacity: CGFloat
    var displayPolicy: StealthDisplayPolicy

    static func load(from defaults: UserDefaults = .standard) -> StealthPreferences {
        let opacity = defaults.object(forKey: "stealth.opacity") as? Double ?? defaultOverlayOpacity
        let boundedOpacity = min(max(opacity, 0.2), 1.0)
        let policy = StealthDisplayPolicy(rawValue: defaults.string(forKey: "stealth.displayPolicy") ?? "all") ?? .all

        return StealthPreferences(
            isEnabled: defaults.bool(forKey: "stealth.enabled"),
            launchWithoutFocus: defaults.object(forKey: "stealth.launchWithoutFocus") as? Bool ?? true,
            stayOnTop: defaults.bool(forKey: "stealth.stayOnTop"),
            hideFromDock: defaults.bool(forKey: "stealth.hideFromDock"),
            hideFromActivityWindow: defaults.bool(forKey: "stealth.hideFromActivityWindow"),
            hideFromMissionControl: defaults.bool(forKey: "stealth.hideFromMissionControl"),
            hideFromStageManager: defaults.bool(forKey: "stealth.hideFromStageManager"),
            mousePassthrough: defaults.bool(forKey: "stealth.mousePassthrough"),
            noWindowShadow: defaults.bool(forKey: "stealth.noWindowShadow"),
            hideFromScreenCapture: defaults.bool(forKey: "stealth.hideFromScreenCapture"),
            suppressNotificationHistory: defaults.bool(forKey: "stealth.suppressNotificationHistory"),
            suppressRecentItemsAndHandoff: defaults.bool(forKey: "stealth.suppressRecentItemsAndHandoff"),
            overlayOpacity: CGFloat(boundedOpacity),
            displayPolicy: policy
        )
    }
}
