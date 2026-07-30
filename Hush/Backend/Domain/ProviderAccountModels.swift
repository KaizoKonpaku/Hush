import Foundation

enum ProviderValidationState: Equatable {
    case idle
    case validating
    case valid(modelCount: Int)
    case invalid(message: String)
}

enum ProviderAccountAuthMethod: String, CaseIterable, Codable, Hashable, Identifiable {
    case oauth
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oauth:
            return "Sign In"
        case .apiKey:
            return "API Key"
        }
    }

    var detailText: String {
        switch self {
        case .oauth:
            return "Stored locally on this Mac."
        case .apiKey:
            return "Stored on this Mac and used for provider requests."
        }
    }

    var requiresSecretEntry: Bool {
        self == .apiKey
    }
}

struct ProviderAccountLocalSecrets: Codable, Hashable, Sendable {
    var apiKey: String
    var adminKey: String

    static let empty = Self(apiKey: "", adminKey: "")
}

struct ProviderAccountRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let providerID: IntelligenceProviderID
    var authMethod: ProviderAccountAuthMethod
    var displayName: String
    var identifier: String
    var organizationID: String
    var projectID: String
    var usesKeychain: Bool
    var apiKeyPreview: String
    var adminKeyPreview: String
    var localSecrets: ProviderAccountLocalSecrets
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        providerID: IntelligenceProviderID,
        authMethod: ProviderAccountAuthMethod,
        displayName: String,
        identifier: String,
        organizationID: String = "",
        projectID: String = "",
        usesKeychain: Bool = true,
        apiKeyPreview: String = "",
        adminKeyPreview: String = "",
        localSecrets: ProviderAccountLocalSecrets = .empty,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.authMethod = authMethod
        self.displayName = displayName
        self.identifier = identifier
        self.organizationID = organizationID
        self.projectID = projectID
        self.usesKeychain = usesKeychain
        self.apiKeyPreview = apiKeyPreview
        self.adminKeyPreview = adminKeyPreview
        self.localSecrets = localSecrets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var methodTitle: String {
        authMethod.title
    }

    var maskedSecret: String {
        apiKeyPreview.isEmpty ? "No API key" : apiKeyPreview
    }

    var maskedAdminSecret: String {
        adminKeyPreview.isEmpty ? "No admin key" : adminKeyPreview
    }

    var hasAPIKeyConfigured: Bool {
        !apiKeyPreview.isEmpty || !localSecrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAdminKeyConfigured: Bool {
        !adminKeyPreview.isEmpty || !localSecrets.adminKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var summaryLine: String {
        switch providerID {
        case .openAI:
            var segments: [String] = []
            if !identifier.isEmpty {
                segments.append(identifier)
            }
            if !organizationID.isEmpty {
                segments.append(shortIdentifier(organizationID))
            }
            if !projectID.isEmpty {
                segments.append(shortIdentifier(projectID))
            }
            segments.append(maskedSecret)
            return segments.joined(separator: " · ")
        case _ where authMethod == .oauth:
            return identifier
        default:
            return identifier.isEmpty ? maskedSecret : "\(identifier) · \(maskedSecret)"
        }
    }

    private func shortIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 14 else { return trimmed }
        return "\(trimmed.prefix(8))...\(trimmed.suffix(4))"
    }
}

struct ProviderAccountUpsert {
    var record: ProviderAccountRecord
    var secrets: ProviderAccountLocalSecrets
}

enum ProviderAccountStatusKind: Equatable {
    case idle
    case refreshing
    case connected
    case limited
    case failed
}

struct ProviderAccountUsageSnapshot: Equatable {
    let modelCount: Int
    let spendText: String?
    let requestCount: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let organizationSummary: String?
    let projectSummary: String?
    let hasAdminKey: Bool

    var totalTokens: Int? {
        guard let inputTokens, let outputTokens else { return nil }
        return inputTokens + outputTokens
    }
}

struct ProviderAccountStatusSummary: Equatable {
    let kind: ProviderAccountStatusKind
    let title: String
    let detail: String
    let checkedAt: Date
    let usage: ProviderAccountUsageSnapshot?

    static func idle(
        detail: String = "No validation run yet.",
        usage: ProviderAccountUsageSnapshot? = nil
    ) -> Self {
        Self(kind: .idle, title: "Idle", detail: detail, checkedAt: Date(), usage: usage)
    }

    static func refreshing(
        detail: String = "Checking connection…",
        usage: ProviderAccountUsageSnapshot? = nil
    ) -> Self {
        Self(kind: .refreshing, title: "Refreshing", detail: detail, checkedAt: Date(), usage: usage)
    }

    static func connected(detail: String, usage: ProviderAccountUsageSnapshot? = nil) -> Self {
        Self(kind: .connected, title: "Connected", detail: detail, checkedAt: Date(), usage: usage)
    }

    static func limited(detail: String, usage: ProviderAccountUsageSnapshot? = nil) -> Self {
        Self(kind: .limited, title: "Connected", detail: detail, checkedAt: Date(), usage: usage)
    }

    static func failed(_ detail: String, usage: ProviderAccountUsageSnapshot? = nil) -> Self {
        Self(kind: .failed, title: "Connection Failed", detail: detail, checkedAt: Date(), usage: usage)
    }

    var isError: Bool {
        kind == .failed
    }
}
