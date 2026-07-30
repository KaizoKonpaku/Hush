import AppKit
import Carbon
import Foundation

struct GlobalShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt

    static let fallbackToggleOverlay = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_H),
        modifiers: UInt(cmdKey)
    )

    static func fromDefaults(_ key: String, fallback: GlobalShortcut) -> GlobalShortcut {
        guard
            let raw = UserDefaults.standard.string(forKey: key),
            let data = raw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(GlobalShortcut.self, from: data)
        else {
            return fallback
        }
        return decoded
    }

    func save(to key: String) {
        guard
            let data = try? JSONEncoder().encode(self),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        UserDefaults.standard.set(raw, forKey: key)
    }

    var displayText: String {
        var symbols: [String] = []

        if modifiers & UInt(cmdKey) != 0 { symbols.append("⌘") }
        if modifiers & UInt(optionKey) != 0 { symbols.append("⌥") }
        if modifiers & UInt(controlKey) != 0 { symbols.append("⌃") }
        if modifiers & UInt(shiftKey) != 0, !shouldHideShiftSymbol { symbols.append("⇧") }

        return symbols.joined() + displayKeyName
    }

    var displayTokens: [String] {
        let modifierSymbols = ["⌘", "⌥", "⌃", "⇧"]
        let text = displayText
        var tokens: [String] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            let character = String(text[cursor])
            if modifierSymbols.contains(character) {
                tokens.append(character)
                cursor = text.index(after: cursor)
                continue
            }

            let remainder = String(text[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainder.isEmpty {
                tokens.append(remainder)
            }
            break
        }

        return tokens.isEmpty ? [text] : tokens
    }

    var carbonModifiers: UInt32 { UInt32(modifiers) }

    private var shouldHideShiftSymbol: Bool {
        modifiers & UInt(shiftKey) != 0 &&
        (modifiers & UInt(optionKey) != 0 || modifiers & UInt(controlKey) != 0) &&
        keyCode == UInt32(kVK_ANSI_Equal)
    }

    private var displayKeyName: String {
        let isShiftModified = modifiers & UInt(shiftKey) != 0

        if isShiftModified, keyCode == UInt32(kVK_ANSI_Equal) {
            return "+"
        }

        if isShiftModified, keyCode == UInt32(kVK_ANSI_Minus) {
            return "-"
        }

        return keyCodeDisplayName
    }

    private var keyCodeDisplayName: String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↵"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_T: return "T"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_ANSI_Keypad0: return "Num 0"
        case kVK_ANSI_Keypad1: return "Num 1"
        case kVK_ANSI_Keypad2: return "Num 2"
        case kVK_ANSI_Keypad3: return "Num 3"
        case kVK_ANSI_Keypad4: return "Num 4"
        case kVK_ANSI_Keypad5: return "Num 5"
        case kVK_ANSI_Keypad6: return "Num 6"
        case kVK_ANSI_Keypad7: return "Num 7"
        case kVK_ANSI_Keypad8: return "Num 8"
        case kVK_ANSI_Keypad9: return "Num 9"
        case kVK_ANSI_KeypadDecimal: return "Num ."
        case kVK_ANSI_KeypadMultiply: return "Num *"
        case kVK_ANSI_KeypadPlus: return "Num +"
        case kVK_ANSI_KeypadMinus: return "Num -"
        case kVK_ANSI_KeypadDivide: return "Num /"
        case kVK_ANSI_KeypadEnter: return "Num Enter"
        case kVK_ANSI_KeypadEquals: return "Num ="
        default:
            if let translated = Self.translatedKeyName(for: UInt16(keyCode)) {
                return translated
            }
            return "Key \(keyCode)"
        }
    }

    private static func translatedKeyName(for keyCode: UInt16) -> String? {
        guard
            let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(
                inputSource,
                kTISPropertyUnicodeKeyLayoutData
            )
        else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let layoutPtr = CFDataGetBytePtr(layoutData) else { return nil }

        let keyboardLayout = layoutPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 }
        var deadKeyState: UInt32 = 0
        var outputLength = 0
        var outputChars = [UniChar](repeating: 0, count: 4)

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            outputChars.count,
            &outputLength,
            &outputChars
        )

        guard status == noErr, outputLength > 0 else { return nil }
        let value = String(utf16CodeUnits: outputChars, count: outputLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value.uppercased()
    }
}

