import Foundation

struct OverlayErrorDescriptor {
    let title: String
    let message: String
}

enum OverlayRuntimeError: Error {
    case missingInput
    case alreadyProcessing
    case captureLimitReached
    case screenCapturePermissionDenied
    case captureFailed
    case attachmentImportFailed

    var descriptor: OverlayErrorDescriptor {
        switch self {
        case .missingInput:
            return OverlayErrorDescriptor(
                title: "Nothing to Process",
                message: "Add text or at least one capture before running Process."
            )
        case .alreadyProcessing:
            return OverlayErrorDescriptor(
                title: "Already Processing",
                message: "Wait for the current response to finish before starting another one."
            )
        case .captureLimitReached:
            return OverlayErrorDescriptor(
                title: "Capture Limit Reached",
                message: "You can attach up to 6 captures in one request."
            )
        case .screenCapturePermissionDenied:
            return OverlayErrorDescriptor(
                title: "Screen Capture Permission Required",
                message: "Enable Screen Recording permission in System Settings to add captures."
            )
        case .captureFailed:
            return OverlayErrorDescriptor(
                title: "Capture Failed",
                message: "Could not capture the screen. Try again."
            )
        case .attachmentImportFailed:
            return OverlayErrorDescriptor(
                title: "Attachment Failed",
                message: "Could not add the selected item. Try again."
            )
        }
    }
}
