import Combine
import Foundation

@MainActor
final class ProviderAccountStore: ObservableObject {
    static let shared = ProviderAccountStore()

    @Published private(set) var modelsByProvider: [IntelligenceProviderID: [AssistantModelOption]] = [:]
    @Published private(set) var validationStates: [IntelligenceProviderID: ProviderValidationState] = [:]
    @Published private(set) var accounts: [ProviderAccountRecord] = []
    @Published private(set) var accountStatuses: [UUID: ProviderAccountStatusSummary] = [:]

    private let defaults = UserDefaults.standard
    private let secretStore = KeychainSecretStore.shared
    private let openAIService = OpenAIService.shared
    private let storageKey = "accounts.providerRecords.v2"
    private let legacyStorageKey = "accounts.mockProviderRecords.v1"
    private let automaticRefreshInterval: TimeInterval = 45

    private var loadedOpenAIModels: [AssistantModelOption] = []
    private var loadedOpenAIRealtimeModels: [AssistantModelOption] = []
    private var loadedOpenAIRealtimeTranscriptionModels: [AssistantModelOption] = []
    private var isRefreshingConfiguredProviders = false
    private var lastConfiguredProvidersRefreshAt: Date?

    private init() {
        loadAccounts()
        syncState()
        repairStoredSelectionsIfNeeded()
    }

    var availableModels: [AssistantModelOption] {
        IntelligenceProviderID.connectableProviders.flatMap { models(for: $0) }
    }

    var availableRealtimeModels: [AssistantModelOption] {
        realtimeModels(for: .openAI)
    }

    var availableRealtimeTranscriptionModels: [AssistantModelOption] {
        realtimeTranscriptionModels(for: .openAI)
    }

    func models(for providerID: IntelligenceProviderID) -> [AssistantModelOption] {
        switch providerID {
        case .mock:
            return []
        case .openAI:
            guard !accounts(for: providerID).isEmpty else { return [] }
            if !loadedOpenAIModels.isEmpty {
                return loadedOpenAIModels
            }

            switch validationStates[.openAI] ?? .idle {
            case .idle, .validating:
                return AssistantModelCatalog.defaultModels(for: .openAI)
            case .valid, .invalid:
                return []
            }
        default:
            guard !accounts(for: providerID).isEmpty else { return [] }
            return AssistantModelCatalog.defaultModels(for: providerID)
        }
    }

    func realtimeModels(for providerID: IntelligenceProviderID) -> [AssistantModelOption] {
        switch providerID {
        case .openAI:
            guard !accounts(for: providerID).isEmpty else { return [] }
            if !loadedOpenAIRealtimeModels.isEmpty {
                return loadedOpenAIRealtimeModels
            }

            switch validationStates[.openAI] ?? .idle {
            case .idle, .validating:
                return AssistantModelCatalog.defaultRealtimeModels(for: .openAI)
            case .valid, .invalid:
                return []
            }
        case .mock, .google, .anthropic, .x:
            return []
        }
    }

    func realtimeTranscriptionModels(for providerID: IntelligenceProviderID) -> [AssistantModelOption] {
        switch providerID {
        case .openAI:
            guard !accounts(for: providerID).isEmpty else { return [] }
            if !loadedOpenAIRealtimeTranscriptionModels.isEmpty {
                return loadedOpenAIRealtimeTranscriptionModels
            }

            switch validationStates[.openAI] ?? .idle {
            case .idle, .validating:
                return AssistantModelCatalog.defaultRealtimeTranscriptionModels(for: .openAI)
            case .valid, .invalid:
                return []
            }
        case .mock, .google, .anthropic, .x:
            return []
        }
    }

