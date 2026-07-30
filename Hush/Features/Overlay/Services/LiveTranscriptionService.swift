import Foundation
import Combine
import AppKit
import AVFoundation
import Speech
import ScreenCaptureKit
import CoreGraphics
import CoreMedia

enum LiveAudioInputMode: String {
    case both
    case mic
    case system

    var includesMic: Bool {
        self == .both || self == .mic
    }

    var includesSystemAudio: Bool {
        self == .both || self == .system
    }
}

enum LiveTranscriptSource: String {
    case both
    case mic
    case system
    case assistant

    var label: String {
        switch self {
        case .both:
            return "BOTH"
        case .mic:
            return "MIC"
        case .system:
            return "SYS"
        case .assistant:
            return "AI"
        }
    }

    var sortOrder: Int {
        switch self {
        case .both:
            return 0
        case .mic:
            return 1
        case .system:
            return 2
        case .assistant:
            return 3
        }
    }
}

struct LiveTranscriptLine: Identifiable, Equatable {
    let id = UUID()
    let source: LiveTranscriptSource
    var text: String
}

enum LiveVoiceDebugResponseState: String, Equatable, Sendable {
    case idle
    case requested
    case active
    case cancelled
    case replaced
    case completed

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .requested:
            return "Requested"
        case .active:
            return "Active"
        case .cancelled:
            return "Cancelled"
        case .replaced:
            return "Replaced"
        case .completed:
            return "Completed"
        }
    }
}

struct LiveVoiceDebugTransition: Sendable {
    enum Category: String, Equatable, Sendable {
        case pipeline
        case capture
        case speech
        case response
        case warning

        var label: String {
            switch self {
            case .pipeline:
                return "PIPE"
            case .capture:
                return "MIC"
            case .speech:
                return "VAD"
            case .response:
                return "RESP"
            case .warning:
                return "WARN"
            }
        }
    }

    let category: Category
    let title: String
    let detail: String
    let itemID: String?
    let responseID: String?
    let responseState: LiveVoiceDebugResponseState?
    let micCaptureActive: Bool?
    let backendLabel: String?
    let transcriptionModelLabel: String?
    let speechLabel: String?
    let loopHint: String?
    let clearsLoopHint: Bool
    let isHighlighted: Bool

    init(
        category: Category,
        title: String,
        detail: String,
        itemID: String? = nil,
        responseID: String? = nil,
        responseState: LiveVoiceDebugResponseState? = nil,
        micCaptureActive: Bool? = nil,
        backendLabel: String? = nil,
        transcriptionModelLabel: String? = nil,
        speechLabel: String? = nil,
        loopHint: String? = nil,
        clearsLoopHint: Bool = false,
        isHighlighted: Bool = false
    ) {
        self.category = category
        self.title = title
        self.detail = detail
        self.itemID = itemID
        self.responseID = responseID
        self.responseState = responseState
        self.micCaptureActive = micCaptureActive
        self.backendLabel = backendLabel
        self.transcriptionModelLabel = transcriptionModelLabel
        self.speechLabel = speechLabel
        self.loopHint = loopHint
        self.clearsLoopHint = clearsLoopHint
        self.isHighlighted = isHighlighted
    }
}

struct LiveVoiceDebugEvent: Identifiable, Equatable {
    let id = UUID()
    var occurredAt: Date
    let category: LiveVoiceDebugTransition.Category
    let title: String
    let detail: String
    let itemID: String?
    let responseID: String?
    let isHighlighted: Bool
    var repeatCount: Int

    init(
        occurredAt: Date,
        category: LiveVoiceDebugTransition.Category,
        title: String,
        detail: String,
        itemID: String?,
        responseID: String?,
        isHighlighted: Bool,
        repeatCount: Int = 1
    ) {
        self.occurredAt = occurredAt
        self.category = category
        self.title = title
        self.detail = detail
        self.itemID = itemID
        self.responseID = responseID
        self.isHighlighted = isHighlighted
        self.repeatCount = repeatCount
    }

    var signature: String {
        [
            category.rawValue,
            title,
            detail,
            itemID ?? "",
            responseID ?? "",
            isHighlighted ? "1" : "0",
        ].joined(separator: "|")
    }
}

struct LiveVoiceDebugSnapshot: Equatable {
    var backendLabel = "Waiting"
    var transcriptionModelLabel = "Waiting"
    var micCaptureLabel = "Stopped"
    var speechLabel = "No speech"
    var responseState: LiveVoiceDebugResponseState = .idle
    var activeItemID: String?
    var activeResponseID: String?
    var loopHint: String?
    var events: [LiveVoiceDebugEvent] = []
}

private struct LiveTranscriptionConfiguration: Equatable {
    let mode: LiveAudioInputMode
    let localeIdentifier: String
}