enum ShortcutDefaultsKey {
    static let toggleOverlay = "shortcuts.toggleOverlay"
    static let quickCapture = "shortcuts.quickCapture"
    static let openSettings = "shortcuts.openSettings"
    static let toggleStealth = "shortcuts.toggleStealth"
    static let decreaseStealthOpacity = "shortcuts.decreaseStealthOpacity"
    static let increaseStealthOpacity = "shortcuts.increaseStealthOpacity"
    static let resetStealthOpacity = "shortcuts.resetStealthOpacity"
    static let live = "shortcuts.live"
    static let cycleLiveMode = "shortcuts.cycleLiveMode"
    static let text = "shortcuts.text"
    static let capture = "shortcuts.capture"
    static let deleteCapture = "shortcuts.deleteCapture"
    static let process = "shortcuts.process"
    static let moveLeft = "shortcuts.moveLeft"
    static let moveRight = "shortcuts.moveRight"
    static let moveUp = "shortcuts.moveUp"
    static let moveDown = "shortcuts.moveDown"
    static let focusCapturePrevious = "shortcuts.focusCapturePrevious"
    static let focusCaptureNext = "shortcuts.focusCaptureNext"
    static let toggleAutoscroll = "shortcuts.toggleAutoscroll"
    static let resultsScrollUp = "shortcuts.resultsScrollUp"
    static let resultsScrollDown = "shortcuts.resultsScrollDown"
    static let hideUnhideFromScreen = "shortcuts.hideUnhideFromScreen"
    static let newSession = "shortcuts.newSession"
}

enum ShortcutSettingsGroup: String, CaseIterable, Identifiable {
    case modes = "Modes"
    case capture = "Capture"
    case windowManagement = "Window Management"
    case resultsNavigation = "Results Navigation"
    case app = "App"

    var id: String { rawValue }

    var footer: String {
        switch self {
        case .modes:
            return "Shortcuts for switching between the main HUSH workflows."
        case .capture:
            return "Capture shortcuts control screenshots, selection focus, and cleanup."
        case .windowManagement:
            return "Move, hide, and adjust the overlay with these window-level shortcuts."
        case .resultsNavigation:
            return "These shortcuts control the current answer view."
        case .app:
            return "App-level shortcuts open HUSH controls and toggle stealth mode."
        }
    }

    var actions: [GlobalShortcutAction] {
        GlobalShortcutAction.allCases.filter { $0.settingsGroup == self }
    }
}

enum GlobalShortcutAction: Int, CaseIterable {
    case toggleOverlay = 1
    case deleteCapture = 2
    case live = 3
    case cycleLiveMode = 4
    case text = 5
    case capture = 6
    case quickCapture = 7
    case openSettings = 8
    case toggleStealth = 9
    case decreaseStealthOpacity = 10
    case increaseStealthOpacity = 11
    case resetStealthOpacity = 12
    // Keep legacy hotkey IDs stable after removing the text-size shortcut actions.
    case moveLeft = 16
    case moveRight = 17
    case moveUp = 18
    case moveDown = 19
    case focusCapturePrevious = 20
    case focusCaptureNext = 21
    case toggleAutoscroll = 22
    case resultsScrollUp = 23
    case resultsScrollDown = 24
    case hideUnhideFromScreen = 25
    case process = 26
    case newSession = 27

    static var allCases: [GlobalShortcutAction] {
        [
            .deleteCapture,
            .live,
            .cycleLiveMode,
            .text,
            .process,
            .newSession,
            .capture,
            .quickCapture,
            .openSettings,
            .toggleStealth,
            .moveLeft,
            .moveRight,
            .moveUp,
            .moveDown,
            .hideUnhideFromScreen,
            .decreaseStealthOpacity,
            .increaseStealthOpacity,
            .resetStealthOpacity,
            .focusCapturePrevious,
            .focusCaptureNext,
            .toggleAutoscroll,
            .resultsScrollUp,
            .resultsScrollDown
        ]
    }

