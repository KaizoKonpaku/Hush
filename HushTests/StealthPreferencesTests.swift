import XCTest
@testable import Hush

final class StealthPreferencesTests: XCTestCase {
    func testLoadDefaultsLaunchWithoutFocusToTrue() {
        let suiteName = "StealthPreferencesTests.defaults.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = StealthPreferences.load(from: defaults)

        XCTAssertTrue(preferences.launchWithoutFocus)
        XCTAssertFalse(preferences.isEnabled)
    }

    func testLoadReadsStoredLaunchWithoutFocusPreference() {
        let suiteName = "StealthPreferencesTests.stored.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(true, forKey: "stealth.enabled")
        defaults.set(false, forKey: "stealth.launchWithoutFocus")

        let preferences = StealthPreferences.load(from: defaults)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertFalse(preferences.launchWithoutFocus)
    }
}