private enum LiveTranscriptionServiceError: LocalizedError {
    case recognizerUnavailable
    case speechTranscriberUnavailable
    case analyzerFormatUnavailable
    case unsupportedSpeechAnalyzerLocale
    case speechRecognitionPermissionRequired
    case noDisplayAvailable
    case missingShareableContent
    case microphoneUnavailable
    case invalidSystemAudioFormat

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for the selected language."
        case .speechTranscriberUnavailable:
            return "The newer speech transcription backend is unavailable on this Mac."
        case .analyzerFormatUnavailable:
            return "Could not configure a compatible audio format for speech transcription."
        case .unsupportedSpeechAnalyzerLocale:
            return "The newer speech transcription backend does not support the selected language."
        case .speechRecognitionPermissionRequired:
            return "Speech Recognition permission is required for local Live transcription."
        case .noDisplayAvailable:
            return "No display is available for system-audio capture."
        case .missingShareableContent:
            return "Could not access shareable screen content."
        case .microphoneUnavailable:
            return "No microphone input is available."
        case .invalidSystemAudioFormat:
            return "Could not read the captured system-audio format."
        }
    }
}

protocol LiveAudioTranscriptionPipeline: AnyObject {
    func append(buffer: AVAudioPCMBuffer) throws
    func append(sampleBuffer: CMSampleBuffer) throws
    func finish() async
    func cancel()
}

protocol LiveRealtimeChatPipeline: LiveAudioTranscriptionPipeline {
    func submitTextTurn(_ text: String) throws
}

private final class LegacySpeechRecognizerPipeline: LiveAudioTranscriptionPipeline {
    private let recognizer: SFSpeechRecognizer
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let task: SFSpeechRecognitionTask

    init(
        locale: Locale,
        onTextUpdate: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        recognizer = try Self.buildRecognizer(locale: locale)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request

        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    onTextUpdate(text)
                }
            }

            if let error {
                onError(error)
            }
        }
    }

    func append(buffer: AVAudioPCMBuffer) throws {
        request.append(buffer)
    }

    func append(sampleBuffer: CMSampleBuffer) throws {
        request.appendAudioSampleBuffer(sampleBuffer)
    }

    func finish() async {
        request.endAudio()
        task.cancel()
    }

    func cancel() {
        request.endAudio()
        task.cancel()
    }

    private static func buildRecognizer(locale: Locale) throws -> SFSpeechRecognizer {
        if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
            return recognizer
        }
        if let fallback = SFSpeechRecognizer(), fallback.isAvailable {
            return fallback
        }
        throw LiveTranscriptionServiceError.recognizerUnavailable
    }
}

@available(macOS 26.0, *)
private final class LiveAudioBufferConverter {
    enum Error: Swift.Error {
        case failedToCreateConverter
        case failedToCreateConversionBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }

        guard let converter else {
            throw Error.failedToCreateConverter
        }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard let conversionBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw Error.failedToCreateConversionBuffer
        }

        var nsError: NSError?
        var bufferProcessed = false

        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            defer { bufferProcessed = true }
            inputStatusPointer.pointee = bufferProcessed ? .noDataNow : .haveData
            return bufferProcessed ? nil : buffer
        }

        guard status != .error else {
            throw Error.conversionFailed(nsError)
        }

        return conversionBuffer
    }
}

@available(macOS 26.0, *)
private enum LiveSystemAudioPCMBridge {
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw LiveTranscriptionServiceError.invalidSystemAudioFormat
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw LiveTranscriptionServiceError.invalidSystemAudioFormat
        }

        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return buffer
    }
}

@available(macOS 26.0, *)
private final class SpeechAnalyzerTranscriptionPipeline: LiveAudioTranscriptionPipeline {
    private let onTextUpdate: (String) -> Void
    private let onError: (Error) -> Void
    private let converter = LiveAudioBufferConverter()

    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var resultTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var finalizedTranscript = AttributedString()
    private var volatileTranscript = AttributedString()

    init(
        locale: Locale,
        onTextUpdate: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        self.onTextUpdate = onTextUpdate
        self.onError = onError
        try await setUp(locale: locale)
    }

    func append(buffer: AVAudioPCMBuffer) throws {
        guard let inputBuilder, let analyzerFormat else {
            throw LiveTranscriptionServiceError.analyzerFormatUnavailable
        }

        let convertedBuffer = try converter.convertBuffer(buffer, to: analyzerFormat)
        inputBuilder.yield(AnalyzerInput(buffer: convertedBuffer))
    }

    func append(sampleBuffer: CMSampleBuffer) throws {
        let buffer = try LiveSystemAudioPCMBridge.pcmBuffer(from: sampleBuffer)
        try append(buffer: buffer)
    }

    func finish() async {
        inputBuilder?.finish()

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            onError(error)
        }

