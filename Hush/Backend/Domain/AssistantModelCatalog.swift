import Foundation

private let preferredOpenAIModelIDs = [
    "gpt-5.4",
    "gpt-5.4-mini",
    "gpt-5.4-nano",
    "gpt-5",
    "gpt-5-mini",
    "gpt-5-nano",
    "gpt-4.1",
    "gpt-4.1-mini",
    "gpt-4.1-nano",
    "o4-mini",
    "o3",
    "o3-mini",
]

private let preferredOpenAIRealtimeModelIDs = [
    "gpt-realtime-1.5",
    "gpt-realtime",
    "gpt-realtime-mini",
    "gpt-4o-realtime-preview-2025-06-03",
    "gpt-4o-realtime-preview-2024-12-17",
    "gpt-4o-realtime-preview-2024-10-01",
    "gpt-4o-mini-realtime-preview-2024-12-17",
]

private let preferredOpenAIRealtimeTranscriptionModelIDs = [
    "gpt-4o-mini-transcribe",
    "gpt-4o-transcribe-latest",
    "gpt-4o-transcribe",
    "whisper-1",
]

private func makeOpenAIAssistantModelOption(modelID: String) -> AssistantModelOption {
    AssistantModelOption(
        providerID: .openAI,
        modelID: modelID,
        title: AssistantModelCatalog.prettyTitle(for: modelID),
        supportsImages: true,
        supportsAudioInput: true,
        supportsFileInput: true
    )
}

private func sortOpenAIAssistantModelOptions(_ lhs: AssistantModelOption, _ rhs: AssistantModelOption) -> Bool {
    let lhsIndex = preferredOpenAIModelIDs.firstIndex(of: lhs.modelID) ?? Int.max
    let rhsIndex = preferredOpenAIModelIDs.firstIndex(of: rhs.modelID) ?? Int.max

    if lhsIndex != rhsIndex {
        return lhsIndex < rhsIndex
    }

    return lhs.modelID.localizedCaseInsensitiveCompare(rhs.modelID) == .orderedAscending
}

private func sortOpenAIRealtimeModelOptions(_ lhs: AssistantModelOption, _ rhs: AssistantModelOption) -> Bool {
    let lhsIndex = preferredOpenAIRealtimeModelIDs.firstIndex(of: lhs.modelID) ?? Int.max
    let rhsIndex = preferredOpenAIRealtimeModelIDs.firstIndex(of: rhs.modelID) ?? Int.max

    if lhsIndex != rhsIndex {
        return lhsIndex < rhsIndex
    }

    return lhs.modelID.localizedCaseInsensitiveCompare(rhs.modelID) == .orderedAscending
}

private func sortOpenAIRealtimeTranscriptionModelOptions(
    _ lhs: AssistantModelOption,
    _ rhs: AssistantModelOption
) -> Bool {
    let lhsIndex = preferredOpenAIRealtimeTranscriptionModelIDs.firstIndex(of: lhs.modelID) ?? Int.max
    let rhsIndex = preferredOpenAIRealtimeTranscriptionModelIDs.firstIndex(of: rhs.modelID) ?? Int.max

    if lhsIndex != rhsIndex {
        return lhsIndex < rhsIndex
    }

    return lhs.modelID.localizedCaseInsensitiveCompare(rhs.modelID) == .orderedAscending
}

private func isLikelyResponseCapableOpenAIModelID(_ modelID: String) -> Bool {
    let lower = modelID.lowercased()
    let excludedFragments = [
        "embed",
        "embedding",
        "whisper",
        "transcribe",
        "tts",
        "speech",
        "moderation",
        "image",
        "dall",
        "audio",
        "realtime",
        "search",
        "rank",
        "vision-preview",
    ]

    if excludedFragments.contains(where: { lower.contains($0) }) {
        return false
    }

    return lower.hasPrefix("gpt-")
        || lower.hasPrefix("o1")
        || lower.hasPrefix("o3")
        || lower.hasPrefix("o4")
        || lower == "gpt-5"
        || lower == "gpt-5.4"
}

private func isLikelyRealtimeCapableOpenAIModelID(_ modelID: String) -> Bool {
    let lower = modelID.lowercased()
    return lower.contains("realtime")
}

private func isLikelyRealtimeTranscriptionCapableOpenAIModelID(_ modelID: String) -> Bool {
    let normalized = modelID.lowercased()
    return preferredOpenAIRealtimeTranscriptionModelIDs.contains(normalized)
}

enum IntelligenceProviderID: String, CaseIterable, Identifiable, Hashable, Codable {
    case mock = "mock"
    case openAI = "openai"
    case google = "google"
    case anthropic = "anthropic"
    case x = "x"

    var id: String { rawValue }

    static let connectableProviders: [Self] = [.openAI, .google, .anthropic, .x]

