import SwiftUI

struct MainWindowRuntimeSyncState: Equatable {
    var launchAtLogin: Bool
    var showInMenuBar: Bool
    var navPosition: String
    var navMultiMonitor: String
    var navSnapToEdges: Bool
    var navAutoHide: String
    var navTrackpadGestures: Bool
    var navKeyboardNavigation: Bool
    var navFocusInputOnOpen: Bool
    var stealthEnabled: Bool
    var stealthStayOnTop: Bool
    var stealthHideFromDock: Bool
    var stealthHideFromActivityWindow: Bool
    var stealthHideFromMissionControl: Bool
    var stealthHideFromStageManager: Bool
    var stealthOpacity: Double
    var stealthMousePassthrough: Bool
    var stealthNoWindowShadow: Bool
    var stealthHideFromScreenCapture: Bool
    var stealthSuppressNotificationHistory: Bool
    var stealthSuppressRecentItemsAndHandoff: Bool
    var stealthMenuBarVisibility: String
}

extension MainWindowView {
    var resolvedThemeMaterialStyle: String {
        InterfaceMaterialStyle.normalizedRawValue(themesMaterialStyle)
    }

    var themeMaterialStyleBinding: Binding<String> {
        Binding(
            get: { resolvedThemeMaterialStyle },
            set: { themesMaterialStyle = InterfaceMaterialStyle.normalizedRawValue($0) }
        )
    }

    var themesAccentColor: Color {
        .interfaceAccent(red: themesAccentRed, green: themesAccentGreen, blue: themesAccentBlue)
    }

    var assistantTheme: InterfaceThemeSnapshot {
        InterfaceThemeSnapshot(
            accentRed: themesAccentRed,
            accentGreen: themesAccentGreen,
            accentBlue: themesAccentBlue,
            accentActionPills: themesAccentActionPills,
            materialStyle: resolvedThemeMaterialStyle,
            density: themesDensity,
            fontFamily: themesFontFamily,
            fontSize: themesFontSize,
            lineHeight: themesLineHeight,
            messageLayout: themesMessageLayout,
            showAvatars: themesShowAvatars
        )
    }

    var runtimeSyncState: MainWindowRuntimeSyncState {
        MainWindowRuntimeSyncState(
            launchAtLogin: generalLaunchAtLogin,
            showInMenuBar: generalShowInMenuBar,
            navPosition: navPosition,
            navMultiMonitor: navMultiMonitor,
            navSnapToEdges: navSnapToEdges,
            navAutoHide: navAutoHide,
            navTrackpadGestures: navTrackpadGestures,
            navKeyboardNavigation: navKeyboardNavigation,
            navFocusInputOnOpen: navFocusInputOnOpen,
            stealthEnabled: stealthEnabled,
            stealthStayOnTop: stealthStayOnTop,
            stealthHideFromDock: stealthHideFromDock,
            stealthHideFromActivityWindow: stealthHideFromActivityWindow,
            stealthHideFromMissionControl: stealthHideFromMissionControl,
            stealthHideFromStageManager: stealthHideFromStageManager,
            stealthOpacity: stealthOpacity,
            stealthMousePassthrough: stealthMousePassthrough,
            stealthNoWindowShadow: stealthNoWindowShadow,
            stealthHideFromScreenCapture: stealthHideFromScreenCapture,
            stealthSuppressNotificationHistory: stealthSuppressNotificationHistory,
            stealthSuppressRecentItemsAndHandoff: stealthSuppressRecentItemsAndHandoff,
            stealthMenuBarVisibility: stealthMenuBarVisibility
        )
    }

    func applyAccentPreset(_ preset: String) {
        let nextValues: (Double, Double, Double)

        switch preset {
        case "blue":
            nextValues = (0.0, 0.48, 1.0)
        case "green":
            nextValues = (0.18, 0.65, 0.33)
        case "orange":
            nextValues = (0.96, 0.52, 0.15)
        case "red":
            nextValues = (0.89, 0.23, 0.21)
        case "purple":
            nextValues = (0.53, 0.35, 0.91)
        case "pink":
            nextValues = (0.91, 0.29, 0.57)
        case "gray":
            nextValues = (0.45, 0.45, 0.47)
        default:
            nextValues = (0.0, 0.48, 1.0)
        }

        guard themesAccentRed != nextValues.0 ||
                themesAccentGreen != nextValues.1 ||
                themesAccentBlue != nextValues.2 else {
            return
        }

        themesAccentRed = nextValues.0
        themesAccentGreen = nextValues.1
        themesAccentBlue = nextValues.2
    }
}