        resultTask?.cancel()
        _ = await resultTask?.value
        resultTask = nil
        await releaseLocales()
    }

    func cancel() {
        inputBuilder?.finish()
        resultTask?.cancel()

        if let analyzer {
            Task {
                await analyzer.cancelAndFinishNow()
            }
        }

        resultTask = nil
        Task {
            await releaseLocales()
        }
    }

    private func setUp(locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw LiveTranscriptionServiceError.speechTranscriberUnavailable
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        try await ensureModel(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw LiveTranscriptionServiceError.analyzerFormatUnavailable
        }
        self.analyzerFormat = analyzerFormat

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputBuilder

        resultTask = Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    self?.handle(result: result)
                }
            } catch is CancellationError {
            } catch {
                self?.onError(error)
            }
        }

        try await analyzer.start(inputSequence: inputSequence)
    }

    private func handle(result: SpeechTranscriber.Result) {
        if result.isFinal {
            finalizedTranscript += result.text
            volatileTranscript = AttributedString()
        } else {
            volatileTranscript = result.text
        }

        let transcript = String((finalizedTranscript + volatileTranscript).characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        onTextUpdate(transcript)
    }

    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw LiveTranscriptionServiceError.unsupportedSpeechAnalyzerLocale
        }

        if await installed(locale: locale) {
            return
        }

        if let installer = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installer.downloadAndInstall()
        }
    }

    private func supported(locale: Locale) async -> Bool {
        let supportedLocales = await SpeechTranscriber.supportedLocales
        let supportedIdentifiers = supportedLocales.map { $0.identifier(.bcp47) }
        return supportedIdentifiers.contains(locale.identifier(.bcp47))
    }

    private func installed(locale: Locale) async -> Bool {
        let installedLocales = await Set(SpeechTranscriber.installedLocales)
        let installedIdentifiers = installedLocales.map { $0.identifier(.bcp47) }
        return installedIdentifiers.contains(locale.identifier(.bcp47))
    }

    private func releaseLocales() async {
        let reservedLocales = await AssetInventory.reservedLocales
        for locale in reservedLocales {
            _ = await AssetInventory.release(reservedLocale: locale)
        }
    }
}

final class LiveTranscriptionService: NSObject, ObservableObject {
    private enum DebugSurface {
        static let maxEventCount = 18
        static let repeatWindow: TimeInterval = 4
    }

    private enum RealtimeFallbackCooldown {
        static let quotaOrBilling: TimeInterval = 300
        static let setupFailure: TimeInterval = 30
    }

    @Published private(set) var isListening = false
    @Published private(set) var transcriptLines: [LiveTranscriptLine] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var voiceDebugSnapshot = LiveVoiceDebugSnapshot()

    var onCompletedTurn: (@Sendable (LiveCompletedTurn) -> Void)?

    private let defaults = UserDefaults.standard
    private let requestLock = NSLock()
    private let microphoneAudioQueue = DispatchQueue(
        label: "hush.live.microphone.sample-queue",
        qos: .userInitiated
    )
    private let systemAudioQueue = DispatchQueue(
        label: "hush.live.system-audio.sample-queue",
        qos: .userInitiated
    )

    private var micEngine: AVAudioEngine?
    private var micPipeline: LiveAudioTranscriptionPipeline?
    private var sharedPipeline: LiveAudioTranscriptionPipeline?
    private var systemPipeline: LiveAudioTranscriptionPipeline?
    private var systemStream: SCStream?
    private var pipelineTask: Task<Void, Never>?
    private var activeConfiguration: LiveTranscriptionConfiguration?
    private var requestedConfiguration: LiveTranscriptionConfiguration?
    private var lastPipelineErrorBySource: [String: (message: String, occurredAt: Date)] = [:]
    private var realtimeFallbackCooldownUntil: Date?
    private var realtimeFallbackCooldownReason: String?

    deinit {
        pipelineTask?.cancel()
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()

        let pipelineState = clearPipelineState()
        for pipeline in pipelineState.pipelines {
            pipeline.cancel()
        }

        pipelineState.stream?.stopCapture { _ in }
    }

    func start(
        mode: LiveAudioInputMode,
        localeIdentifier: String,
        seedItems: [OpenAIConversationSeedItem] = []
    ) {
        let configuration = LiveTranscriptionConfiguration(
            mode: mode,
            localeIdentifier: localeIdentifier
        )

        let shouldStart = requestLock.withLock { () -> Bool in
            let shouldStart = activeConfiguration != configuration && requestedConfiguration != configuration
            if shouldStart {
                requestedConfiguration = configuration
            }
            return shouldStart
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .pipeline,
                title: shouldStart ? "Live start requested" : "Live start ignored",
                detail: "\(configuration.mode.rawValue.uppercased()) • \(configuration.localeIdentifier)",
                responseState: .idle,
                clearsLoopHint: shouldStart,
                isHighlighted: !shouldStart
            )
        )

