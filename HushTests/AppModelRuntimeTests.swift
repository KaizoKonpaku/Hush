import CoreGraphics
import Foundation
import XCTest
@testable import Hush

@MainActor
final class AppModelRuntimeTests: XCTestCase {
    func testShowMainWindowRequestsRouteOnceWhenRuntimeActionIsInstalled() {
        let appModel = AppModel.shared
        var receivedRoutes: [MainWindowRoute] = []

        appModel.installRuntimeActions(
            showMainWindow: { route in
                receivedRoutes.append(route)
                appModel.requestMainWindow(route)
            },
            toggleMainWindow: { route in
                appModel.requestMainWindow(route)
            },
            hideMainWindow: { },
            toggleOverlay: { },
            updateOverlayContentSize: { _ in },
            syncRuntimeAction: { _ in }
        )

        let startingRequestID = appModel.mainWindowRouteRequestID

        appModel.showMainWindow(.sessions)

        XCTAssertEqual(receivedRoutes, [.sessions])
        XCTAssertEqual(appModel.mainWindowRoute, .sessions)
        XCTAssertEqual(appModel.mainWindowRouteRequestID, startingRequestID + 1)
    }

    func testShortcutSyncBumpsShortcutConfigurationVersionOnlyForShortcutUpdates() {
        let appModel = AppModel.shared
        appModel.installRuntimeActions(
            showMainWindow: { _ in },
            toggleMainWindow: { _ in },
            hideMainWindow: { },
            toggleOverlay: { },
            updateOverlayContentSize: { _ in },
            syncRuntimeAction: { _ in }
        )

        let startingVersion = appModel.shortcutConfigurationVersion

        appModel.syncRuntime(.menuBar)
        XCTAssertEqual(appModel.shortcutConfigurationVersion, startingVersion)

        appModel.syncRuntime(.shortcuts)
        XCTAssertEqual(appModel.shortcutConfigurationVersion, startingVersion + 1)
    }

    func testIntelligencePreferencesMigrationSeedsMockSelections() {
        let suiteName = "hush-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("openai::gpt-5", forKey: "intel.defaultModel")
        defaults.set("anthropic::claude-sonnet-4", forKey: "intel.fastModel")
        defaults.set("google::gemini-2.5-pro", forKey: "intel.advancedModel")

        IntelligencePreferencesMigration.migrateIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: "accounts.primaryProvider"), IntelligenceProviderID.mock.rawValue)
        XCTAssertEqual(defaults.string(forKey: "accounts.enabledProviders"), IntelligenceProviderID.mock.rawValue)
        XCTAssertEqual(defaults.string(forKey: "intel.defaultModel"), AssistantModelCatalog.mockStorageValue)
        XCTAssertEqual(defaults.string(forKey: "intel.fastModel"), AssistantModelCatalog.mockStorageValue)
        XCTAssertEqual(defaults.string(forKey: "intel.advancedModel"), AssistantModelCatalog.mockStorageValue)
        XCTAssertEqual(defaults.string(forKey: "assistant.selectedModelMode"), AssistantModelMode.defaultMode.rawValue)
    }
}
