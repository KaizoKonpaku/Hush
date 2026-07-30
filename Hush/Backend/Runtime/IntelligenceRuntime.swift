import Foundation

struct IntelligenceConversationHandle {
    let conversationID: String?
    let seedItems: [OpenAIConversationSeedItem]
    let existingAssets: [AttachmentAssetRecord]

    init(
        conversationID: String? = nil,
        seedItems: [OpenAIConversationSeedItem] = [],
        existingAssets: [AttachmentAssetRecord] = []
    ) {
        self.conversationID = conversationID
        self.seedItems = seedItems
        self.existingAssets = existingAssets
    }
}

struct IntelligenceResponseStream {
    let responseID: String?
    let conversationID: String?
    let assistantItemID: String?
    let assets: [AttachmentAssetRecord]
    let stream: AsyncThrowingStream<String, Error>
}

enum IntelligenceRuntimeError: LocalizedError {
    case noModelSelected
    case missingProviderAccount(String)
    case missingProviderKey(String)
    case unsupportedProvider(String)

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "Choose a live model in Settings > Intelligence before sending a request."
        case let .missingProviderAccount(provider):
            return "Connect a \(provider) account in Settings > Accounts first."
        case let .missingProviderKey(provider):
            return "Add a valid \(provider) API key in Settings > Accounts."
        case let .unsupportedProvider(provider):
            return "\(provider) is not available in this build yet."
        }
    }
}

struct IntelligenceRuntime {
    static let shared = IntelligenceRuntime()

    private let defaults = UserDefaults.standard
    private let openAIService = OpenAIService.shared

    func responseStream(
        prompt: String,
        captures: [OverlayCapture],
        modelMode: AssistantModelMode,
        conversationHandle: IntelligenceConversationHandle = .init()
    ) async throws -> IntelligenceResponseStream {
        let selectedValue = AssistantModelCatalog.storedModelValue(for: modelMode, defaults: defaults)
        let availableOptions = await MainActor.run {
            ProviderAccountStore.shared.availableModels
        }
        guard AssistantModelCatalog.hasAvailableOption(for: selectedValue, availableOptions: availableOptions),
              let selectedModel = AssistantModelCatalog.option(for: selectedValue, availableOptions: availableOptions) else {
            throw IntelligenceRuntimeError.noModelSelected
        }

        switch selectedModel.providerID {
        case .mock:
            throw IntelligenceRuntimeError.noModelSelected
        case .openAI:
            guard let (account, secrets) = await MainActor.run(body: { () -> (ProviderAccountRecord, ProviderAccountLocalSecrets)? in
                guard let account = ProviderAccountStore.shared.primaryAccount(for: .openAI) else {
                    return nil
                }

                return (account, ProviderAccountStore.shared.secrets(for: account))
            }) else {
                throw IntelligenceRuntimeError.missingProviderAccount("OpenAI")
            }

            guard !secrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw IntelligenceRuntimeError.missingProviderKey("OpenAI")
            }

            let resolvedConversationID: String?
            if conversationHandle.conversationID == nil {
                resolvedConversationID = try await openAIService.ensureConversationID(
                    existingConversationID: nil,
                    seedItems: conversationHandle.seedItems,
                    record: account,
                    secrets: secrets
                )
            } else {
                resolvedConversationID = conversationHandle.conversationID
            }

            let response = try await openAIService.generateResponse(
                prompt: prompt,
                captures: captures,
                existingAssets: conversationHandle.existingAssets,
                seedItems: conversationHandle.seedItems,
                modelID: selectedModel.modelID,
                modelMode: modelMode,
                conversationID: resolvedConversationID,
                record: account,
                secrets: secrets
            )
            return IntelligenceResponseStream(
                responseID: response.id,
                conversationID: response.conversationID,
                assistantItemID: response.assistantItemID,
                assets: response.assets,
                stream: streamedResponse(from: response.text)
            )
        default:
            throw IntelligenceRuntimeError.unsupportedProvider(selectedModel.provider)
        }
    }

    private func shouldUseStreaming() -> Bool {
        if defaults.object(forKey: "behaviours.text.streamResponses") == nil {
            return true
        }

        return defaults.bool(forKey: "behaviours.text.streamResponses")
    }

    private func streamedResponse(from text: String) -> AsyncThrowingStream<String, Error> {
        let chunks = shouldUseStreaming() ? streamedChunks(from: text) : [text]

        return AsyncThrowingStream { continuation in
            let task = Task {
                for (index, chunk) in chunks.enumerated() {
                    guard !Task.isCancelled else {
                        return
                    }

                    continuation.yield(chunk)

                    if index < chunks.count - 1 {
                        try? await Task.sleep(nanoseconds: 45_000_000)
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamedChunks(from text: String) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""

        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let token = currentChunk.isEmpty ? String(word) : " \(word)"
            if currentChunk.count + token.count > 56, !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = String(word)
            } else {
                currentChunk += token
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks.isEmpty ? [text] : chunks
    }
}