    var defaultsKey: String {
        switch self {
        case .toggleOverlay: return ShortcutDefaultsKey.toggleOverlay
        case .deleteCapture: return ShortcutDefaultsKey.deleteCapture
        case .live: return ShortcutDefaultsKey.live
        case .cycleLiveMode: return ShortcutDefaultsKey.cycleLiveMode
        case .text: return ShortcutDefaultsKey.text
        case .capture: return ShortcutDefaultsKey.capture
        case .quickCapture: return ShortcutDefaultsKey.quickCapture
        case .openSettings: return ShortcutDefaultsKey.openSettings
        case .toggleStealth: return ShortcutDefaultsKey.toggleStealth
        case .decreaseStealthOpacity: return ShortcutDefaultsKey.decreaseStealthOpacity
        case .increaseStealthOpacity: return ShortcutDefaultsKey.increaseStealthOpacity
        case .resetStealthOpacity: return ShortcutDefaultsKey.resetStealthOpacity
        case .moveLeft: return ShortcutDefaultsKey.moveLeft
        case .moveRight: return ShortcutDefaultsKey.moveRight
        case .moveUp: return ShortcutDefaultsKey.moveUp
        case .moveDown: return ShortcutDefaultsKey.moveDown
        case .focusCapturePrevious: return ShortcutDefaultsKey.focusCapturePrevious
        case .focusCaptureNext: return ShortcutDefaultsKey.focusCaptureNext
        case .toggleAutoscroll: return ShortcutDefaultsKey.toggleAutoscroll
        case .resultsScrollUp: return ShortcutDefaultsKey.resultsScrollUp
        case .resultsScrollDown: return ShortcutDefaultsKey.resultsScrollDown
        case .hideUnhideFromScreen: return ShortcutDefaultsKey.hideUnhideFromScreen
        case .process: return ShortcutDefaultsKey.process
        case .newSession: return ShortcutDefaultsKey.newSession
        }
    }

    var title: String {
        switch self {
        case .toggleOverlay: return "Hide / unhide overlay"
        case .deleteCapture: return "Delete focused screenshot"
        case .live: return "Switch to Live"
        case .cycleLiveMode: return "Cycle Live source mode"
        case .text: return "Switch to Text"
        case .capture: return "Capture full screen"
        case .quickCapture: return "Capture with picker"
        case .openSettings: return "Open / close app window"
        case .toggleStealth: return "Toggle stealth mode"
        case .decreaseStealthOpacity: return "Decrease stealth opacity"
        case .increaseStealthOpacity: return "Increase stealth opacity"
        case .resetStealthOpacity: return "Reset stealth opacity"
        case .moveLeft: return "Move overlay left"
        case .moveRight: return "Move overlay right"
        case .moveUp: return "Move overlay up"
        case .moveDown: return "Move overlay down"
        case .focusCapturePrevious: return "Focus previous capture"
        case .focusCaptureNext: return "Focus next capture"
        case .toggleAutoscroll: return "Toggle auto-scroll"
        case .resultsScrollUp: return "Results scroll up"
        case .resultsScrollDown: return "Results scroll down"
        case .hideUnhideFromScreen: return "Hide / unhide overlay"
        case .process: return "Process"
        case .newSession: return "New session"
        }
    }

