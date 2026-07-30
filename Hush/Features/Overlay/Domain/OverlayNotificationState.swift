import SwiftUI

enum OverlayNotificationKind {
    case info
    case success
    case error

    var iconName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct OverlayNotificationState: Identifiable {
    let id = UUID()
    let kind: OverlayNotificationKind
    let title: String
    let message: String
    let accent: Color?
}