        guard shouldStart else { return }

        pipelineTask?.cancel()
        pipelineTask = Task { [weak self] in
            guard let self else { return }
            await self.startPipelines(
                configuration: configuration,
                seedItems: seedItems
            )
        }
    }

    func stop() {
        requestLock.withLock {
            requestedConfiguration = nil
            activeConfiguration = nil
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .pipeline,
                title: "Live stop requested",
                detail: "Tearing down active voice pipelines.",
                responseState: .idle,
                micCaptureActive: false
            )
        )

        pipelineTask?.cancel()
        pipelineTask = Task { [weak self] in
            await self?.stopPipelines(resetStatus: true)
        }
    }

    func clearTranscript() {
        Task { @MainActor in
            guard !transcriptLines.isEmpty else { return }
            transcriptLines = []
        }
    }

    @MainActor
    func submitRealtimeChatTurn(_ text: String) -> Bool {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return false }

        let pipeline = requestLock.withLock { () -> LiveRealtimeChatPipeline? in
            if let sharedPipeline = sharedPipeline as? LiveRealtimeChatPipeline {
                return sharedPipeline
            }
            if let micPipeline = micPipeline as? LiveRealtimeChatPipeline {
                return micPipeline
            }
            if let systemPipeline = systemPipeline as? LiveRealtimeChatPipeline {
                return systemPipeline
            }
            return nil
        }

        guard let pipeline else { return false }

        do {
            try pipeline.submitTextTurn(normalizedText)
            return true
        } catch {
            reportPipelineError(error, source: .assistant)
            return false
        }
    }

    private func startPipelines(
        configuration: LiveTranscriptionConfiguration,
        seedItems: [OpenAIConversationSeedItem]
    ) async {
        defer {
            requestLock.withLock {
                if requestedConfiguration == configuration {
                    requestedConfiguration = nil
                }
            }
            pipelineTask = nil
        }

        await stopPipelines(resetStatus: false)
        guard !Task.isCancelled else { return }

        await MainActor.run {
            statusMessage = nil
        }

        let locale = Locale(identifier: configuration.localeIdentifier)
        var startedAny = false
        var issues: [String] = []
        var speechAuthorizationState: Bool?

        func ensureSpeechAuthorization() async -> Bool {
            if let speechAuthorizationState {
                return speechAuthorizationState
            }

            let isAuthorized = await AppPermissionAccess.requestSpeechRecognitionAccess()
            speechAuthorizationState = isAuthorized
            return isAuthorized
        }

        let micAuthorized: Bool
        if configuration.mode.includesMic {
            micAuthorized = await AppPermissionAccess.requestMicrophoneAccess()
            guard !Task.isCancelled else { return }
            if !micAuthorized {
                issues.append("Mic: microphone permission is required.")
            }
        } else {
            micAuthorized = false
        }

        let systemAuthorized: Bool
        if configuration.mode.includesSystemAudio {
            systemAuthorized = AppPermissionAccess.requestScreenCaptureAccess()
            if !systemAuthorized {
                issues.append("System: screen recording permission is required.")
            }
        } else {
            systemAuthorized = false
        }

        if configuration.mode == .both, micAuthorized, systemAuthorized {
            do {
                try await startCombinedPipeline(
                    locale: locale,
                    ensureSpeechAuthorization: ensureSpeechAuthorization,
                    seedItems: seedItems
                )
                guard !Task.isCancelled else { return }
                startedAny = true
            } catch {
                issues.append("Both: \(error.localizedDescription)")
            }
        } else {
            if configuration.mode.includesMic, micAuthorized {
                do {
                    try await startMicPipeline(
                        locale: locale,
                        ensureSpeechAuthorization: ensureSpeechAuthorization,
                        seedItems: seedItems
                    )
                    guard !Task.isCancelled else { return }
                    startedAny = true
                } catch {
                    issues.append("Mic: \(error.localizedDescription)")
                }
            }

            if configuration.mode.includesSystemAudio, systemAuthorized {
                do {
                    try await startSystemPipeline(
                        locale: locale,
                        ensureSpeechAuthorization: ensureSpeechAuthorization,
                        seedItems: seedItems
                    )
                    guard !Task.isCancelled else { return }
                    startedAny = true
                } catch {
                    issues.append("System: \(error.localizedDescription)")
                }
            }
        }

        let resolvedStartedAny = startedAny
        let resolvedStatusMessage = issues.isEmpty ? nil : issues.joined(separator: " ")

        await MainActor.run {
            isListening = resolvedStartedAny
            statusMessage = resolvedStatusMessage
        }

        if startedAny {
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .pipeline,
                    title: "Live pipeline active",
                    detail: "\(configuration.mode.rawValue.uppercased()) • \(configuration.localeIdentifier)"
                )
            )
        } else if let resolvedStatusMessage, !resolvedStatusMessage.isEmpty {
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .warning,
                    title: "Live pipeline failed to start",
                    detail: resolvedStatusMessage,
                    responseState: .idle,
                    isHighlighted: true
                )
            )
        }

        requestLock.withLock {
            activeConfiguration = startedAny ? configuration : nil
        }
    }

    private func stopPipelines(resetStatus: Bool) async {
        if let micEngine {
            micEngine.inputNode.removeTap(onBus: 0)
            micEngine.stop()
            self.micEngine = nil
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .capture,
                    title: "Mic capture stopped",
                    detail: "AVAudioEngine input tap removed.",
                    micCaptureActive: false
                )
            )
        }

        let pipelineState = clearPipelineState()

        if let stream = pipelineState.stream {
            await stopCapture(stream)
        }

        drainAudioAppendQueues()

        for pipeline in pipelineState.pipelines {
            await pipeline.finish()
        }

        requestLock.withLock {
            activeConfiguration = nil
            if resetStatus {
                requestedConfiguration = nil
            }
        }

        await MainActor.run {
            isListening = false
            if resetStatus {
                statusMessage = nil
            }
        }
    }

    private func drainAudioAppendQueues() {
        microphoneAudioQueue.sync {}
        systemAudioQueue.sync {}
    }

    private func startMicPipeline(
        locale: Locale,
        ensureSpeechAuthorization: @escaping () async -> Bool,
        seedItems: [OpenAIConversationSeedItem]
    ) async throws {
        let pipeline = try await makePipeline(
            locale: locale,
            source: .mic,
            ensureSpeechAuthorization: ensureSpeechAuthorization,
            seedItems: seedItems
        )
        storeMicPipeline(pipeline)

        do {
            try startMicEngine()
        } catch {
            let pipelineState = clearMicPipelineState()
            pipelineState?.cancel()
            throw error
        }
    }

    private func startCombinedPipeline(
        locale: Locale,
        ensureSpeechAuthorization: @escaping () async -> Bool,
        seedItems: [OpenAIConversationSeedItem]
    ) async throws {
        let pipeline = try await makePipeline(
            locale: locale,
            source: .both,
            ensureSpeechAuthorization: ensureSpeechAuthorization,
            seedItems: seedItems
        )
        storeSharedPipeline(pipeline)

        do {
            try startMicEngine()
            let stream = try await startSystemStream()
            storeSystemStream(stream)
        } catch {
            let pipelineState = clearPipelineState()
            pipelineState.pipelines.forEach { $0.cancel() }
            if let stream = pipelineState.stream {
                await stopCapture(stream)
            }
            throw error
        }
    }

    private func startMicEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw LiveTranscriptionServiceError.microphoneUnavailable
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self,
                  let copiedBuffer = Self.copyAudioBuffer(buffer) else {
                return
            }

            self.microphoneAudioQueue.async { [weak self] in
                self?.appendMicrophoneBuffer(copiedBuffer)
            }
        }

        engine.prepare()
        try engine.start()
        micEngine = engine
        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .capture,
                title: "Mic capture started",
                detail: "\(Int(inputFormat.sampleRate)) Hz • \(inputFormat.channelCount) ch",
                micCaptureActive: true
            )
        )
    }

    private func startSystemPipeline(
        locale: Locale,
        ensureSpeechAuthorization: @escaping () async -> Bool,
        seedItems: [OpenAIConversationSeedItem]
    ) async throws {
        let pipeline = try await makePipeline(
            locale: locale,
            source: .system,
            ensureSpeechAuthorization: ensureSpeechAuthorization,
            seedItems: seedItems
        )
        let stream = try await startSystemStream()
        storeSystemPipeline(pipeline: pipeline, stream: stream)
    }

    private func startSystemStream() async throws -> SCStream {
        let shareableContent = try await loadShareableContent()
        guard let display = preferredDisplay(from: shareableContent.displays) else {
            throw LiveTranscriptionServiceError.noDisplayAvailable
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = max(display.width, 2)
        configuration.height = max(display.height, 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        configuration.queueDepth = 3
        configuration.capturesAudio = true
        configuration.sampleRate = 44_100
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: systemAudioQueue)
        try await startCapture(stream)
        return stream
    }

    private func makePipeline(
        locale: Locale,
        source: LiveTranscriptSource,
        ensureSpeechAuthorization: @escaping () async -> Bool,
        seedItems: [OpenAIConversationSeedItem]
    ) async throws -> LiveAudioTranscriptionPipeline {
        let onTextUpdate: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.setTranscriptLine(source: source, text: text)
            }
        }

        let onError: @Sendable (Error) -> Void = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.reportPipelineError(error, source: source)
            }
        }

        if let realtimePipeline = try await makeRealtimePipeline(
            locale: locale,
            source: source,
            onTextUpdate: onTextUpdate,
            onError: onError,
            seedItems: seedItems
        ) {
            return realtimePipeline
        }

        guard await ensureSpeechAuthorization() else {
            throw LiveTranscriptionServiceError.speechRecognitionPermissionRequired
        }

        if #available(macOS 26.0, *) {
            do {
                recordDebugTransition(
                    LiveVoiceDebugTransition(
                        category: .pipeline,
                        title: "Local pipeline selected",
                        detail: "SpeechAnalyzer transcription",
                        backendLabel: "Local SpeechAnalyzer",
                        transcriptionModelLabel: "SpeechTranscriber"
                    )
                )

                return try await SpeechAnalyzerTranscriptionPipeline(
                    locale: locale,
                    onTextUpdate: onTextUpdate,
                    onError: onError
                )
            } catch {
                recordDebugTransition(
                    LiveVoiceDebugTransition(
                        category: .warning,
                        title: "SpeechAnalyzer unavailable",
                        detail: error.localizedDescription,
                        isHighlighted: true
                    )
                )
                recordDebugTransition(
                    LiveVoiceDebugTransition(
                        category: .pipeline,
                        title: "Local fallback selected",
                        detail: "Legacy speech recognizer",
                        backendLabel: "Local SpeechRecognizer",
                        transcriptionModelLabel: "SFSpeechRecognizer"
                    )
                )
                return try LegacySpeechRecognizerPipeline(
                    locale: locale,
                    onTextUpdate: onTextUpdate,
                    onError: onError
                )
            }
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .pipeline,
                title: "Local fallback selected",
                detail: "Legacy speech recognizer",
                backendLabel: "Local SpeechRecognizer",
                transcriptionModelLabel: "SFSpeechRecognizer"
            )
        )
        return try LegacySpeechRecognizerPipeline(
            locale: locale,
            onTextUpdate: onTextUpdate,
            onError: onError
        )
    }

    private func makeRealtimePipeline(
        locale: Locale,
        source: LiveTranscriptSource,
        onTextUpdate: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (Error) -> Void,
        seedItems: [OpenAIConversationSeedItem]
    ) async throws -> OpenAIRealtimeConversationPipeline? {
        if let cooldownUntil = realtimeFallbackCooldownUntil,
           cooldownUntil > Date() {
            let seconds = max(1, Int(ceil(cooldownUntil.timeIntervalSinceNow)))
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .warning,
                    title: "Realtime cooldown",
                    detail: "\(realtimeFallbackCooldownReason ?? "Recent Realtime setup failed"). Retrying in \(seconds)s.",
                    backendLabel: "Local fallback",
                    isHighlighted: true
                )
            )
            return nil
        }

        let accountContext = await MainActor.run { () -> (ProviderAccountRecord, ProviderAccountLocalSecrets)? in
            guard let account = ProviderAccountStore.shared.primaryAccount(for: .openAI) else {
                return nil
            }

            return (account, ProviderAccountStore.shared.secrets(for: account))
        }

        guard let (account, secrets) = accountContext else {
            return nil
        }

        let credentials: OpenAIRealtimeSessionCredentials
        do {
            let preferredRealtimeModel = AssistantModelCatalog.storedRealtimeModelValue(defaults: defaults)
            let preferredRealtimeTranscriptionModel =
                AssistantModelCatalog.storedRealtimeTranscriptionModelValue(defaults: defaults)
            credentials = try await OpenAIService.shared.realtimeSessionCredentials(
                record: account,
                secrets: secrets,
                preferredStoredValue: preferredRealtimeModel,
                preferredTranscriptionStoredValue: preferredRealtimeTranscriptionModel
            )
        } catch {
            rememberRealtimeFallbackCooldown(after: error)
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .warning,
                    title: "Realtime unavailable",
                    detail: error.localizedDescription,
                    isHighlighted: true
                )
            )
            return nil
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .pipeline,
                title: "Realtime pipeline selected",
                detail: credentials.modelID,
                backendLabel: "OpenAI Realtime",
                transcriptionModelLabel: credentials.transcriptionModelID,
                clearsLoopHint: true
            )
        )

        do {
            return try await OpenAIRealtimeConversationPipeline(
                credentials: credentials,
                source: source,
                locale: locale,
                reduceNoise: bool(forKey: "behaviours.live.reduceNoise", default: true),
                interruptWhenSpeak: bool(forKey: "behaviours.live.interruptWhenSpeak", default: true),
                seedItems: seedItems,
                onTextUpdate: onTextUpdate,
                onAssistantTextUpdate: { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.setTranscriptLine(source: .assistant, text: text)
                    }
                },
                onCompletedTurn: { [weak self] turn in
                    self?.onCompletedTurn?(turn)
                },
                onDebugTransition: { [weak self] transition in
                    self?.recordDebugTransition(transition)
                },
                onError: onError
            )
        } catch {
            rememberRealtimeFallbackCooldown(after: error)
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .warning,
                    title: "Realtime pipeline setup failed",
                    detail: error.localizedDescription,
                    isHighlighted: true
                )
            )
            return nil
        }
    }

    private func appendMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        let target = requestLock.withLock { () -> (source: LiveTranscriptSource, pipeline: LiveAudioTranscriptionPipeline)? in
            if let sharedPipeline {
                return (.both, sharedPipeline)
            }
            if let micPipeline {
                return (.mic, micPipeline)
            }
            return nil
        }

        guard let target else { return }

        let appendResult = Result { try target.pipeline.append(buffer: buffer) }
        if case let .failure(error) = appendResult {
            Task { @MainActor [weak self] in
                self?.reportPipelineError(error, source: target.source)
            }
        }
    }

    private func appendSystemSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let target = requestLock.withLock { () -> (source: LiveTranscriptSource, pipeline: LiveAudioTranscriptionPipeline)? in
            if let sharedPipeline {
                return (.both, sharedPipeline)
            }
            if let systemPipeline {
                return (.system, systemPipeline)
            }
            return nil
        }

        guard let target else { return }

        let appendResult = Result { try target.pipeline.append(sampleBuffer: sampleBuffer) }
        if case let .failure(error) = appendResult {
            Task { @MainActor [weak self] in
                self?.reportPipelineError(error, source: target.source)
            }
        }
    }

    private static func copyAudioBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copiedBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: max(buffer.frameLength, 1)
        ) else {
            return nil
        }

        copiedBuffer.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copiedBuffer.mutableAudioBufferList)
        for index in 0..<min(sourceBuffers.count, destinationBuffers.count) {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData else {
                continue
            }

            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }

        return copiedBuffer
    }

    @MainActor
    private func reportPipelineError(_ error: Error, source: LiveTranscriptSource) {
        let message = "\(source.label): \(error.localizedDescription)"
        let now = Date()
        let throttleKey = source.rawValue
        if let lastError = lastPipelineErrorBySource[throttleKey],
           lastError.message == message,
           now.timeIntervalSince(lastError.occurredAt) < 2 {
            if isListening, statusMessage != message {
                statusMessage = message
            }
            return
        }

        lastPipelineErrorBySource[throttleKey] = (message, now)

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .warning,
                title: "Pipeline error",
                detail: message,
                isHighlighted: true
            )
        )

        Task { @MainActor in
            guard isListening else { return }
            guard statusMessage != message else { return }
            statusMessage = message
        }
    }

    @MainActor
    private func setTranscriptLine(source: LiveTranscriptSource, text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedText.isEmpty {
            guard let index = transcriptLines.firstIndex(where: { $0.source == source }) else { return }
            transcriptLines.remove(at: index)
            return
        }

        if let index = transcriptLines.firstIndex(where: { $0.source == source }) {
            guard transcriptLines[index].text != normalizedText else { return }
            transcriptLines[index].text = normalizedText
        } else {
            transcriptLines.append(LiveTranscriptLine(source: source, text: normalizedText))
            transcriptLines.sort { lhs, rhs in
                lhs.source.sortOrder < rhs.source.sortOrder
            }
        }
    }

    private func preferredDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        guard !displays.isEmpty else { return nil }
        if let screenNumber = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let mainDisplayID = CGDirectDisplayID(screenNumber.uint32Value)
            if let matching = displays.first(where: { $0.displayID == mainDisplayID }) {
                return matching
            }
        }
        return displays.first
    }

    private func loadShareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            ) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: LiveTranscriptionServiceError.missingShareableContent)
                }
            }
        }
    }

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stopCapture { _ in
                continuation.resume(returning: ())
            }
        }
    }

    private func recordDebugTransition(_ transition: LiveVoiceDebugTransition) {
        Task { @MainActor [weak self] in
            self?.applyDebugTransition(transition)
        }
    }

    @MainActor
    private func applyDebugTransition(_ transition: LiveVoiceDebugTransition) {
        var snapshot = voiceDebugSnapshot

        if let backendLabel = transition.backendLabel, !backendLabel.isEmpty {
            snapshot.backendLabel = backendLabel
        }
        if let transcriptionModelLabel = transition.transcriptionModelLabel, !transcriptionModelLabel.isEmpty {
            snapshot.transcriptionModelLabel = transcriptionModelLabel
        }
        if let micCaptureActive = transition.micCaptureActive {
            snapshot.micCaptureLabel = micCaptureActive ? "Running" : "Stopped"
        }
        if let speechLabel = transition.speechLabel, !speechLabel.isEmpty {
            snapshot.speechLabel = speechLabel
        }
        if transition.clearsLoopHint {
            snapshot.loopHint = nil
        }
        if let loopHint = transition.loopHint, !loopHint.isEmpty {
            snapshot.loopHint = loopHint
        }
        if let responseState = transition.responseState {
            snapshot.responseState = responseState
            switch responseState {
            case .requested, .active, .replaced:
                if let itemID = transition.itemID, !itemID.isEmpty {
                    snapshot.activeItemID = itemID
                }
                if let responseID = transition.responseID, !responseID.isEmpty {
                    snapshot.activeResponseID = responseID
                }

            case .idle:
                snapshot.activeItemID = nil
                snapshot.activeResponseID = nil

            case .cancelled, .completed:
                if transition.itemID == nil || transition.itemID == snapshot.activeItemID {
                    snapshot.activeItemID = nil
                }
                if transition.responseID == nil || transition.responseID == snapshot.activeResponseID {
                    snapshot.activeResponseID = nil
                }
            }
        }

        let now = Date()
        let nextEvent = LiveVoiceDebugEvent(
            occurredAt: now,
            category: transition.category,
            title: transition.title,
            detail: transition.detail,
            itemID: transition.itemID,
            responseID: transition.responseID,
            isHighlighted: transition.isHighlighted
        )

        if let lastIndex = snapshot.events.indices.last,
           snapshot.events[lastIndex].signature == nextEvent.signature,
           now.timeIntervalSince(snapshot.events[lastIndex].occurredAt) <= DebugSurface.repeatWindow {
            snapshot.events[lastIndex].occurredAt = now
            snapshot.events[lastIndex].repeatCount += 1

            if snapshot.events[lastIndex].repeatCount >= 2,
               snapshot.loopHint == nil || snapshot.loopHint?.isEmpty == true {
                let repeatedID = shortDebugIdentifier(snapshot.events[lastIndex].itemID ?? snapshot.events[lastIndex].responseID)
                snapshot.loopHint = "Repeated \(snapshot.events[lastIndex].title.lowercased())\(repeatedID.map { " for \($0)" } ?? "") inside 4 seconds."
            }
        } else {
            snapshot.events.append(nextEvent)
            if snapshot.events.count > DebugSurface.maxEventCount {
                snapshot.events.removeFirst(snapshot.events.count - DebugSurface.maxEventCount)
            }
        }

        voiceDebugSnapshot = snapshot
    }

    private func shortDebugIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 8 ? String(trimmed.suffix(8)) : trimmed
    }

    private func clearPipelineState() -> (stream: SCStream?, pipelines: [LiveAudioTranscriptionPipeline]) {
        requestLock.withLock {
            let pipelines = [micPipeline, sharedPipeline, systemPipeline].compactMap { $0 }
            micPipeline = nil
            sharedPipeline = nil
            systemPipeline = nil

            let stream = systemStream
            systemStream = nil
            return (stream, pipelines)
        }
    }

    private func storeSystemPipeline(
        pipeline: LiveAudioTranscriptionPipeline,
        stream: SCStream
    ) {
        requestLock.withLock {
            systemPipeline = pipeline
            systemStream = stream
        }
    }

    private func storeMicPipeline(_ pipeline: LiveAudioTranscriptionPipeline) {
        requestLock.withLock {
            micPipeline = pipeline
        }
    }

    private func clearMicPipelineState() -> LiveAudioTranscriptionPipeline? {
        requestLock.withLock {
            let pipeline = micPipeline
            micPipeline = nil
            return pipeline
        }
    }

    private func storeSharedPipeline(_ pipeline: LiveAudioTranscriptionPipeline) {
        requestLock.withLock {
            sharedPipeline = pipeline
        }
    }

    private func storeSystemStream(_ stream: SCStream) {
        requestLock.withLock {
            systemStream = stream
        }
    }

    private func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func rememberRealtimeFallbackCooldown(after error: Error) {
        let message = error.localizedDescription
        let lowercasedMessage = message.lowercased()
        let duration: TimeInterval

        if lowercasedMessage.contains("quota")
            || lowercasedMessage.contains("billing")
            || lowercasedMessage.contains("insufficient_quota")
            || lowercasedMessage.contains("rate limit") {
            duration = RealtimeFallbackCooldown.quotaOrBilling
        } else {
            duration = RealtimeFallbackCooldown.setupFailure
        }

        realtimeFallbackCooldownUntil = Date().addingTimeInterval(duration)
        realtimeFallbackCooldownReason = message
    }
}

extension LiveTranscriptionService: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        appendSystemSampleBuffer(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard isListening else { return }
            statusMessage = "System capture stopped: \(error.localizedDescription)"
        }
    }
}