    var defaultShortcut: GlobalShortcut {
        switch self {
        case .toggleOverlay:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt(cmdKey))
        case .deleteCapture:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt(cmdKey))
        case .live:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt(cmdKey))
        case .cycleLiveMode:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt(cmdKey | shiftKey))
        case .text:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt(cmdKey))
        case .capture:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt(cmdKey))
        case .quickCapture:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt(cmdKey | controlKey))
        case .openSettings:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_Comma), modifiers: UInt(cmdKey))
        case .toggleStealth:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt(cmdKey | shiftKey))
        case .decreaseStealthOpacity:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_Minus), modifiers: UInt(cmdKey | controlKey))
        case .increaseStealthOpacity:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_Equal), modifiers: UInt(cmdKey | controlKey | shiftKey))
        case .resetStealthOpacity:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_0), modifiers: UInt(cmdKey | controlKey))
        case .moveLeft:
            return GlobalShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt(cmdKey))
        case .moveRight:
            return GlobalShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: UInt(cmdKey))
        case .moveUp:
            return GlobalShortcut(keyCode: UInt32(kVK_UpArrow), modifiers: UInt(cmdKey))
        case .moveDown:
            return GlobalShortcut(keyCode: UInt32(kVK_DownArrow), modifiers: UInt(cmdKey))
        case .focusCapturePrevious:
            return GlobalShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt(cmdKey | controlKey))
        case .focusCaptureNext:
            return GlobalShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: UInt(cmdKey | controlKey))
        case .toggleAutoscroll:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt(cmdKey))
        case .resultsScrollUp:
            return GlobalShortcut(keyCode: UInt32(kVK_UpArrow), modifiers: UInt(cmdKey | shiftKey))
        case .resultsScrollDown:
            return GlobalShortcut(keyCode: UInt32(kVK_DownArrow), modifiers: UInt(cmdKey | shiftKey))
        case .hideUnhideFromScreen:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt(cmdKey))
        case .process:
            return GlobalShortcut(keyCode: UInt32(kVK_Return), modifiers: UInt(cmdKey))
        case .newSession:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt(cmdKey))
        }
    }

    var settingsGroup: ShortcutSettingsGroup {
        switch self {
        case .live, .cycleLiveMode, .text, .process, .newSession:
            return .modes
        case .capture, .quickCapture, .deleteCapture, .focusCapturePrevious, .focusCaptureNext:
            return .capture
        case .moveLeft, .moveRight, .moveUp, .moveDown, .hideUnhideFromScreen,
             .decreaseStealthOpacity, .increaseStealthOpacity, .resetStealthOpacity:
            return .windowManagement
        case .toggleAutoscroll, .resultsScrollUp, .resultsScrollDown:
            return .resultsNavigation
        case .toggleOverlay, .openSettings, .toggleStealth:
            return .app
        }
    }

    var searchKeywords: [String] {
        var keywords = ["shortcut", "hotkey", "keyboard", "command", settingsGroup.rawValue]

        switch self {
        case .toggleOverlay, .hideUnhideFromScreen:
            keywords += ["overlay", "show overlay", "hide overlay"]
        case .toggleStealth:
            keywords += ["stealth", "privacy mode", "discreet"]
        case .decreaseStealthOpacity:
            keywords += ["stealth opacity", "window opacity", "reduce opacity", "lower opacity", "make more transparent"]
        case .increaseStealthOpacity:
            keywords += ["stealth opacity", "window opacity", "increase opacity", "raise opacity", "make less transparent"]
        case .resetStealthOpacity:
            keywords += ["stealth opacity", "window opacity", "reset opacity", "default opacity", "restore opacity"]
        case .openSettings:
            keywords += ["app window", "show app", "hide app", "toggle window", "workspace window"]
        case .capture, .quickCapture, .deleteCapture, .focusCapturePrevious, .focusCaptureNext:
            keywords += ["screenshot", "capture"]
        case .live, .cycleLiveMode:
            keywords += ["live mode", "audio", "transcription"]
        case .text:
            keywords += ["text mode", "typing"]
        case .process:
            keywords += ["submit", "run", "process prompt"]
        case .newSession:
            keywords += ["new chat", "new conversation", "reset conversation"]
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            keywords += ["move window", "reposition overlay"]
        case .toggleAutoscroll, .resultsScrollUp, .resultsScrollDown:
            keywords += ["results", "scroll", "autoscroll", "answer view"]
        }

        return keywords
    }
}