    var title: String {
        switch self {
        case .mock:
            return "Mock"
        case .openAI:
            return "OpenAI"
        case .google:
            return "Google"
        case .anthropic:
            return "Anthropic"
        case .x:
            return "X"
        }
    }

    var helperText: String {
        switch self {
        case .mock:
            return "Built-in demo responses with no external provider."
        case .openAI:
            return "Use an OpenAI project API key for model requests. Add an admin key if you want usage and cost status."
        case .google:
            return "Local placeholder flow for Google and Gemini access."
        case .anthropic:
            return "Local placeholder flow for Anthropic workspace keys."
        case .x:
            return "Local placeholder flow for X and Grok access."
        }
    }

    var icon: String {
        switch self {
        case .mock:
            return "cpu.fill"
        case .openAI:
            return "sparkles.rectangle.stack.fill"
        case .google:
            return "globe"
        case .anthropic:
            return "text.bubble.fill"
        case .x:
            return "bolt.fill"
        }
    }

    var supportsOAuth: Bool {
        switch self {
        case .mock, .openAI, .anthropic:
            return false
        case .google, .x:
            return true
        }
    }

    var supportsAPIKeys: Bool {
        self != .mock
    }
}

enum AssistantModelMode: String {
    case defaultMode = "default"
    case fast
    case advanced
}

struct AssistantModelOption: Identifiable, Hashable {
    let providerID: IntelligenceProviderID
    let modelID: String
    let title: String
    let supportsImages: Bool
    let supportsAudioInput: Bool
    let supportsFileInput: Bool

    var id: String { storageValue }
    var provider: String { providerID.title }
    var storageValue: String { AssistantModelCatalog.storageValue(providerID: providerID, modelID: modelID) }
}

enum AssistantModelCatalog {
    private static let legacyMockModelID = "hush-demo"
    private static let legacyMockStorageValue = storageValue(providerID: .mock, modelID: legacyMockModelID)

    static let mockStorageValue = legacyMockStorageValue

    static func storageValue(providerID: IntelligenceProviderID, modelID: String) -> String {
        "\(providerID.rawValue)::\(modelID)"
    }

    static func decodeStorageValue(_ value: String) -> (providerID: IntelligenceProviderID, modelID: String)? {
        let normalized = normalizedStoredValue(value)
        guard !normalized.isEmpty else {
            return nil
        }

        return decodeDirectStorageValue(normalized)
    }

    static func option(for storedValue: String, availableOptions: [AssistantModelOption]) -> AssistantModelOption? {
        guard let decoded = decodeStorageValue(storedValue) else {
            return nil
        }

        return availableOptions.first {
            $0.providerID == decoded.providerID && $0.modelID == decoded.modelID
        } ?? AssistantModelOption(
            providerID: decoded.providerID,
            modelID: decoded.modelID,
            title: prettyTitle(for: decoded.modelID),
            supportsImages: defaultImageSupport(for: decoded.providerID, modelID: decoded.modelID),
            supportsAudioInput: defaultAudioSupport(for: decoded.providerID),
            supportsFileInput: defaultFileSupport(for: decoded.providerID)
        )
    }

    static func title(for storedValue: String, availableOptions: [AssistantModelOption]) -> String {
        guard hasAvailableOption(for: storedValue, availableOptions: availableOptions) else {
            return "No model"
        }

        return option(for: storedValue, availableOptions: availableOptions)?.title ?? "No model"
    }

    static func hasAvailableOption(for storedValue: String, availableOptions: [AssistantModelOption]) -> Bool {
        guard let decoded = decodeStorageValue(storedValue) else {
            return false
        }

        return availableOptions.contains {
            $0.providerID == decoded.providerID && $0.modelID == decoded.modelID
        }
    }

    static func providerID(for storedValue: String, availableOptions: [AssistantModelOption]) -> IntelligenceProviderID? {
        guard hasAvailableOption(for: storedValue, availableOptions: availableOptions) else {
            return nil
        }

        return option(for: storedValue, availableOptions: availableOptions)?.providerID
    }

    static func storedModelValue(for mode: AssistantModelMode, defaults: UserDefaults = .standard) -> String {
        let key: String
        switch mode {
        case .defaultMode:
            key = "intel.defaultModel"
        case .fast:
            key = "intel.fastModel"
        case .advanced:
            key = "intel.advancedModel"
        }

        let normalized = normalizedStoredValue(defaults.string(forKey: key) ?? "")
        return normalized
    }

    static func storedRealtimeModelValue(defaults: UserDefaults = .standard) -> String {
        normalizedStoredValue(defaults.string(forKey: "intel.realtimeModel") ?? "")
    }

    static func storedRealtimeTranscriptionModelValue(defaults: UserDefaults = .standard) -> String {
        normalizedStoredValue(defaults.string(forKey: "intel.realtimeTranscriptionModel") ?? "")
    }

