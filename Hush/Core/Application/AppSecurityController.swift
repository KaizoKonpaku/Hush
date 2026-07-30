import Foundation
import LocalAuthentication
import Observation

@MainActor
@Observable
final class AppSecurityController {
    private enum DefaultsKey {
        static let protectionEnabled = "accounts.lockWithPassword"
        static let approvalTimeout = "accounts.lockTimeout"
    }
    private struct AuthenticationResult {
        let success: Bool
        let error: Error?
    }

    var isAuthenticating = false
    var authorizationErrorMessage: String?

    private var lastApprovedAt: Date?
    private var activeAuthorizationSessionCount = 0

    var isProtectionEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.protectionEnabled)
    }

    func refreshConfiguration() {
        guard isProtectionEnabled else {
            clearApproval()
            return
        }

        if isApprovalStillValid == false {
            lastApprovedAt = nil
        }
    }

    func clearApproval() {
        isAuthenticating = false
        authorizationErrorMessage = nil
        lastApprovedAt = nil
        activeAuthorizationSessionCount = 0
    }

    func clearAuthorizationError() {
        authorizationErrorMessage = nil
    }

    func beginAuthorizationSession() {
        activeAuthorizationSessionCount += 1
        authorizationErrorMessage = nil
    }

    func endAuthorizationSession() {
        activeAuthorizationSessionCount = max(0, activeAuthorizationSessionCount - 1)
    }

    @discardableResult
    func authorizeAccountAccessIfNeeded(
        reason: String,
        requireFreshApproval: Bool = false
    ) async -> Bool {
        refreshConfiguration()
        guard isProtectionEnabled else { return true }
        if requireFreshApproval == false {
            guard activeAuthorizationSessionCount == 0 else { return true }
            guard isApprovalStillValid == false else { return true }
        }
        guard isAuthenticating == false else { return false }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            authorizationErrorMessage = availabilityError?.localizedDescription ?? "Touch ID or your Mac password is not available right now."
            return false
        }

        isAuthenticating = true
        authorizationErrorMessage = nil

        let result: AuthenticationResult = await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, error in
                continuation.resume(returning: AuthenticationResult(success: success, error: error))
            }
        }

        isAuthenticating = false

        if result.success {
            lastApprovedAt = Date()
            authorizationErrorMessage = nil
            return true
        }

        authorizationErrorMessage = errorMessage(for: result.error)
        return false
    }

    private var approvalTimeoutInterval: TimeInterval? {
        switch UserDefaults.standard.string(forKey: DefaultsKey.approvalTimeout) ?? "5min" {
        case "immediate":
            return .zero
        case "1min":
            return 60
        case "5min":
            return 300
        case "30min":
            return 1800
        default:
            return 300
        }
    }

    private var isApprovalStillValid: Bool {
        guard let lastApprovedAt, let approvalTimeoutInterval else { return false }
        guard approvalTimeoutInterval > 0 else { return false }
        return Date().timeIntervalSince(lastApprovedAt) < approvalTimeoutInterval
    }

    private func errorMessage(for error: Error?) -> String? {
        guard let error else {
            return "Authentication is still required."
        }

        if let localAuthenticationError = error as? LAError {
            switch localAuthenticationError.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
                return nil
            default:
                break
            }
        }

        return error.localizedDescription
    }
}
