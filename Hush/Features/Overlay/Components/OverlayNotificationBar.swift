import SwiftUI

struct OverlayNotificationBar: View {
    let notification: OverlayNotificationState
    let onDismiss: @MainActor () -> Void

    private var accent: Color {
        notification.accent ?? defaultAccent
    }

    private var defaultAccent: Color {
        switch notification.kind {
        case .info:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: notification.kind.iconName)
                .foregroundStyle(accent)
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.system(size: 11, weight: .semibold))
                Text(notification.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button("Dismiss") {
                Task { @MainActor in
                    onDismiss()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}
