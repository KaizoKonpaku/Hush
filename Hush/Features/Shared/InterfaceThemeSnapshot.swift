import SwiftUI

private func clampedUnit(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

enum InterfaceAppearanceMode {
    static func preferredColorScheme(for rawValue: String) -> ColorScheme? {
        switch rawValue {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}

enum InterfaceFontSize: String, CaseIterable {
    case small
    case medium
    case large

    static var defaultRawValue: String { medium.rawValue }

    static func resolved(rawValue: String) -> InterfaceFontSize {
        InterfaceFontSize(rawValue: rawValue) ?? .medium
    }

    static func stepped(rawValue: String, delta: Int) -> String {
        let sizes = allCases
        let currentSize = resolved(rawValue: rawValue)
        guard let currentIndex = sizes.firstIndex(of: currentSize) else {
            return defaultRawValue
        }

        let nextIndex = min(max(currentIndex + delta, sizes.startIndex), sizes.endIndex - 1)
        return sizes[nextIndex].rawValue
    }

    var pointSize: CGFloat {
        switch self {
        case .small:
            return 12
        case .medium:
            return 13
        case .large:
            return 14
        }
    }
}

extension Color {
    static func interfaceAccent(red: Double, green: Double, blue: Double) -> Color {
        Color(
            red: clampedUnit(red),
            green: clampedUnit(green),
            blue: clampedUnit(blue)
        )
    }
}

enum InterfaceMaterialStyle: String, CaseIterable {
    case solid
    case medium
    case liquid

    static var isLiquidSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }

        return false
    }

    static func resolved(rawValue: String) -> InterfaceMaterialStyle {
        switch rawValue {
        case solid.rawValue:
            return .solid
        case liquid.rawValue, "glass":
            return isLiquidSupported ? .liquid : .medium
        case medium.rawValue, "blur":
            return .medium
        default:
            return .medium
        }
    }

    static func normalizedRawValue(_ rawValue: String) -> String {
        resolved(rawValue: rawValue).rawValue
    }
}

struct InterfaceThemeSnapshot: Equatable {
    var accentRed: Double
    var accentGreen: Double
    var accentBlue: Double
    var accentActionPills: Bool
    var materialStyle: String
    var density: String
    var fontFamily: String
    var fontSize: String
    var lineHeight: String
    var messageLayout: String
    var showAvatars: Bool

    var accentColor: Color {
        .interfaceAccent(red: accentRed, green: accentGreen, blue: accentBlue)
    }
}

struct OverlaySettingsSnapshot: Equatable {
    var appearanceMode: String
    var liveAutoListen: Bool
    var liveLanguage: String
    var liveAudioSource: String
    var theme: InterfaceThemeSnapshot
}
