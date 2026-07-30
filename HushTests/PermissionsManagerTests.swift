import AVFoundation
import Speech
import XCTest
@testable import Hush

final class PermissionsManagerTests: XCTestCase {
    func testMicrophoneAuthorizationStatusMapping() {
        XCTAssertEqual(AppPermissionAccess.mapMicrophoneAuthorizationStatus(.authorized), .granted)
        XCTAssertEqual(AppPermissionAccess.mapMicrophoneAuthorizationStatus(.notDetermined), .notDetermined)
        XCTAssertEqual(AppPermissionAccess.mapMicrophoneAuthorizationStatus(.denied), .denied)
        XCTAssertEqual(AppPermissionAccess.mapMicrophoneAuthorizationStatus(.restricted), .restricted)
    }

    func testSpeechAuthorizationStatusMapping() {
        XCTAssertEqual(AppPermissionAccess.mapSpeechRecognitionAuthorizationStatus(.authorized), .granted)
        XCTAssertEqual(AppPermissionAccess.mapSpeechRecognitionAuthorizationStatus(.notDetermined), .notDetermined)
        XCTAssertEqual(AppPermissionAccess.mapSpeechRecognitionAuthorizationStatus(.denied), .denied)
        XCTAssertEqual(AppPermissionAccess.mapSpeechRecognitionAuthorizationStatus(.restricted), .restricted)
    }

    func testResolutionActionMatchesPermissionState() {
        XCTAssertEqual(AppPermissionState.granted.resolutionAction, .none)
        XCTAssertEqual(AppPermissionState.restricted.resolutionAction, .none)
        XCTAssertEqual(AppPermissionState.notDetermined.resolutionAction, .request)
        XCTAssertEqual(AppPermissionState.needsApproval.resolutionAction, .request)
        XCTAssertEqual(AppPermissionState.denied.resolutionAction, .openSystemSettings)

        XCTAssertNil(AppPermissionState.granted.resolutionAction.buttonTitle)
        XCTAssertEqual(AppPermissionState.needsApproval.resolutionAction.buttonTitle, "Request")
        XCTAssertEqual(AppPermissionState.denied.resolutionAction.buttonTitle, "Open Settings")
    }
}