    static func prettyTitle(for modelID: String) -> String {
        return modelID
            .replacingOccurrences(of: "/", with: " / ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { token in
                let lower = token.lowercased()
                switch lower {
                case "hush":
                    return "HUSH"
                case "ai":
                    return "AI"
                case "gpt":
                    return "GPT"
                default:
                    return token.prefix(1).uppercased() + token.dropFirst()
                }
            }
            .joined(separator: " ")
    }

    static func defaultImageSupport(for providerID: IntelligenceProviderID, modelID: String) -> Bool {
        true
    }

    static func defaultAudioSupport(for providerID: IntelligenceProviderID) -> Bool {
        true
    }

    static func defaultFileSupport(for providerID: IntelligenceProviderID) -> Bool {
        true
    }

    static func defaultModels(for providerID: IntelligenceProviderID) -> [AssistantModelOption] {
        switch providerID {
        case .mock:
            return []
        case .openAI:
            return preferredOpenAIModelIDs.map(makeOpenAIAssistantModelOption(modelID:))
        case .google:
            return [
                AssistantModelOption(providerID: .google, modelID: "standard", title: "Google Standard", supportsImages: true, supportsAudioInput: true, supportsFileInput: true),
                AssistantModelOption(providerID: .google, modelID: "fast", title: "Google Fast", supportsImages: true, supportsAudioInput: false, supportsFileInput: true),
            ]
        case .anthropic:
            return [
                AssistantModelOption(providerID: .anthropic, modelID: "standard", title: "Anthropic Standard", supportsImages: true, supportsAudioInput: false, supportsFileInput: true),
                AssistantModelOption(providerID: .anthropic, modelID: "extended", title: "Anthropic Extended", supportsImages: true, supportsAudioInput: false, supportsFileInput: true),
            ]
        case .x:
            return [
                AssistantModelOption(providerID: .x, modelID: "standard", title: "X Standard", supportsImages: true, supportsAudioInput: true, supportsFileInput: true),
                AssistantModelOption(providerID: .x, modelID: "fast", title: "X Fast", supportsImages: true, supportsAudioInput: false, supportsFileInput: true),
            ]
        }
    }

    static func defaultRealtimeModels(for providerID: IntelligenceProviderID) -> [AssistantModelOption] {
        switch providerID {
        case .openAI:
            return preferredOpenAIRealtimeModelIDs.map(makeOpenAIAssistantModelOption(modelID:))
        case .mock, .google, .anthropic, .x:
            return []
        }
    }

    static func defaultRealtimeTranscriptionModels(for providerID: IntelligenceProviderID) -> [AssistantModelOption] {
        switch providerID {
        case .openAI:
            return preferredOpenAIRealtimeTranscriptionModelIDs.map(makeOpenAIAssistantModelOption(modelID:))
        case .mock, .google, .anthropic, .x:
            return []
        }
    }

    static func openAIModelOptions(from modelIDs: [String]) -> [AssistantModelOption] {
        let filtered = Set(modelIDs.filter(isLikelyResponseCapableOpenAIModelID))
        guard !filtered.isEmpty else {
            return defaultModels(for: .openAI)
        }

        return filtered
            .map(makeOpenAIAssistantModelOption(modelID:))
            .sorted(by: sortOpenAIAssistantModelOptions(_:_:))
    }

    static func openAIRealtimeModelOptions(from modelIDs: [String]) -> [AssistantModelOption] {
        Set(modelIDs.filter(isLikelyRealtimeCapableOpenAIModelID))
            .map(makeOpenAIAssistantModelOption(modelID:))
            .sorted(by: sortOpenAIRealtimeModelOptions(_:_:))
    }

    static func openAIRealtimeTranscriptionModelOptions(from modelIDs: [String]) -> [AssistantModelOption] {
        let filtered = Set(modelIDs.filter(isLikelyRealtimeTranscriptionCapableOpenAIModelID))
        guard !filtered.isEmpty else {
            return defaultRealtimeTranscriptionModels(for: .openAI)
        }

        return filtered
            .map(makeOpenAIAssistantModelOption(modelID:))
            .sorted(by: sortOpenAIRealtimeTranscriptionModelOptions(_:_:))
    }

    private static func normalizedStoredValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed == legacyMockModelID || trimmed == legacyMockStorageValue {
            return ""
        }

        if let decoded = decodeDirectStorageValue(trimmed) {
            return storageValue(providerID: decoded.providerID, modelID: decoded.modelID)
        }

        return ""
    }

    private static func decodeDirectStorageValue(
        _ value: String
    ) -> (providerID: IntelligenceProviderID, modelID: String)? {
        let parts = value.components(separatedBy: "::")
        guard parts.count == 2,
              let providerID = IntelligenceProviderID(rawValue: parts[0]),
              !parts[1].isEmpty else {
            return nil
        }

        return (providerID, parts[1])
    }
}