    func accounts(for providerID: IntelligenceProviderID) -> [ProviderAccountRecord] {
        accounts
            .filter { $0.providerID == providerID }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func primaryAccount(for providerID: IntelligenceProviderID) -> ProviderAccountRecord? {
        accounts(for: providerID).first
    }

    func statusSummary(for account: ProviderAccountRecord) -> ProviderAccountStatusSummary {
        accountStatuses[account.id] ?? .idle()
    }

    func validationState(for providerID: IntelligenceProviderID) -> ProviderValidationState {
        validationStates[providerID] ?? .idle
    }

    func secrets(for account: ProviderAccountRecord) -> ProviderAccountLocalSecrets {
        if account.usesKeychain {
            return ProviderAccountLocalSecrets(
                apiKey: secretStore.loadSecret(for: account.id, providerID: account.providerID, slot: .apiKey),
                adminKey: secretStore.loadSecret(for: account.id, providerID: account.providerID, slot: .adminKey)
            )
        }

        return account.localSecrets
    }

    func refreshConfiguredProviders(
        using apiKeys: [IntelligenceProviderID: String] = [:],
        force: Bool = false
    ) async {
        if isRefreshingConfiguredProviders {
            return
        }

        if !force,
           let lastConfiguredProvidersRefreshAt,
           Date().timeIntervalSince(lastConfiguredProvidersRefreshAt) < automaticRefreshInterval {
            return
        }

        isRefreshingConfiguredProviders = true
        defer {
            isRefreshingConfiguredProviders = false
            lastConfiguredProvidersRefreshAt = Date()
        }

        loadAccounts()
        syncState()
        repairStoredSelectionsIfNeeded()

        await refreshOpenAIAccounts(force: force)

        for providerID in IntelligenceProviderID.connectableProviders where providerID != .openAI {
            for account in accounts(for: providerID) {
                accountStatuses[account.id] = .connected(detail: "Stored locally for UI testing in this build.")
            }
        }

        syncState()
        repairStoredSelectionsIfNeeded()
    }

    func resetValidation(for providerID: IntelligenceProviderID) {
        syncState()
    }

    func validate(providerID: IntelligenceProviderID, apiKey: String) async {
        guard providerID == .openAI else {
            validationStates[providerID] = .valid(modelCount: AssistantModelCatalog.defaultModels(for: providerID).count)
            return
        }

        let temporaryRecord = ProviderAccountRecord(
            providerID: providerID,
            authMethod: .apiKey,
            displayName: "OpenAI",
            identifier: "Temporary validation",
            usesKeychain: false,
            apiKeyPreview: maskedPreview(for: apiKey)
        )
        let temporarySecrets = ProviderAccountLocalSecrets(apiKey: apiKey, adminKey: "")

        validationStates[providerID] = .validating
        do {
            let result = try await openAIService.refreshAccount(record: temporaryRecord, secrets: temporarySecrets)
            validationStates[providerID] = .valid(modelCount: result.models.count)
        } catch {
            validationStates[providerID] = .invalid(message: error.localizedDescription)
        }
    }

    func saveAccount(_ upsert: ProviderAccountUpsert) {
        var record = upsert.record
        let trimmedSecrets = ProviderAccountLocalSecrets(
            apiKey: upsert.secrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            adminKey: upsert.secrets.adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        record.apiKeyPreview = maskedPreview(for: trimmedSecrets.apiKey)
        record.adminKeyPreview = maskedPreview(for: trimmedSecrets.adminKey)

        if record.usesKeychain {
            let savedAPIKey = secretStore.save(trimmedSecrets.apiKey, for: record.id, providerID: record.providerID, slot: .apiKey)
            let savedAdminKey = secretStore.save(trimmedSecrets.adminKey, for: record.id, providerID: record.providerID, slot: .adminKey)
            if savedAPIKey && savedAdminKey {
                record.localSecrets = .empty
            } else {
                record.usesKeychain = false
                record.localSecrets = trimmedSecrets
            }
        } else {
            record.localSecrets = trimmedSecrets
            secretStore.deleteSecrets(for: record.id, providerID: record.providerID)
        }

        if let index = accounts.firstIndex(where: { $0.id == record.id }) {
            accounts[index] = record
        } else {
            accounts.append(record)
        }

        accountStatuses[record.id] = .refreshing()
        persistAccounts()
        syncState()
        repairStoredSelectionsIfNeeded()

        Task { @MainActor [weak self] in
            await self?.refreshConfiguredProviders(force: true)
        }
    }

    func deleteAccount(_ record: ProviderAccountRecord) {
        accounts.removeAll { $0.id == record.id }
        accountStatuses.removeValue(forKey: record.id)
        secretStore.deleteSecrets(for: record.id, providerID: record.providerID)
        persistAccounts()
        syncState()
        repairStoredSelectionsIfNeeded()
    }

    func repairStoredSelectionsIfNeeded() {
        let fallbackModelValue = availableModels.first?.storageValue ?? ""
        let fallbackRealtimeModelValue = availableRealtimeModels.first?.storageValue ?? ""
        let fallbackRealtimeTranscriptionModelValue = availableRealtimeTranscriptionModels.first?.storageValue ?? ""
        let defaults = UserDefaults.standard

        repairStoredSelection(
            key: "intel.defaultModel",
            fallbackModelValue: fallbackModelValue,
            defaults: defaults
        )
        repairStoredSelection(
            key: "intel.fastModel",
            fallbackModelValue: fallbackModelValue,
            defaults: defaults
        )
        repairStoredSelection(
            key: "intel.advancedModel",
            fallbackModelValue: fallbackModelValue,
            defaults: defaults
        )
        repairStoredSelection(
            key: "intel.realtimeModel",
            fallbackModelValue: fallbackRealtimeModelValue,
            defaults: defaults
        )
        repairStoredSelection(
            key: "intel.realtimeTranscriptionModel",
            fallbackModelValue: fallbackRealtimeTranscriptionModelValue,
            defaults: defaults
        )
    }

    private func refreshOpenAIAccounts(force: Bool) async {
        let openAIAccounts = accounts(for: .openAI)
        guard !openAIAccounts.isEmpty else {
            loadedOpenAIModels = []
            loadedOpenAIRealtimeModels = []
            loadedOpenAIRealtimeTranscriptionModels = []
            validationStates[.openAI] = .idle
            return
        }

        let previousModels = loadedOpenAIModels
        let previousRealtimeModels = loadedOpenAIRealtimeModels
        let previousRealtimeTranscriptionModels = loadedOpenAIRealtimeTranscriptionModels
        let previousStatuses = accountStatuses
        let hadValidatedModels = previousModels.isEmpty == false

        if force || !hadValidatedModels {
            validationStates[.openAI] = .validating
        }

        var aggregatedModels = Set<AssistantModelOption>()
        var aggregatedRealtimeModels = Set<AssistantModelOption>()
        var aggregatedRealtimeTranscriptionModels = Set<AssistantModelOption>()
        var lastFailureMessage: String?

        for account in openAIAccounts {
            let previousStatus = previousStatuses[account.id]
            if force || shouldShowRefreshingStatus(previousStatus) {
                accountStatuses[account.id] = .refreshing()
            }
        }

        for account in openAIAccounts {
            do {
                let result = try await openAIService.refreshAccount(record: account, secrets: secrets(for: account))
                aggregatedModels.formUnion(result.models)
                aggregatedRealtimeModels.formUnion(result.realtimeModels)
                aggregatedRealtimeTranscriptionModels.formUnion(result.realtimeTranscriptionModels)
                accountStatuses[account.id] = result.status
            } catch {
                lastFailureMessage = error.localizedDescription
                if force || shouldShowFailureStatus(previousStatuses[account.id]) {
                    accountStatuses[account.id] = .failed(error.localizedDescription)
                } else if let previousStatus = previousStatuses[account.id] {
                    accountStatuses[account.id] = previousStatus
                }
            }
        }

        if aggregatedModels.isEmpty {
            if !force, hadValidatedModels {
                loadedOpenAIModels = previousModels
                loadedOpenAIRealtimeModels = previousRealtimeModels
                loadedOpenAIRealtimeTranscriptionModels = previousRealtimeTranscriptionModels
                validationStates[.openAI] = .valid(modelCount: previousModels.count)
            } else {
                loadedOpenAIModels = []
                loadedOpenAIRealtimeModels = []
                loadedOpenAIRealtimeTranscriptionModels = []
                validationStates[.openAI] = .invalid(message: lastFailureMessage ?? "OpenAI validation failed.")
            }
        } else {
            loadedOpenAIModels = AssistantModelCatalog.openAIModelOptions(from: aggregatedModels.map(\.modelID))
            loadedOpenAIRealtimeModels = AssistantModelCatalog.openAIRealtimeModelOptions(
                from: aggregatedRealtimeModels.map(\.modelID)
            )
            loadedOpenAIRealtimeTranscriptionModels = AssistantModelCatalog.openAIRealtimeTranscriptionModelOptions(
                from: aggregatedRealtimeTranscriptionModels.map(\.modelID)
            )
            validationStates[.openAI] = .valid(modelCount: loadedOpenAIModels.count)
        }
    }

    private func shouldShowRefreshingStatus(_ status: ProviderAccountStatusSummary?) -> Bool {
        guard let status else { return true }
        switch status.kind {
        case .idle, .failed:
            return true
        case .refreshing, .connected, .limited:
            return false
        }
    }

    private func shouldShowFailureStatus(_ status: ProviderAccountStatusSummary?) -> Bool {
        guard let status else { return true }
        switch status.kind {
        case .idle, .failed, .refreshing:
            return true
        case .connected, .limited:
            return false
        }
    }

    private func syncState() {
        var nextModels: [IntelligenceProviderID: [AssistantModelOption]] = [:]
        var nextValidationStates: [IntelligenceProviderID: ProviderValidationState] = [:]

        for providerID in IntelligenceProviderID.connectableProviders {
            let providerAccounts = accounts(for: providerID)
            guard !providerAccounts.isEmpty else {
                nextValidationStates[providerID] = .idle
                continue
            }

            let providerModels = models(for: providerID)
            if !providerModels.isEmpty {
                nextModels[providerID] = providerModels
            }

            if providerID == .openAI {
                nextValidationStates[providerID] = validationStates[providerID]
                    ?? (providerModels.isEmpty ? .idle : .valid(modelCount: providerModels.count))
            } else {
                nextValidationStates[providerID] = .valid(modelCount: providerModels.count)
            }
        }

        modelsByProvider = nextModels
        validationStates = nextValidationStates
    }

    private func repairStoredSelection(
        key: String,
        fallbackModelValue: String,
        defaults: UserDefaults
    ) {
        let currentValue = defaults.string(forKey: key) ?? ""
        if let decoded = AssistantModelCatalog.decodeStorageValue(currentValue) {
            let normalizedValue = AssistantModelCatalog.storageValue(
                providerID: decoded.providerID,
                modelID: decoded.modelID
            )

            if currentValue != normalizedValue {
                defaults.set(normalizedValue, forKey: key)
            }
            return
        }

        defaults.set(fallbackModelValue, forKey: key)
    }

    private func loadAccounts() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode([ProviderAccountRecord].self, from: data) {
            accounts = decoded.filter { $0.providerID != .mock }
            return
        }

        guard let legacyData = defaults.data(forKey: legacyStorageKey),
              let legacyAccounts = try? decoder.decode([LegacyProviderAccountRecord].self, from: legacyData) else {
            accounts = []
            return
        }

        accounts = legacyAccounts
            .filter { $0.providerID != .mock }
            .map {
                ProviderAccountRecord(
                    id: $0.id,
                    providerID: $0.providerID,
                    authMethod: $0.authMethod,
                    displayName: $0.displayName,
                    identifier: $0.identifier,
                    usesKeychain: false,
                    apiKeyPreview: maskedPreview(for: $0.secret),
                    localSecrets: ProviderAccountLocalSecrets(apiKey: $0.secret, adminKey: ""),
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
    }

    private func persistAccounts() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(accounts) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func maskedPreview(for secret: String) -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let prefix = String(trimmed.prefix(4))
        let suffix = String(trimmed.suffix(min(4, trimmed.count)))
        return "\(prefix)••••\(suffix)"
    }
}

private struct LegacyProviderAccountRecord: Codable {
    let id: UUID
    let providerID: IntelligenceProviderID
    let authMethod: ProviderAccountAuthMethod
    let displayName: String
    let identifier: String
    let secret: String
    let createdAt: Date
    let updatedAt: Date
}
