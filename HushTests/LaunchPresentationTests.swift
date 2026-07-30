import XCTest
@testable import Hush

final class LaunchPresentationTests: XCTestCase {
    func testInitialBehaviorMatchesPresentationMode() {
        XCTAssertEqual(
            LaunchPresentation.window.initialBehavior,
            LaunchPresentationBehavior(showsMainWindow: true, showsOverlay: false)
        )
        XCTAssertEqual(
            LaunchPresentation.overlay.initialBehavior,
            LaunchPresentationBehavior(showsMainWindow: false, showsOverlay: true)
        )
        XCTAssertEqual(
            LaunchPresentation.windowAndOverlay.initialBehavior,
            LaunchPresentationBehavior(showsMainWindow: true, showsOverlay: true)
        )
    }

    func testLoadUsesStoredValueAndFallsBackToWindow() {
        let suiteName = "LaunchPresentationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated defaults suite")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(LaunchPresentation.load(from: defaults), .window)

        defaults.set(LaunchPresentation.overlay.rawValue, forKey: "general.launchPresentation")
        XCTAssertEqual(LaunchPresentation.load(from: defaults), .overlay)

        defaults.set("unknown", forKey: "general.launchPresentation")
        XCTAssertEqual(LaunchPresentation.load(from: defaults), .window)
    }
}
