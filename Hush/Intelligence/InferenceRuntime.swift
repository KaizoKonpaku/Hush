#if canImport(CoreAI)
import CoreAILanguageModels
#endif
import Foundation
import FoundationModels
import MLX
import MLXLMCommon

protocol InferenceServing: Sendable {
    func generate(_ request: GenerationRequest, event: @Sendable @escaping (GenerationEvent) async -> Void) async throws
    func unload() async
}

actor InferenceRuntime: InferenceServing {
    private var activeModelID: String?
    private let mlxEngine = MLXEngine()
    #if canImport(CoreAI)
    private var coreModel: CoreAILanguageModel?
    private var visionModel: CoreAIVisionLanguageModel?
    #endif
    private var generating = false
    private var unloadingTask: Task<Void, Never>?

    func generate(_ request: GenerationRequest, event: @Sendable @escaping (GenerationEvent) async -> Void) async throws {
        if let unloadingTask { await unloadingTask.value }
        guard !generating else { throw HushError.message("A response is already running. Stop it before starting another.") }
        generating = true
        defer { generating = false }
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.thermalState != .critical else {
            throw HushError.message("This device is too warm to start another model run. Let it cool down and try again.")
        }
        await event(.status("Preparing \(request.model.name)"))
        let started = ContinuousClock.now
        var metrics = GenerationMetrics()

        if activeModelID != request.model.id { await releaseModels() }
        if request.model.engine == .mlx {
            try Self.checkMemory(for: request)
            activeModelID = request.model.id
            try await mlxEngine.generate(request, event: event)
            return
        }
        let model: any FoundationModels.LanguageModel
        var tokenizer: (any MLXLMCommon.Tokenizer)?
        var contextLimit = 4096

        switch request.model.engine {
        case .apple:
            let system = SystemLanguageModel.default
            guard system.isAvailable else { throw HushError.message(Self.appleAvailabilityMessage) }
            model = system
            contextLimit = system.contextSize
        case .mlx:
            throw HushError.message("The MLX engine did not start.")
        case .coreAI:
            #if canImport(CoreAI)
            guard let directory = request.modelDirectory else { throw HushError.message("Import the Core AI bundle before using it.") }
            try Self.checkMemory(for: request)
            if request.model.supportsVision {
                if visionModel == nil { visionModel = try await CoreAIVisionLanguageModel(resourcesAt: directory) }
                guard let loaded = visionModel else { throw HushError.message("The vision model could not be created.") }
                model = loaded
            } else {
                if coreModel == nil { coreModel = try await CoreAILanguageModel(resourcesAt: directory) }
                guard let loaded = coreModel else { throw HushError.message("The model could not be created.") }
                model = loaded
            }
            tokenizer = try await LocalTokenizerLoader().load(from: directory.appending(path: "tokenizer"))
            contextLimit = ModelContextLimit.read(from: directory)
            #else
            throw HushError.message("Core AI requires a physical device with OS 27. This simulator SDK does not include the framework.")
            #endif
        }
        activeModelID = request.model.id
        try Task.checkCancellation()

        let prompt = try Self.makePrompt(request)
        var history = ConversationContext.completedTurns(from: request.history)
        let originalCount = history.count
        let outputLimit = min(request.settings.maximumOutputTokens, max(64, contextLimit / 2))
        let availableInput = contextLimit - outputLimit - 128
        var entries = try Self.entries(history, request: request)
        let textPrompt = try Self.makePrompt(request, includingImages: false)
        func estimatedCount(_ entries: [Transcript.Entry], history: [ChatMessage], tokenizer: (any MLXLMCommon.Tokenizer)?) async throws -> Int {
            let imageCount = request.attachments.filter { $0.kind == .image }.count
                + history.flatMap(\.attachments).filter { $0.kind == .image }.count
            if request.model.engine == .apple {
                // OS 27's tokenizer rejects image segments even though generation supports them.
                // Imported images are bounded to 1536px; reserve space rather than dropping vision.
                let textEntries = try Self.entries(history, request: request, includingImages: false)
                return try await SystemLanguageModel.default.tokenCount(for: textEntries)
                    + SystemLanguageModel.default.tokenCount(for: textPrompt) + imageCount * 2048
            }
            let text = request.settings.instructions + history.map(Self.referenceText).joined(separator: "\n")
                + request.prompt + request.attachments.compactMap(\.extractedText).joined(separator: "\n")
            return (tokenizer?.encode(text: text).count ?? text.utf8.count) + entries.count * 16 + imageCount * 2048 + 64
        }
        while try await estimatedCount(entries, history: history, tokenizer: tokenizer) > availableInput {
            guard !history.isEmpty else {
                throw HushError.message("This message and its attachments exceed the model's context window. Use a shorter document or a model with a larger context window.")
            }
            history.removeFirst()
            while history.first?.role == .assistant { history.removeFirst() }
            entries = try Self.entries(history, request: request)
        }
        if history.count < originalCount { await event(.status("Using recent messages to fit this model's context")) }

        let session = LanguageModelSession(model: model, transcript: Transcript(entries: entries))
        session.transcriptErrorHandlingPolicy = .revertTranscript
        let stream = session.streamResponse(to: prompt,
            options: GenerationOptions(temperature: request.settings.temperature, maximumResponseTokens: outputLimit),
            contextOptions: ContextOptions(), metadata: ["conversationID": request.conversationID.uuidString])
        await event(.status("Generating on this device"))
        var lastUpdate = ContinuousClock.now
        var latest = ""
        do {
            for try await snapshot in stream {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.thermalState != .critical else {
                    throw HushError.message("Generation stopped because the device reached a critical temperature. Your partial response is saved.")
                }
                latest = snapshot.content
                if metrics.timeToFirstToken == nil, !latest.isEmpty {
                    metrics.timeToFirstToken = Self.seconds(since: started)
                }
                if Self.seconds(since: lastUpdate) >= 0.033 {
                    await event(.snapshot(latest))
                    lastUpdate = .now
                }
            }
            try Task.checkCancellation()
        } catch {
            if !latest.isEmpty { await event(.snapshot(latest)) }
            throw error
        }
        guard !latest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HushError.message("The model returned no text. Try another prompt or a different model.")
        }
        await event(.snapshot(latest))
        let usage = session.usage
        metrics.inputTokens = usage.input.totalTokenCount
        metrics.outputTokens = usage.output.totalTokenCount
        metrics.cachedTokens = usage.input.cachedTokenCount
        metrics.duration = Self.seconds(since: started)
        await event(.completed(metrics))
    }

    func unload() async {
        if let unloadingTask { await unloadingTask.value; return }
        guard !generating else { return }
        let task = Task { await releaseModels() }
        unloadingTask = task
        await task.value
        unloadingTask = nil
    }

    private func releaseModels() async {
        await mlxEngine.unload()
        #if canImport(CoreAI)
        coreModel?.unload()
        coreModel = nil
        visionModel = nil
        #endif
        activeModelID = nil
        Memory.clearCache()
    }

    static var appleAvailabilityMessage: String {
        switch SystemLanguageModel.default.availability {
        case .available: "Ready on this device"
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings, or download an MLX model."
        case .unavailable(.modelNotReady): "Apple is preparing the on-device model. Try again when its download has finished, or use MLX."
        case .unavailable(.deviceNotEligible): "Apple Intelligence is unavailable on this device. Try a compatible MLX model."
        @unknown default: "Apple's on-device model is currently unavailable. You can use an installed MLX model instead."
        }
    }

    private static func checkMemory(for request: GenerationRequest) throws {
        guard request.memoryBudget >= 512 * 1024 * 1024 else { throw HushError.message("Not enough available memory to load a local model.") }
        let weights = request.model.sizeBytes ?? 0
        let estimate = weights + max(768 * 1024 * 1024, weights / 4)
        guard estimate < Int64(request.memoryBudget) else {
            throw HushError.message("This model is likely to exceed the current memory budget. Choose a smaller quantized model, or select Maximum in Runtime settings if your device has room.")
        }
    }

    private static func makePrompt(_ request: GenerationRequest, includingImages: Bool = true) throws -> Prompt {
        let images = try request.attachments.filter { $0.kind == .image }.compactMap { attachment -> URL? in
            if !request.model.supportsVision {
                guard let text = attachment.extractedText, !text.isEmpty else {
                    throw HushError.message("This model cannot see images. Choose Apple On-Device or a vision-capable MLX model.")
                }
                return nil
            }
            return try ModelPath.resolve(attachment.filename, under: request.attachmentDirectory)
        }
        return Prompt {
            request.prompt
            for attachment in request.attachments {
                if let text = attachment.extractedText, attachment.kind == .text || !request.model.supportsVision {
                    "Reference attachment: \(attachment.name)\n<reference>\n\(text)\n</reference>"
                }
            }
            if includingImages {
                for image in images { Attachment(imageURL: image) }
            }
        }
    }

    private static func entries(_ messages: [ChatMessage], request: GenerationRequest, includingImages: Bool = true) throws -> [Transcript.Entry] {
        var entries: [Transcript.Entry] = [.instructions(.init(
            segments: [.text(.init(content: request.settings.instructions))], toolDefinitions: []))]
        for message in messages {
            guard !message.text.isEmpty else { continue }
            var segments: [Transcript.Segment] = [.text(.init(content: referenceText(message)))]
            if request.model.supportsVision && includingImages {
                for image in message.attachments where image.kind == .image {
                    let url = try ModelPath.resolve(image.filename, under: request.attachmentDirectory)
                    if FileManager.default.fileExists(atPath: url.path) {
                        segments.append(.attachment(.init(content: .image(.init(imageURL: url)), label: image.name)))
                    }
                }
            }
            if message.role == .user { entries.append(.prompt(.init(segments: segments))) }
            else { entries.append(.response(.init(segments: segments))) }
        }
        return entries
    }

    private static func referenceText(_ message: ChatMessage) -> String {
        message.text + message.attachments.compactMap { attachment in
            attachment.extractedText.map { "\nReference attachment: \(attachment.name)\n<reference>\n\($0)\n</reference>" }
        }.joined()
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: .now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
