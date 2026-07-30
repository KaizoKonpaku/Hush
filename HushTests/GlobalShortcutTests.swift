import Carbon
import XCTest
@testable import Hush

final class GlobalShortcutTests: XCTestCase {
    func testFromDefaultsFallsBackForMissingOrInvalidValues() {
        let defaultsKey = "tests.shortcuts.\(UUID().uuidString)"
        let fallback = GlobalShortcut.fallbackToggleOverlay
        defer {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }

        XCTAssertEqual(GlobalShortcut.fromDefaults(defaultsKey, fallback: fallback), fallback)

        UserDefaults.standard.set("not-json", forKey: defaultsKey)
        XCTAssertEqual(GlobalShortcut.fromDefaults(defaultsKey, fallback: fallback), fallback)
    }

    func testSaveAndLoadRoundTripsShortcut() {
        let defaultsKey = "tests.shortcuts.\(UUID().uuidString)"
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt(cmdKey | shiftKey)
        )
        defer {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }

        shortcut.save(to: defaultsKey)

        XCTAssertEqual(
            GlobalShortcut.fromDefaults(defaultsKey, fallback: .fallbackToggleOverlay),
            shortcut
        )
    }

    func testWindowManagementIncludesStealthOpacityShortcuts() {
        let actions = ShortcutSettingsGroup.windowManagement.actions

        XCTAssertTrue(actions.contains(.decreaseStealthOpacity))
        XCTAssertTrue(actions.contains(.increaseStealthOpacity))
        XCTAssertTrue(actions.contains(.resetStealthOpacity))
    }

    func testResultsNavigationNoLongerIncludesTextSizeShortcutRows() {
        let titles = ShortcutSettingsGroup.resultsNavigation.actions.map(\.title)

        XCTAssertFalse(titles.contains("Decrease text size"))
        XCTAssertFalse(titles.contains("Increase text size"))
        XCTAssertFalse(titles.contains("Reset text size"))
    }
}
