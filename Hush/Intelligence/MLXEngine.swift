import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

actor MLXEngine {
    private var container: ModelContainer?
    private var modelID: String?
    private var session: ChatSession?
    private var sessionConversationID: UUID?
    private var sessionSettings: HushSettings?
    private var expectedHistory: [Turn] = []
    private var generating = false

    func generate(_ request: GenerationRequest, event: @Sendable @escaping (GenerationEvent) async -> Void) async throws {
        guard !generating else { throw HushError.message("The local model is busy.") }
        guard let directory = request.modelDirectory else { throw HushError.message("Download this model before using it.") }
        let weights = request.model.sizeBytes ?? 0
        guard weights + max(768 * 1024 * 1024, weights / 4) < Int64(request.memoryBudget) else {
            throw HushError.message("This model is too large for the available memory budget. Choose a smaller quantized model.")
        }
        guard ProcessInfo.processInfo.thermalState != .critical else { throw HushError.message("Let this device cool down before starting another response.") }
        generating = true
        defer { generating = false }
        let started = ContinuousClock.now
        var metrics = GenerationMetrics()
        Memory.memoryLimit = request.memoryBudget
        Memory.cacheLimit = min(256 * 1024 * 1024, request.memoryBudget / 8)
        Memory.peakMemory = 0

        if modelID != request.model.id {
            resetSession()
            container = nil
            // This loader accepts only a verified local installation, never a Hub identifier.
            container = try await MLXLMCommon.loadModelContainer(from: directory, using: LocalTokenizerLoader())
            modelID = request.model.id
        }
        guard let container else { throw HushError.message("The model could not be loaded.") }
        try Task.checkCancellation()
        let tokenizer = await container.tokenizer
        let contextLimit = ModelContextLimit.read(from: directory)
        let outputLimit = min(request.settings.maximumOutputTokens, max(64, contextLimit / 2))
        var history = ConversationContext.completedTurns(from: request.history).map(Turn.init)
        let originalCount = history.count
        let prompt = Turn(role: .user, text: request.prompt, attachments: request.attachments)
        let context: [String: any Sendable] = ["enable_thinking": false]
        while try tokenCount(history: history, prompt: prompt, instructions: request.settings.instructions,
                             tokenizer: tokenizer, context: context) > contextLimit - outputLimit - 128 {
            guard !history.isEmpty else {
                throw HushError.message("This message is larger than the model's context window. Attach a shorter document or choose a larger-context model.")
            }
            history.removeFirst()
            while history.first?.role == .assistant { history.removeFirst() }
        }
        if history.count != originalCount { await event(.status("Using recent messages to fit the model's context")) }

        if sessionConversationID != request.conversationID || sessionSettings != request.settings || expectedHistory != history {
            resetSession()
            let messages = try history.map { try $0.message(for: request) }
            session = ChatSession(container, instructions: request.settings.instructions, history: messages,
                generateParameters: GenerateParameters(maxTokens: outputLimit,
                    temperature: Float(request.settings.temperature), topP: 0.95), additionalContext: context)
            sessionConversationID = request.conversationID
            sessionSettings = request.settings
        }
        guard let session else { throw HushError.message("The local session could not be prepared.") }
        session.generateParameters.maxTokens = outputLimit
        await event(.status("Generating with Metal"))
        var text = ""
        var lastUpdate = ContinuousClock.now
        do {
            for try await item in session.streamDetails(to: [try prompt.message(for: request)]) {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.thermalState != .critical else {
                    throw HushError.message("Generation stopped to let this device cool down. Your partial response is saved.")
                }
                switch item {
                case .chunk(let chunk):
                    text += chunk
                    if metrics.timeToFirstToken == nil { metrics.timeToFirstToken = seconds(since: started) }
                    if seconds(since: lastUpdate) >= 0.033 {
                        await event(.snapshot(text))
                        lastUpdate = .now
                    }
                case .info(let info):
                    metrics.inputTokens = info.totalPromptTokenCount
                    metrics.cachedTokens = info.cachedPromptTokenCount
                    metrics.outputTokens = info.generationTokenCount
                case .toolCall, .rejectedToolCall:
                    throw HushError.message("This model requested a tool that is not enabled. No action was executed.")
                }
            }
            try Task.checkCancellation()
            await waitForProducer(session)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HushError.message("The model returned no text. Try another prompt or a different model.")
            }
            await event(.snapshot(text))
            expectedHistory = history + [prompt, Turn(role: .assistant, text: text)]
            metrics.duration = seconds(since: started)
            metrics.peakMemoryBytes = Memory.peakMemory
            await event(.completed(metrics))
        } catch {
            // Wait for the producer to stop before releasing its GPU-backed cache.
            await waitForProducer(session)
            resetSession()
            if !text.isEmpty { await event(.snapshot(text)) }
            throw error
        }
    }

    func unload() {
        guard !generating else { return }
        resetSession()
        container = nil
        modelID = nil
        Stream.gpu.synchronize()
        Memory.clearCache()
    }

    private func resetSession() {
        session = nil
        sessionConversationID = nil
        sessionSettings = nil
        expectedHistory = []
    }

    private func waitForProducer(_ session: ChatSession) async {
        // ChatSession is non-Sendable. This actor owns it exclusively and keeps
        // `generating` true until its internally locked producer has drained.
        nonisolated(unsafe) let ownedSession = session
        await ownedSession.synchronize()
    }

    private func tokenCount(history: [Turn], prompt: Turn, instructions: String,
                            tokenizer: any MLXLMCommon.Tokenizer, context: [String: any Sendable]) throws -> Int {
        let turns = history + [prompt]
        let messages: [[String: any Sendable]] = [["role": "system", "content": instructions]] + turns.map {
            ["role": $0.role.rawValue, "content": $0.referenceText]
        }
        let textCount = try tokenizer.applyChatTemplate(messages: messages, tools: nil, additionalContext: context).count
        return textCount + turns.flatMap(\.attachments).filter { $0.kind == .image }.count * 2048
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    private struct Turn: Equatable {
        var role: ChatMessage.Role
        var text: String
        var attachments: [ChatAttachment] = []

        init(role: ChatMessage.Role, text: String, attachments: [ChatAttachment] = []) {
            self.role = role
            self.text = text
            self.attachments = attachments
        }

        init(_ message: ChatMessage) { self.init(role: message.role, text: message.text, attachments: message.attachments) }

        var referenceText: String {
            text + attachments.compactMap { attachment in
                attachment.extractedText.map { "\nReference attachment: \(attachment.name)\n<reference>\n\($0)\n</reference>" }
            }.joined()
        }

        func message(for request: GenerationRequest) throws -> Chat.Message {
            let images = try attachments.filter { $0.kind == .image }.compactMap { attachment -> UserInput.Image? in
                guard request.model.supportsVision else {
                    guard attachment.extractedText?.isEmpty == false else {
                        throw HushError.message("This model cannot see images. Choose a vision model or attach a text document.")
                    }
                    return nil
                }
                return .url(try ModelPath.resolve(attachment.filename, under: request.attachmentDirectory))
            }
            return Chat.Message(role: role == .user ? .user : .assistant, content: referenceText, images: images)
        }
    }
}
