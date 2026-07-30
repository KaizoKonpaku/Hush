import AVFoundation
import CoreMedia
import Foundation

struct LiveCompletedTurn: Sendable {
    let prompt: String
    let response: String
    let startedAt: Date
    let finishedAt: Date
    let realtimeSessionID: String?
    let userItemID: String?
    let assistantItemID: String?
    let assistantResponseID: String?
    let wasInterrupted: Bool
    let wasTruncated: Bool
}

private enum OpenAIRealtimeConversationError: LocalizedError {
    case connectionTimedOut
    case notConnected
    case invalidEvent
    case invalidAudioChunk
    case sessionFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionTimedOut:
            return "OpenAI Realtime took too long to connect."
        case .notConnected:
            return "OpenAI Realtime is not connected."
        case .invalidEvent:
            return "OpenAI Realtime returned an unreadable event."
        case .invalidAudioChunk:
            return "OpenAI Realtime returned an unreadable audio chunk."
        case let .sessionFailed(message):
            return message
        }
    }
}

private struct RealtimeDraftTurn {
    let userItemID: String
    let startedAt: Date
    var prompt = ""
    var assistantText = ""
    var assistantAudioTranscript = ""
    var assistantItemID: String?
    var assistantResponseID: String?
    var wasInterrupted = false
    var wasTruncated = false
    var isCompleted = false

    var effectiveAssistantResponse: String {
        let preferredText = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferredText.isEmpty {
            return preferredText
        }

        return assistantAudioTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RealtimePlaybackTruncation {
    let itemID: String
    let audioEndMilliseconds: Int
}

private enum RealtimeMicrophoneBarrierState: Equatable {
    case idle
    case playback
    case cooldown

    var debugLabel: String {
        switch self {
        case .idle:
            return "idle"
        case .playback:
            return "playback"
        case .cooldown:
            return "cooldown"
        }
    }
}

private final class RealtimePCM16Encoder {
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    private var converter: AVAudioConverter?

    func encode(_ buffer: AVAudioPCMBuffer) throws -> [Int16] {
        let convertedBuffer = try convert(buffer)
        guard let channelData = convertedBuffer.floatChannelData?[0] else {
            return []
        }

        let frameCount = Int(convertedBuffer.frameLength)
        var samples = [Int16]()
        samples.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let sample = max(-1.0, min(1.0, channelData[index]))
            let scaled = sample < 0 ? sample * Float(Int16.min) * -1 : sample * Float(Int16.max)
            samples.append(Int16(scaled.rounded()))
        }

        return samples
    }

    private func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.format != targetFormat else {
            return buffer
        }

        if converter == nil
            || converter?.inputFormat != buffer.format
            || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converter?.primeMethod = .none
        }

        guard let converter else {
            throw OpenAIRealtimeConversationError.invalidAudioChunk
        }

        let outputFrameCount = AVAudioFrameCount(
            (Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate).rounded(.up)
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: max(outputFrameCount, 1)
        ) else {
            throw OpenAIRealtimeConversationError.invalidAudioChunk
        }

        var sourceBufferConsumed = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            defer { sourceBufferConsumed = true }
            outStatus.pointee = sourceBufferConsumed ? .noDataNow : .haveData
            return sourceBufferConsumed ? nil : buffer
        }

        guard status != .error else {
            throw conversionError ?? OpenAIRealtimeConversationError.invalidAudioChunk
        }

        return convertedBuffer
    }
}

private enum RealtimeSystemAudioPCMBridge {
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw OpenAIRealtimeConversationError.invalidAudioChunk
        }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameCount, 1)) else {
            throw OpenAIRealtimeConversationError.invalidAudioChunk
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

private final class RealtimeInputMixer {
    private enum Backlog {
        static let maxQueuedSamplesPerSource = 24_000 * 8
        static let compactThreshold = 24_000
    }

    private let chunkSampleCount: Int
    private let callbackQueue = DispatchQueue(label: "hush.realtime.input-mixer.callback")
    private let timer: DispatchSourceTimer
    private let lock = NSLock()
    private let onChunkReady: @Sendable (Data) -> Void

    private var microphoneSamples: [Int16] = []
    private var systemSamples: [Int16] = []
    private var microphoneReadIndex = 0
    private var systemReadIndex = 0
    private var hasBeenStopped = false

    init(
        chunkSampleCount: Int = 960,
        onChunkReady: @escaping @Sendable (Data) -> Void
    ) {
        self.chunkSampleCount = chunkSampleCount
        self.onChunkReady = onChunkReady
        self.timer = DispatchSource.makeTimerSource(queue: callbackQueue)
        self.timer.schedule(deadline: .now() + .milliseconds(40), repeating: .milliseconds(40))
        self.timer.setEventHandler { [weak self] in
            self?.emitNextChunk()
        }
        self.timer.resume()
    }

    deinit {
        stop(flushRemaining: false)
    }

    func appendMicrophone(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        lock.withLock {
            guard !hasBeenStopped else { return }
            append(samples, to: &microphoneSamples, readIndex: &microphoneReadIndex)
        }
    }

    func appendSystem(_ samples: [Int16]) {
        guard !samples.isEmpty else { return }
        lock.withLock {
            guard !hasBeenStopped else { return }
            append(samples, to: &systemSamples, readIndex: &systemReadIndex)
        }
    }

    func stop(flushRemaining: Bool) {
        let remainingChunks = lock.withLock { () -> [Data] in
            guard !hasBeenStopped else { return [] }
            hasBeenStopped = true
            timer.setEventHandler {}
            timer.cancel()

            guard flushRemaining else {
                microphoneSamples.removeAll(keepingCapacity: false)
                systemSamples.removeAll(keepingCapacity: false)
                microphoneReadIndex = 0
                systemReadIndex = 0
                return []
            }

            var chunks: [Data] = []
            while !microphoneSamples.isEmpty || !systemSamples.isEmpty {
                if let chunk = makeChunk(sampleCount: chunkSampleCount) {
                    chunks.append(chunk)
                } else {
                    break
                }
            }
            return chunks
        }

        for chunk in remainingChunks where !chunk.isEmpty {
            onChunkReady(chunk)
        }
    }

    private func append(_ samples: [Int16], to buffer: inout [Int16], readIndex: inout Int) {
        compact(buffer: &buffer, readIndex: &readIndex, force: false)
        buffer.append(contentsOf: samples)

        let queuedSampleCount = buffer.count - readIndex
        if queuedSampleCount > Backlog.maxQueuedSamplesPerSource {
            readIndex += queuedSampleCount - Backlog.maxQueuedSamplesPerSource
            compact(buffer: &buffer, readIndex: &readIndex, force: false)
        }
    }

    private func emitNextChunk() {
        guard let chunk = lock.withLock({ makeChunk(sampleCount: chunkSampleCount) }) else {
            return
        }

        guard !chunk.isEmpty else { return }
        onChunkReady(chunk)
    }

    private func makeChunk(sampleCount: Int) -> Data? {
        let microphoneQueuedCount = microphoneSamples.count - microphoneReadIndex
        let systemQueuedCount = systemSamples.count - systemReadIndex
        let requiredCount = min(
            sampleCount,
            max(microphoneQueuedCount, systemQueuedCount)
        )

        guard requiredCount > 0 else { return nil }

        var mixedSamples = [Int16]()
        mixedSamples.reserveCapacity(requiredCount)

        for index in 0..<requiredCount {
            let hasMicrophoneSample = index < microphoneQueuedCount
            let hasSystemSample = index < systemQueuedCount
            let microphoneSample = hasMicrophoneSample ? Int(microphoneSamples[microphoneReadIndex + index]) : 0
            let systemSample = hasSystemSample ? Int(systemSamples[systemReadIndex + index]) : 0
            let divisor = (hasMicrophoneSample && hasSystemSample) ? 2 : 1
            let combinedSample = max(Int(Int16.min), min(Int(Int16.max), (microphoneSample + systemSample) / divisor))
            mixedSamples.append(Int16(combinedSample))
        }

        microphoneReadIndex += min(requiredCount, microphoneQueuedCount)
        systemReadIndex += min(requiredCount, systemQueuedCount)
        compact(buffer: &microphoneSamples, readIndex: &microphoneReadIndex, force: false)
        compact(buffer: &systemSamples, readIndex: &systemReadIndex, force: false)

        return mixedSamples.withUnsafeBufferPointer { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else {
                return Data()
            }

            return Data(
                bytes: baseAddress,
                count: bufferPointer.count * MemoryLayout<Int16>.size
            )
        }
    }

    private func compact(buffer: inout [Int16], readIndex: inout Int, force: Bool) {
        guard readIndex > 0 else { return }
        guard force || readIndex >= Backlog.compactThreshold || readIndex > buffer.count / 2 else {
            return
        }

        buffer.removeFirst(readIndex)
        readIndex = 0
    }
}

private final class RealtimePCMOutputPlayer {
    private let queue = DispatchQueue(label: "hush.realtime.audio-player")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    private var activeItemID: String?
    private var activeItemStartSampleTime: AVAudioFramePosition = 0
    private var scheduledSampleCursor: AVAudioFramePosition = 0
    private var pendingBufferCount = 0
    private var lastPlaybackFinishedAt = Date.distantPast

    init() {
        queue.sync {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
            } catch {
                NSLog("[HUSH] Realtime audio player start failed: \(error.localizedDescription)")
            }
        }
    }

    func enqueue(base64AudioChunk: String, itemID: String) throws {
        guard let data = Data(base64Encoded: base64AudioChunk) else {
            throw OpenAIRealtimeConversationError.invalidAudioChunk
        }

        try queue.sync {
            try ensureEngineStarted()

            let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameCount, 1)),
                  let channelData = buffer.int16ChannelData?[0] else {
                throw OpenAIRealtimeConversationError.invalidAudioChunk
            }

            buffer.frameLength = frameCount
            data.withUnsafeBytes { rawBuffer in
                guard let source = rawBuffer.baseAddress else { return }
                memcpy(channelData, source, data.count)
            }

            if activeItemID != itemID {
                activeItemID = itemID
                activeItemStartSampleTime = scheduledSampleCursor
            }

            pendingBufferCount += 1
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    self.pendingBufferCount = max(0, self.pendingBufferCount - 1)
                    guard self.pendingBufferCount == 0 else { return }

                    self.activeItemID = nil
                    self.activeItemStartSampleTime = 0
                    self.scheduledSampleCursor = 0
                    self.lastPlaybackFinishedAt = Date()
                }
            }
            scheduledSampleCursor += AVAudioFramePosition(frameCount)

            if !player.isPlaying {
                player.play()
            }
        }
    }

    func interruptCurrentPlayback() -> RealtimePlaybackTruncation? {
        queue.sync { () -> RealtimePlaybackTruncation? in
            guard let currentItemID = activeItemID else { return nil }
            let playedFrames = playedFramesForActiveItem()
            let playedMilliseconds = max(0, Int((Double(playedFrames) / 24_000.0) * 1_000.0))

            player.stop()
            player.reset()
            let interruptedItemID = currentItemID
            self.activeItemID = nil
            activeItemStartSampleTime = 0
            scheduledSampleCursor = 0
            pendingBufferCount = 0
            lastPlaybackFinishedAt = Date()

            return RealtimePlaybackTruncation(
                itemID: interruptedItemID,
                audioEndMilliseconds: playedMilliseconds
            )
        }
    }

    func stop() {
        queue.sync {
            player.stop()
            player.reset()
            engine.stop()
            activeItemID = nil
            activeItemStartSampleTime = 0
            scheduledSampleCursor = 0
            pendingBufferCount = 0
            lastPlaybackFinishedAt = Date()
        }
    }

    func suppressesMicrophoneInput(gracePeriod: TimeInterval) -> Bool {
        queue.sync {
            if pendingBufferCount > 0 || activeItemID != nil {
                return true
            }

            return Date().timeIntervalSince(lastPlaybackFinishedAt) < gracePeriod
        }
    }

    func microphoneBarrierState(gracePeriod: TimeInterval) -> RealtimeMicrophoneBarrierState {
        queue.sync {
            if pendingBufferCount > 0 || activeItemID != nil {
                return .playback
            }

            if Date().timeIntervalSince(lastPlaybackFinishedAt) < gracePeriod {
                return .cooldown
            }

            return .idle
        }
    }

    private func ensureEngineStarted() throws {
        if engine.isRunning {
            return
        }
        try engine.start()
    }

    private func playedFramesForActiveItem() -> AVAudioFramePosition {
        guard let lastRenderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: lastRenderTime) else {
            return 0
        }

        return max(0, playerTime.sampleTime - activeItemStartSampleTime)
    }
}

final class OpenAIRealtimeConversationPipeline: LiveRealtimeChatPipeline {
    private enum PlaybackGuards {
        static let microphoneSuppressionGracePeriod: TimeInterval = 1.2
    }

    private enum LocalSpeechDetection {
        static let minimumCalibrationFrames = 5
        static let minimumRMS: Float = 0.032
        static let playbackRelativeMultiplier: Float = 3.2
        static let cooldownRelativeMultiplier: Float = 2.4
        static let requiredConsecutiveFrames = 5
        static let baselineSmoothing: Float = 0.08
        static let baselineRiseCap: Float = 1.08
    }

    private enum ManualTurnDetection {
        static let speechStartRMS: Float = 0.018
        static let speechContinueRMS: Float = 0.012
        static let requiredSpeechFrames = 3
        static let silenceDuration: TimeInterval = 0.72
        static let minimumTurnDuration: TimeInterval = 0.32
        static let maximumTurnDuration: TimeInterval = 18
        static let sampleRate: Double = 24_000
    }

    private let source: LiveTranscriptSource
    private let locale: Locale
    private let interruptWhenSpeak: Bool
    private let seedItems: [OpenAIConversationSeedItem]
    private let onTextUpdate: @Sendable (String) -> Void
    private let onAssistantTextUpdate: @Sendable (String) -> Void
    private let onCompletedTurn: @Sendable (LiveCompletedTurn) -> Void
    private let onDebugTransition: @Sendable (LiveVoiceDebugTransition) -> Void
    private let onError: @Sendable (Error) -> Void

    private let session: URLSession
    private let micEncoder = RealtimePCM16Encoder()
    private let systemEncoder = RealtimePCM16Encoder()
    private let audioPlayer = RealtimePCMOutputPlayer()
    private lazy var inputMixer = RealtimeInputMixer { [weak self] chunk in
        self?.handleInputAudioChunk(chunk)
    }
    private let lock = NSLock()

    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendChain: Task<Void, Never>?
    private var isReady = false
    private var connectionError: Error?
    private var realtimeSessionID: String?
    private var activeTurnItemID: String?
    private var pendingResponseTurnItemIDs: [String] = []
    private var userItemIDByResponseID: [String: String] = [:]
    private var userItemIDByAssistantItemID: [String: String] = [:]
    private var userItemIDByResponseCreateEventID: [String: String] = [:]
    private var responseOutputModalitiesByItemID: [String: [String]] = [:]
    private var visibleAssistantTurnItemID: String?
    private var responseRequestedItemIDs = Set<String>()
    private var turnsByItemID: [String: RealtimeDraftTurn] = [:]
    private var responseRetryTask: Task<Void, Never>?
    private var lastSystemAudioSuppressionDebugAt = Date.distantPast
    private var lastMicrophoneSuppressionDebugAt = Date.distantPast
    private var suppressedMicrophoneBaseline: Float = 0
    private var suppressedMicrophoneCalibrationFrames = 0
    private var suppressedMicrophoneTriggerCount = 0
    private var manualTurnStartedAt: Date?
    private var manualTurnLastSpeechAt: Date?
    private var manualTurnSpeechFrameCount = 0
    private var manualTurnAudioDuration: TimeInterval = 0
    private var manualTurnHasAppendedAudio = false

    init(
        credentials: OpenAIRealtimeSessionCredentials,
        source: LiveTranscriptSource,
        locale: Locale,
        reduceNoise: Bool,
        interruptWhenSpeak: Bool,
        seedItems: [OpenAIConversationSeedItem] = [],
        onTextUpdate: @escaping @Sendable (String) -> Void,
        onAssistantTextUpdate: @escaping @Sendable (String) -> Void,
        onCompletedTurn: @escaping @Sendable (LiveCompletedTurn) -> Void,
        onDebugTransition: @escaping @Sendable (LiveVoiceDebugTransition) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async throws {
        self.source = source
        self.locale = locale
        self.interruptWhenSpeak = interruptWhenSpeak
        self.seedItems = seedItems
        self.onTextUpdate = onTextUpdate
        self.onAssistantTextUpdate = onAssistantTextUpdate
        self.onCompletedTurn = onCompletedTurn
        self.onDebugTransition = onDebugTransition
        self.onError = onError
        self.session = URLSession(configuration: .ephemeral)

        do {
            try await connect(
                credentials: credentials,
                reduceNoise: reduceNoise
            )
        } catch {
            cancel()
            throw error
        }
    }

    deinit {
        cancel()
    }

    func append(buffer: AVAudioPCMBuffer) throws {
        let samples = try micEncoder.encode(buffer)
        guard !samples.isEmpty else { return }

        let barrierState = audioPlayer.microphoneBarrierState(
            gracePeriod: PlaybackGuards.microphoneSuppressionGracePeriod
        )

        switch barrierState {
        case .idle:
            resetLocalSpeechDetector()
            inputMixer.appendMicrophone(samples)

        case .playback:
            if interruptWhenSpeak,
               shouldTreatSuppressedMicrophoneAudioAsUserSpeech(
                samples,
                state: .playback
               ) {
                recordDebugTransition(
                    LiveVoiceDebugTransition(
                        category: .speech,
                        title: "Speech detected",
                        detail: "Local detector fired during playback.",
                        speechLabel: "Local playback interrupt",
                        loopHint: "Local speech detection interrupted playback. HUSH drops the guarded mic frame so assistant audio cannot become the next user turn.",
                        isHighlighted: true
                    )
                )
                interruptAssistantPlaybackForLocalSpeech()
                resetLocalSpeechDetector()
            } else {
                recordMicrophoneSuppressionIfNeeded(barrierState)
            }

        case .cooldown:
            if shouldTreatSuppressedMicrophoneAudioAsUserSpeech(
                samples,
                state: .cooldown
            ) {
                recordDebugTransition(
                    LiveVoiceDebugTransition(
                        category: .speech,
                        title: "Mic cooldown suppressed",
                        detail: "Dropped local speech-like mic audio during playback cooldown.",
                        speechLabel: "Cooldown suppressed",
                        loopHint: "The mic heard speech-like audio inside the playback cooldown window, but HUSH suppressed it instead of creating another response.",
                        isHighlighted: true
                    )
                )
                resetLocalSpeechDetector()
            } else {
                recordMicrophoneSuppressionIfNeeded(barrierState)
            }
        }
    }

    func append(sampleBuffer: CMSampleBuffer) throws {
        if let barrierState = systemAudioSuppressionBarrierState() {
            recordSystemAudioSuppressionIfNeeded(barrierState)
            return
        }

        let pcmBuffer = try RealtimeSystemAudioPCMBridge.pcmBuffer(from: sampleBuffer)
        let samples = try systemEncoder.encode(pcmBuffer)
        inputMixer.appendSystem(samples)
    }

    func submitTextTurn(_ text: String) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }
        guard lock.withLock({ isReady && connectionError == nil }) else {
            throw OpenAIRealtimeConversationError.notConnected
        }

        onTextUpdate(normalizedText)
        onAssistantTextUpdate("")

        let itemID = "hush_text_\(UUID().uuidString)"
        enqueueEvent(
            [
                "type": "conversation.item.create",
                "item": [
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": normalizedText,
                        ],
                    ],
                ],
            ]
        )

        let requestState = lock.withLock {
            () -> (shouldRequestResponse: Bool, deferredBecauseResponseActive: Bool) in
            turnsByItemID[itemID] = RealtimeDraftTurn(
                userItemID: itemID,
                startedAt: Date(),
                prompt: normalizedText
            )
            responseOutputModalitiesByItemID[itemID] = ["text"]

            let responseAlreadyActive =
                userItemIDByResponseID.isEmpty == false
                || responseRequestedItemIDs.isEmpty == false

            if !pendingResponseTurnItemIDs.contains(itemID) {
                pendingResponseTurnItemIDs.append(itemID)
            }

            activeTurnItemID = itemID

            let shouldRequestResponse =
                pendingResponseTurnItemIDs.first == itemID
                && !responseAlreadyActive

            if shouldRequestResponse {
                responseRequestedItemIDs.insert(itemID)
            }

            return (shouldRequestResponse, !shouldRequestResponse)
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .response,
                title: requestState.deferredBecauseResponseActive ? "Text response deferred" : "Text turn submitted",
                detail: requestState.deferredBecauseResponseActive
                    ? "Realtime chat text queued until the active response closes."
                    : "Realtime chat text added with conversation.item.create.",
                itemID: itemID,
                responseState: requestState.deferredBecauseResponseActive ? nil : .requested,
                isHighlighted: requestState.deferredBecauseResponseActive
            )
        )

        guard requestState.shouldRequestResponse else { return }
        requestResponse(for: itemID, detail: "Queued text response.create after chat input.")
    }

    func finish() async {
        inputMixer.stop(flushRemaining: false)
        resetManualInputAudioTurn()
        receiveTask?.cancel()
        sendChain?.cancel()
        responseRetryTask?.cancel()
        socketTask?.cancel(with: .normalClosure, reason: nil)
        audioPlayer.stop()
        session.invalidateAndCancel()
    }

    func cancel() {
        inputMixer.stop(flushRemaining: false)
        receiveTask?.cancel()
        sendChain?.cancel()
        responseRetryTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        audioPlayer.stop()
        session.invalidateAndCancel()
    }

    private func connect(
        credentials: OpenAIRealtimeSessionCredentials,
        reduceNoise: Bool
    ) async throws {
        guard var components = URLComponents(string: "wss://api.openai.com/v1/realtime") else {
            throw OpenAIRealtimeConversationError.notConnected
        }
        components.queryItems = [URLQueryItem(name: "model", value: credentials.modelID)]
        guard let url = components.url else {
            throw OpenAIRealtimeConversationError.notConnected
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")

        if !credentials.organizationID.isEmpty {
            request.setValue(credentials.organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }

        let socketTask = session.webSocketTask(with: request)
        self.socketTask = socketTask
        socketTask.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        enqueueEvent(
            [
                "type": "session.update",
                "session": sessionUpdatePayload(
                    credentials: credentials,
                    reduceNoise: reduceNoise
                ),
            ]
        )

        try await waitForReadyState()
        seedConversationIfNeeded()
    }

    private func sessionUpdatePayload(
        credentials: OpenAIRealtimeSessionCredentials,
        reduceNoise: Bool
    ) -> [String: Any] {
        var inputAudio = [
            "format": [
                "type": "audio/pcm",
                "rate": 24_000,
            ] as [String: Any],
            "transcription": inputTranscriptionPayload(credentials: credentials),
            "turn_detection": turnDetectionPayload(),
        ] as [String: Any]

        if let noiseReductionPayload = noiseReductionPayload(enabled: reduceNoise) {
            inputAudio["noise_reduction"] = noiseReductionPayload
        }

        return [
            "type": "realtime",
            "model": credentials.modelID,
            "instructions": credentials.instructions,
            "output_modalities": ["audio"],
            "audio": [
                "input": inputAudio,
                "output": [
                    "format": [
                        "type": "audio/pcm",
                        "rate": 24_000,
                    ],
                    "voice": "marin",
                    "speed": 1.0,
                ],
            ],
        ]
    }

    private func inputTranscriptionPayload(
        credentials: OpenAIRealtimeSessionCredentials
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "model": credentials.transcriptionModelID,
        ]

        if let languageCode = localeLanguageCode() {
            payload["language"] = languageCode
        }

        return payload
    }

    private func turnDetectionPayload() -> Any {
        NSNull()
    }

    private func noiseReductionPayload(enabled: Bool) -> [String: Any]? {
        guard enabled, source != .system else {
            return nil
        }

        return ["type": "near_field"]
    }

    private func waitForReadyState() async throws {
        let timeoutDeadline = Date().addingTimeInterval(10)

        while true {
            let state = lock.withLock { () -> (isReady: Bool, error: Error?) in
                (isReady, connectionError)
            }

            if state.isReady {
                return
            }

            if let error = state.error {
                throw error
            }

            if Date() >= timeoutDeadline {
                let timeoutError = OpenAIRealtimeConversationError.connectionTimedOut
                failReadyStateIfNeeded(with: timeoutError)
                throw timeoutError
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func receiveLoop() async {
        guard let socketTask else {
            failReadyStateIfNeeded(with: OpenAIRealtimeConversationError.notConnected)
            return
        }

        while !Task.isCancelled {
            do {
                let message = try await socketTask.receive()
                switch message {
                case let .string(text):
                    handleServerMessage(text)
                case let .data(data):
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw OpenAIRealtimeConversationError.invalidEvent
                    }
                    handleServerMessage(text)
                @unknown default:
                    throw OpenAIRealtimeConversationError.invalidEvent
                }
            } catch {
                failReadyStateIfNeeded(with: error)

                guard !Task.isCancelled else { return }
                onError(error)
                return
            }
        }
    }

    private func handleServerMessage(_ text: String) {
        guard let payload = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let eventType = payload["type"] as? String else {
            onError(OpenAIRealtimeConversationError.invalidEvent)
            return
        }

        switch eventType {
        case "session.created":
            handleSessionLifecycle(payload)

        case "session.updated":
            handleSessionLifecycle(payload)
            markReadyIfNeeded()

        case "error":
            handleServerError(payload)

        case "input_audio_buffer.speech_started":
            handleSpeechStarted()

        case "input_audio_buffer.committed":
            handleCommittedInputAudio(payload)

        case "response.created":
            handleResponseCreated(payload)

        case "response.output_item.added", "response.output_item.created":
            handleResponseOutputItem(payload)

        case "conversation.item.input_audio_transcription.delta":
            handleInputAudioTranscription(payload, isFinal: false)

        case "conversation.item.input_audio_transcription.completed":
            handleInputAudioTranscription(payload, isFinal: true)

        case "response.output_text.delta":
            handleAssistantTextDelta(payload, prefersOutputText: true)

        case "response.output_audio_transcript.delta":
            handleAssistantTextDelta(payload, prefersOutputText: false)

        case "response.output_audio.delta":
            handleAssistantAudioDelta(payload)

        case "response.done":
            handleResponseDone(payload)

        case "response.cancelled":
            handleResponseCancelled(payload)

        default:
            break
        }
    }

    private func handleServerError(_ payload: [String: Any]) {
        let message = nestedString(payload, path: ["error", "message"])
            ?? nestedString(payload, path: ["message"])
            ?? "OpenAI Realtime request failed."
        let eventID = nestedString(payload, path: ["error", "event_id"])
            ?? nestedString(payload, path: ["event_id"])

        if handleActiveResponseRejectedError(message: message, eventID: eventID) {
            return
        }

        let error = OpenAIRealtimeConversationError.sessionFailed(message)
        failReadyStateIfNeeded(with: error)
        onError(error)
    }

    private func handleActiveResponseRejectedError(message: String, eventID: String?) -> Bool {
        guard message.localizedCaseInsensitiveContains("active response in progress") else {
            return false
        }

        let rejectedItemID = lock.withLock { () -> String? in
            guard let eventID,
                  let itemID = userItemIDByResponseCreateEventID.removeValue(forKey: eventID) else {
                return nil
            }

            responseRequestedItemIDs.remove(itemID)

            guard let draft = turnsByItemID[itemID],
                  !draft.isCompleted,
                  draft.assistantResponseID == nil else {
                return itemID
            }

            if !pendingResponseTurnItemIDs.contains(itemID) {
                pendingResponseTurnItemIDs.insert(itemID, at: 0)
            }

            return itemID
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .warning,
                title: "Response create rejected",
                detail: message,
                itemID: rejectedItemID,
                loopHint: "The server still had an active response when HUSH tried response.create. The turn is held and retried after the active response closes.",
                isHighlighted: true
            )
        )

        scheduleResponseRetry(after: "server active-response rejection")
        return true
    }

    private func handleSpeechStarted() {
        let barrierState = audioPlayer.microphoneBarrierState(
            gracePeriod: PlaybackGuards.microphoneSuppressionGracePeriod
        )
        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .speech,
                title: "Speech detected",
                detail: "Server VAD fired while barrier was \(barrierState.debugLabel).",
                speechLabel: "Server VAD \(barrierState.debugLabel)"
            )
        )

        guard interruptWhenSpeak,
              !audioPlayer.suppressesMicrophoneInput(
                gracePeriod: PlaybackGuards.microphoneSuppressionGracePeriod
              ),
              let truncation = audioPlayer.interruptCurrentPlayback() else {
            return
        }

        onAssistantTextUpdate("")

        enqueueEvent(
            [
                "type": "conversation.item.truncate",
                "item_id": truncation.itemID,
                "content_index": 0,
                "audio_end_ms": truncation.audioEndMilliseconds,
            ]
        )

        lock.withLock {
            for itemID in turnsByItemID.keys {
                guard var draft = turnsByItemID[itemID],
                      draft.assistantItemID == truncation.itemID else {
                    continue
                }

                draft.wasInterrupted = true
                draft.wasTruncated = true
                turnsByItemID[itemID] = draft
            }
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .response,
                title: "Response truncated",
                detail: "Server VAD truncated playback at \(truncation.audioEndMilliseconds) ms.",
                responseState: .cancelled,
                isHighlighted: true
            )
        )
    }

    private func handleCommittedInputAudio(_ payload: [String: Any]) {
        guard let itemID = nestedString(payload, path: ["item_id"]), !itemID.isEmpty else {
            return
        }

        onAssistantTextUpdate("")

        let commitState = lock.withLock {
            () -> (
                shouldRequestResponse: Bool,
                duplicateRequest: Bool,
                duplicatePending: Bool,
                deferredBecauseResponseActive: Bool
            ) in
            if turnsByItemID[itemID] == nil {
                turnsByItemID[itemID] = RealtimeDraftTurn(userItemID: itemID, startedAt: Date())
            }
            responseOutputModalitiesByItemID[itemID] = ["audio"]

            let duplicatePending = pendingResponseTurnItemIDs.contains(itemID)
            let duplicateRequest =
                responseRequestedItemIDs.contains(itemID)
                || userItemIDByResponseID.values.contains(itemID)

            if !duplicatePending && !duplicateRequest {
                pendingResponseTurnItemIDs.append(itemID)
            }
            activeTurnItemID = itemID

            let responseAlreadyActive =
                userItemIDByResponseID.isEmpty == false
                || responseRequestedItemIDs.isEmpty == false

            let shouldRequestResponse =
                !duplicateRequest
                && pendingResponseTurnItemIDs.first == itemID
                && !responseAlreadyActive

            if shouldRequestResponse {
                responseRequestedItemIDs.insert(itemID)
            }

            return (
                shouldRequestResponse,
                duplicateRequest,
                duplicatePending,
                !duplicateRequest && !duplicatePending && !shouldRequestResponse
            )
        }

        if commitState.duplicatePending || commitState.duplicateRequest {
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .warning,
                    title: "Duplicate input commit",
                    detail: "input_audio_buffer.committed repeated before the prior response finished.",
                    itemID: itemID,
                    loopHint: "The same input turn is being committed more than once before completion. That can feed a repeating response.create loop.",
                    isHighlighted: true
                )
            )
        }

        if commitState.deferredBecauseResponseActive {
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .response,
                    title: "Response deferred",
                    detail: "Committed audio queued until the current response closes.",
                    itemID: itemID,
                    loopHint: "A second turn committed while another response was still active. HUSH is now queueing it instead of issuing a second response.create immediately.",
                    isHighlighted: true
                )
            )
        }

        guard commitState.shouldRequestResponse else { return }
        requestResponse(for: itemID, detail: "Queued response.create after committed input audio.")
    }

    private func handleInputAudioTranscription(_ payload: [String: Any], isFinal: Bool) {
        guard let itemID = nestedString(payload, path: ["item_id"]),
              let transcript = nestedString(payload, path: ["transcript"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            return
        }

        onTextUpdate(transcript)

        guard isFinal else { return }

        lock.withLock {
            var draft = turnsByItemID[itemID] ?? RealtimeDraftTurn(userItemID: itemID, startedAt: Date())
            draft.prompt = transcript
            turnsByItemID[itemID] = draft
            activeTurnItemID = itemID
        }
    }

    private func handleResponseCreated(_ payload: [String: Any]) {
        guard let responseID = nestedString(payload, path: ["response", "id"]) ??
                nestedString(payload, path: ["id"]) else {
            return
        }

        let createdState = lock.withLock { () -> (itemID: String, replacedItemID: String?, previousResponseID: String?)? in
            let itemID: String
            if let mappedItemID = userItemIDByResponseID[responseID] {
                itemID = mappedItemID
            } else if pendingResponseTurnItemIDs.isEmpty == false {
                itemID = pendingResponseTurnItemIDs.removeFirst()
                userItemIDByResponseID[responseID] = itemID
            } else if let activeTurnItemID {
                itemID = activeTurnItemID
                userItemIDByResponseID[responseID] = itemID
            } else {
                return nil
            }

            let replacedItemID = turnsByItemID.first { candidateItemID, draft in
                candidateItemID != itemID
                    && !draft.isCompleted
                    && draft.assistantResponseID != nil
            }?.key

            var draft = turnsByItemID[itemID] ?? RealtimeDraftTurn(userItemID: itemID, startedAt: Date())
            let previousResponseID = draft.assistantResponseID
            draft.assistantResponseID = responseID
            turnsByItemID[itemID] = draft
            userItemIDByResponseCreateEventID = userItemIDByResponseCreateEventID.filter { _, mappedItemID in
                mappedItemID != itemID
            }
            visibleAssistantTurnItemID = itemID
            return (itemID, replacedItemID, previousResponseID)
        }

        guard let createdState else { return }

        if let replacedItemID = createdState.replacedItemID {
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .response,
                    title: "Response replaced",
                    detail: "New response.created arrived before turn \(shortDebugIdentifier(replacedItemID)) finished.",
                    itemID: createdState.itemID,
                    responseID: responseID,
                    responseState: .replaced,
                    loopHint: "A new response.created replaced an in-flight turn before the previous one completed. If this repeats, it explains the short response loop.",
                    isHighlighted: true
                )
            )
        } else if let previousResponseID = createdState.previousResponseID,
                  previousResponseID != responseID {
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .response,
                    title: "Response replaced",
                    detail: "Turn \(shortDebugIdentifier(createdState.itemID)) received a second response.created.",
                    itemID: createdState.itemID,
                    responseID: responseID,
                    responseState: .replaced,
                    loopHint: "The same turn received multiple response.created events before completion. That is a strong signal for a response-loop race.",
                    isHighlighted: true
                )
            )
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .response,
                title: "Response created",
                detail: "Server acknowledged a new assistant response.",
                itemID: createdState.itemID,
                responseID: responseID,
                responseState: .active
            )
        )
    }

    private func handleResponseOutputItem(_ payload: [String: Any]) {
        let responseID = nestedString(payload, path: ["response_id"])
            ?? nestedString(payload, path: ["response", "id"])

        let itemID = lock.withLock { () -> String? in
            if let responseID, let mappedItemID = userItemIDByResponseID[responseID] {
                return mappedItemID
            }

            return activeTurnItemID
        }

        guard let itemID else {
            return
        }

        let outputItemID = nestedString(payload, path: ["item", "id"])
            ?? nestedString(payload, path: ["output_item", "id"])
            ?? nestedString(payload, path: ["id"])

        guard let outputItemID, !outputItemID.isEmpty else { return }

        lock.withLock {
            guard var draft = turnsByItemID[itemID] else { return }
            draft.assistantItemID = outputItemID
            turnsByItemID[itemID] = draft
            userItemIDByAssistantItemID[outputItemID] = itemID
            visibleAssistantTurnItemID = itemID
        }
    }

    private func handleAssistantTextDelta(_ payload: [String: Any], prefersOutputText: Bool) {
        guard let delta = nestedString(payload, path: ["delta"]), !delta.isEmpty else {
            return
        }

        let assistantText = lock.withLock { () -> String? in
            guard let itemID = resolvedUserItemID(for: payload) else {
                return nil
            }
            guard var draft = turnsByItemID[itemID], !draft.isCompleted else { return nil }

            if prefersOutputText {
                draft.assistantText += delta
            } else {
                draft.assistantAudioTranscript += delta
            }

            turnsByItemID[itemID] = draft
            guard visibleAssistantTurnItemID == itemID else {
                return nil
            }

            return draft.effectiveAssistantResponse
        }

        if let assistantText, !assistantText.isEmpty {
            onAssistantTextUpdate(assistantText)
        }
    }

    private func handleAssistantAudioDelta(_ payload: [String: Any]) {
        guard let base64Chunk = nestedString(payload, path: ["delta"]),
              !base64Chunk.isEmpty else {
            return
        }

        let itemID = nestedString(payload, path: ["item_id"]) ?? "assistant"

        do {
            try audioPlayer.enqueue(base64AudioChunk: base64Chunk, itemID: itemID)
        } catch {
            onError(error)
        }
    }

    private func handleResponseDone(_ payload: [String: Any]) {
        finishResponse(payload, wasCancelled: false)
    }

    private func handleResponseCancelled(_ payload: [String: Any]) {
        finishResponse(payload, wasCancelled: true)
    }

    private func handleSessionLifecycle(_ payload: [String: Any]) {
        let eventType = nestedString(payload, path: ["type"]) ?? "session"
        let sessionID = nestedString(payload, path: ["session", "id"])
            ?? nestedString(payload, path: ["id"])

        guard let sessionID, !sessionID.isEmpty else { return }

        lock.withLock {
            realtimeSessionID = sessionID
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .pipeline,
                title: eventType == "session.updated" ? "Realtime session ready" : "Realtime session created",
                detail: eventType == "session.updated"
                    ? "Session \(shortDebugIdentifier(sessionID)) acknowledged manual turn and response control."
                    : "Session \(shortDebugIdentifier(sessionID)) opened; waiting for configuration ack."
            )
        )
    }

    private func seedConversationIfNeeded() {
        guard !seedItems.isEmpty else { return }

        for seedItem in seedItems {
            guard let itemPayload = makeRealtimeConversationItemPayload(from: seedItem) else {
                continue
            }

            enqueueEvent(
                [
                    "type": "conversation.item.create",
                    "item": itemPayload,
                ]
            )
        }
    }

    private func makeRealtimeConversationItemPayload(
        from seedItem: OpenAIConversationSeedItem
    ) -> [String: Any]? {
        let content = seedItem.contents.compactMap(makeRealtimeContentPayload(from:))
        guard !content.isEmpty else { return nil }

        let item: [String: Any] = [
            "type": "message",
            "role": seedItem.role.rawValue,
            "content": content,
        ]

        return item
    }

    private func makeRealtimeContentPayload(
        from content: OpenAIConversationSeedContent
    ) -> [String: Any]? {
        switch content {
        case let .inputText(text):
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            return [
                "type": "input_text",
                "text": normalized,
            ]

        case let .outputText(text):
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            return [
                "type": "output_text",
                "text": normalized,
            ]

        case let .imageAsset(asset):
            guard let imageURL = dataURL(for: asset) else {
                return nil
            }
            return [
                "type": "input_image",
                "image_url": imageURL,
            ]

        case let .fileAsset(asset):
            let fallbackText = asset.extractedTextDigest
                ?? asset.degradedSummary
                ?? "Attached file: \(asset.title)"
            return [
                "type": "input_text",
                "text": fallbackText,
            ]
        }
    }

    private func dataURL(for asset: AttachmentAssetRecord) -> String? {
        if let fileURL = asset.resolvedLocalURL,
           isImageURL(fileURL),
           let data = try? Data(contentsOf: fileURL) {
            return "data:\(mimeType(for: fileURL));base64,\(data.base64EncodedString())"
        }

        guard let previewPNGData = asset.previewPNGData else {
            return nil
        }

        return "data:image/png;base64,\(previewPNGData.base64EncodedString())"
    }

    private func isImageURL(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        case "bmp":
            return "image/bmp"
        case "tif", "tiff":
            return "image/tiff"
        default:
            return "image/png"
        }
    }

    private func handleInputAudioChunk(_ audioData: Data) {
        guard !audioData.isEmpty else { return }

        let rms = normalizedRMS(forAudioData: audioData)
        let now = Date()

        if manualTurnStartedAt == nil {
            if rms >= ManualTurnDetection.speechStartRMS {
                manualTurnSpeechFrameCount += 1
            } else {
                manualTurnSpeechFrameCount = max(0, manualTurnSpeechFrameCount - 1)
                return
            }

            guard manualTurnSpeechFrameCount >= ManualTurnDetection.requiredSpeechFrames else {
                return
            }

            startManualInputAudioTurn(startedAt: now)
        }

        enqueueInputAudioChunk(audioData)
        manualTurnHasAppendedAudio = true
        manualTurnAudioDuration += audioDuration(forAudioData: audioData)

        if rms >= ManualTurnDetection.speechContinueRMS {
            manualTurnLastSpeechAt = now
        }

        let silenceDuration = now.timeIntervalSince(manualTurnLastSpeechAt ?? now)
        let turnDuration = now.timeIntervalSince(manualTurnStartedAt ?? now)
        guard manualTurnAudioDuration >= ManualTurnDetection.minimumTurnDuration else { return }

        if silenceDuration >= ManualTurnDetection.silenceDuration {
            commitManualInputAudioTurnIfNeeded(reason: "local silence")
        } else if turnDuration >= ManualTurnDetection.maximumTurnDuration {
            commitManualInputAudioTurnIfNeeded(reason: "local max duration")
        }
    }

    private func startManualInputAudioTurn(startedAt: Date) {
        enqueueEvent(["type": "input_audio_buffer.clear"])
        manualTurnStartedAt = startedAt
        manualTurnLastSpeechAt = startedAt
        manualTurnAudioDuration = 0
        manualTurnHasAppendedAudio = false

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .speech,
                title: "Speech detected",
                detail: "Local turn detector started a manual Realtime audio turn.",
                speechLabel: "Local turn active",
                clearsLoopHint: true
            )
        )
    }

    private func commitManualInputAudioTurnIfNeeded(reason: String) {
        guard manualTurnStartedAt != nil else { return }
        let shouldCommit = manualTurnHasAppendedAudio
        resetManualInputAudioTurn()
        guard shouldCommit else { return }

        enqueueEvent(["type": "input_audio_buffer.commit"])
        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .response,
                title: "Audio turn committed",
                detail: "Committed manual input audio after \(reason)."
            )
        )
    }

    private func resetManualInputAudioTurn() {
        manualTurnStartedAt = nil
        manualTurnLastSpeechAt = nil
        manualTurnSpeechFrameCount = 0
        manualTurnAudioDuration = 0
        manualTurnHasAppendedAudio = false
    }

    private func normalizedRMS(forAudioData audioData: Data) -> Float {
        let sampleCount = audioData.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return 0 }

        return audioData.withUnsafeBytes { rawBuffer in
            var sumSquares: Double = 0
            for sampleIndex in 0..<sampleCount {
                let byteOffset = sampleIndex * 2
                let lowByte = UInt16(rawBuffer[byteOffset])
                let highByte = UInt16(rawBuffer[byteOffset + 1]) << 8
                let sample = Int16(bitPattern: highByte | lowByte)
                let normalized = Double(sample) / Double(Int16.max)
                sumSquares += normalized * normalized
            }
            return Float(sqrt(sumSquares / Double(sampleCount)))
        }
    }

    private func audioDuration(forAudioData audioData: Data) -> TimeInterval {
        let sampleCount = audioData.count / MemoryLayout<Int16>.size
        return TimeInterval(Double(sampleCount) / ManualTurnDetection.sampleRate)
    }

    private func enqueueInputAudioChunk(_ audioData: Data) {
        enqueueEvent(
            [
                "type": "input_audio_buffer.append",
                "audio": audioData.base64EncodedString(),
            ]
        )
    }

    private func enqueueEvent(_ payload: [String: Any]) {
        let serializedData: Data

        do {
            serializedData = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            onError(error)
            return
        }

        let message = String(decoding: serializedData, as: UTF8.self)
        let previousTask = lock.withLock { sendChain }
        let sendTask = Task { [weak self] in
            _ = await previousTask?.value
            guard let self, !Task.isCancelled else { return }

            do {
                guard let socketTask else {
                    throw OpenAIRealtimeConversationError.notConnected
                }
                try await socketTask.send(.string(message))
            } catch {
                failReadyStateIfNeeded(with: error)
                onError(error)
            }
        }

        lock.withLock {
            sendChain = sendTask
        }
    }

    private func markReadyIfNeeded() {
        lock.withLock {
            guard !isReady else { return }
            isReady = true
            connectionError = nil
        }
    }

    private func failReadyStateIfNeeded(with error: Error) {
        lock.withLock {
            guard !isReady, connectionError == nil else { return }
            connectionError = error
        }
    }

    private func nestedString(_ dictionary: [String: Any], path: [String]) -> String? {
        var currentValue: Any? = dictionary

        for key in path {
            if let nestedDictionary = currentValue as? [String: Any] {
                currentValue = nestedDictionary[key]
            } else {
                currentValue = nil
                break
            }
        }

        return currentValue as? String
    }

    private func resolvedUserItemID(for payload: [String: Any]) -> String? {
        if let assistantItemID = nestedString(payload, path: ["item_id"]),
           let itemID = userItemIDByAssistantItemID[assistantItemID] {
            return itemID
        }

        let responseID = nestedString(payload, path: ["response_id"])
            ?? nestedString(payload, path: ["response", "id"])
            ?? nestedString(payload, path: ["id"])
        if let responseID, let itemID = userItemIDByResponseID[responseID] {
            return itemID
        }

        return activeTurnItemID
    }

    private func finishResponse(_ payload: [String: Any], wasCancelled: Bool) {
        let completedState: (itemID: String, responseID: String?, turn: LiveCompletedTurn?, shouldUpdateVisible: Bool)? = lock.withLock {
            guard let itemID = resolvedUserItemID(for: payload),
                  var draft = turnsByItemID[itemID],
                  !draft.isCompleted else {
                return nil
            }

            if wasCancelled {
                draft.wasInterrupted = true
                draft.wasTruncated = draft.wasTruncated || draft.assistantItemID != nil
            }

            let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = draft.effectiveAssistantResponse
            let shouldUpdateVisible = visibleAssistantTurnItemID == nil || visibleAssistantTurnItemID == itemID

            draft.isCompleted = true
            turnsByItemID[itemID] = draft
            if activeTurnItemID == itemID {
                activeTurnItemID = nil
            }
            if visibleAssistantTurnItemID == itemID {
                visibleAssistantTurnItemID = nil
            }
            if let responseID = draft.assistantResponseID {
                userItemIDByResponseID.removeValue(forKey: responseID)
            }
            if let assistantItemID = draft.assistantItemID {
                userItemIDByAssistantItemID.removeValue(forKey: assistantItemID)
            }
            userItemIDByResponseCreateEventID = userItemIDByResponseCreateEventID.filter { _, mappedItemID in
                mappedItemID != itemID
            }
            responseOutputModalitiesByItemID.removeValue(forKey: itemID)
            responseRequestedItemIDs.remove(itemID)

            let completedTurn: LiveCompletedTurn?
            guard !prompt.isEmpty, !response.isEmpty else {
                completedTurn = nil
                return (itemID, draft.assistantResponseID, completedTurn, false)
            }

            completedTurn = LiveCompletedTurn(
                prompt: prompt,
                response: response,
                startedAt: draft.startedAt,
                finishedAt: Date(),
                realtimeSessionID: realtimeSessionID,
                userItemID: draft.userItemID,
                assistantItemID: draft.assistantItemID,
                assistantResponseID: draft.assistantResponseID,
                wasInterrupted: draft.wasInterrupted,
                wasTruncated: draft.wasTruncated
            )

            return (itemID, draft.assistantResponseID, completedTurn, shouldUpdateVisible)
        }

        guard let completedState else { return }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .response,
                title: wasCancelled ? "Response cancelled" : "Response completed",
                detail: wasCancelled ? "Received response.cancelled from the server." : "Received response.done from the server.",
                itemID: completedState.itemID,
                responseID: completedState.responseID,
                responseState: wasCancelled ? .cancelled : .completed,
                isHighlighted: wasCancelled
            )
        )

        requestNextQueuedResponseIfPossible(
            after: wasCancelled ? "response cancellation" : "response completion"
        )

        guard let completedTurn = completedState.turn else { return }
        if completedState.shouldUpdateVisible {
            onAssistantTextUpdate(completedTurn.response)
        }
        onCompletedTurn(completedTurn)
    }

    private func systemAudioSuppressionBarrierState() -> RealtimeMicrophoneBarrierState? {
        let barrierState = audioPlayer.microphoneBarrierState(
            gracePeriod: PlaybackGuards.microphoneSuppressionGracePeriod
        )
        guard barrierState != .idle else { return nil }
        return barrierState
    }

    private func recordSystemAudioSuppressionIfNeeded(_ barrierState: RealtimeMicrophoneBarrierState) {
        let shouldRecord = lock.withLock { () -> Bool in
            let now = Date()
            guard now.timeIntervalSince(lastSystemAudioSuppressionDebugAt) >= 2 else {
                return false
            }

            lastSystemAudioSuppressionDebugAt = now
            return true
        }

        guard shouldRecord else { return }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .capture,
                title: "System audio suppressed",
                detail: "Dropped system capture while assistant playback barrier was \(barrierState.debugLabel).",
                loopHint: "Assistant output was present in system capture. Suppressing it prevents the model from hearing itself and starting a 1-4 second response loop.",
                isHighlighted: true
            )
        )
    }

    private func recordMicrophoneSuppressionIfNeeded(_ barrierState: RealtimeMicrophoneBarrierState) {
        let shouldRecord = lock.withLock { () -> Bool in
            let now = Date()
            guard now.timeIntervalSince(lastMicrophoneSuppressionDebugAt) >= 2 else {
                return false
            }

            lastMicrophoneSuppressionDebugAt = now
            return true
        }

        guard shouldRecord else { return }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .capture,
                title: "Mic audio suppressed",
                detail: "Dropped mic capture while assistant playback barrier was \(barrierState.debugLabel).",
                loopHint: "Mic capture is gated while assistant audio is playing or cooling down, preventing speaker bleed from becoming a fresh response loop."
            )
        )
    }

    private func shouldTreatSuppressedMicrophoneAudioAsUserSpeech(
        _ samples: [Int16],
        state: RealtimeMicrophoneBarrierState
    ) -> Bool {
        let rms = normalizedRMS(for: samples)
        guard rms > 0 else { return false }

        if suppressedMicrophoneCalibrationFrames < LocalSpeechDetection.minimumCalibrationFrames {
            updateSuppressedMicrophoneBaseline(with: rms)
            suppressedMicrophoneCalibrationFrames += 1
            suppressedMicrophoneTriggerCount = 0
            return false
        }

        let relativeMultiplier: Float
        switch state {
        case .playback:
            relativeMultiplier = LocalSpeechDetection.playbackRelativeMultiplier
        case .cooldown:
            relativeMultiplier = LocalSpeechDetection.cooldownRelativeMultiplier
        case .idle:
            relativeMultiplier = 1
        }

        let dynamicThreshold = max(
            LocalSpeechDetection.minimumRMS,
            suppressedMicrophoneBaseline * relativeMultiplier
        )

        updateSuppressedMicrophoneBaseline(with: rms)

        if rms >= dynamicThreshold {
            suppressedMicrophoneTriggerCount += 1
        } else if rms < dynamicThreshold * 0.7 {
            suppressedMicrophoneTriggerCount = 0
        }

        return suppressedMicrophoneTriggerCount >= LocalSpeechDetection.requiredConsecutiveFrames
    }

    private func updateSuppressedMicrophoneBaseline(with rms: Float) {
        guard rms > 0 else { return }

        if suppressedMicrophoneBaseline == 0 {
            suppressedMicrophoneBaseline = rms
            return
        }

        let cappedRMS = min(rms, suppressedMicrophoneBaseline * LocalSpeechDetection.baselineRiseCap)
        suppressedMicrophoneBaseline =
            (suppressedMicrophoneBaseline * (1 - LocalSpeechDetection.baselineSmoothing))
            + (cappedRMS * LocalSpeechDetection.baselineSmoothing)
    }

    private func resetLocalSpeechDetector() {
        suppressedMicrophoneBaseline = 0
        suppressedMicrophoneCalibrationFrames = 0
        suppressedMicrophoneTriggerCount = 0
    }

    private func normalizedRMS(for samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var sumSquares: Double = 0
        for sample in samples {
            let normalized = Double(sample) / Double(Int16.max)
            sumSquares += normalized * normalized
        }

        return Float(sqrt(sumSquares / Double(samples.count)))
    }

    private func interruptAssistantPlaybackForLocalSpeech() {
        guard let truncation = audioPlayer.interruptCurrentPlayback() else { return }

        let interruptionState = lock.withLock { () -> (responseID: String?, itemID: String?) in
            var responseID: String?
            var itemID: String?

            for candidateItemID in turnsByItemID.keys {
                guard var draft = turnsByItemID[candidateItemID],
                      draft.assistantItemID == truncation.itemID else {
                    continue
                }

                if !draft.isCompleted {
                    responseID = draft.assistantResponseID
                    itemID = candidateItemID
                }
                draft.wasInterrupted = true
                draft.wasTruncated = true
                turnsByItemID[candidateItemID] = draft
            }

            return (responseID, itemID)
        }

        if interruptionState.responseID != nil {
            recordDebugTransition(
                LiveVoiceDebugTransition(
                    category: .response,
                    title: "Response cancel sent",
                    detail: "Local speech interrupted playback at \(truncation.audioEndMilliseconds) ms.",
                    itemID: interruptionState.itemID,
                    responseID: interruptionState.responseID,
                    isHighlighted: true
                )
            )
            enqueueEvent(["type": "response.cancel"])
        }

        onAssistantTextUpdate("")
        enqueueEvent(
            [
                "type": "conversation.item.truncate",
                "item_id": truncation.itemID,
                "content_index": 0,
                "audio_end_ms": truncation.audioEndMilliseconds,
            ]
        )
    }

    private func requestNextQueuedResponseIfPossible(after reason: String) {
        let nextItemID = lock.withLock { () -> String? in
            guard responseRequestedItemIDs.isEmpty,
                  userItemIDByResponseID.isEmpty else {
                return nil
            }

            while let candidateItemID = pendingResponseTurnItemIDs.first {
                if turnsByItemID[candidateItemID]?.isCompleted == true {
                    pendingResponseTurnItemIDs.removeFirst()
                    continue
                }

                guard !responseRequestedItemIDs.contains(candidateItemID) else {
                    pendingResponseTurnItemIDs.removeFirst()
                    continue
                }

                responseRequestedItemIDs.insert(candidateItemID)
                activeTurnItemID = candidateItemID
                return candidateItemID
            }

            return nil
        }

        guard let nextItemID else { return }
        requestResponse(
            for: nextItemID,
            detail: "Queued response.create after \(reason)."
        )
    }

    private func scheduleResponseRetry(after reason: String) {
        responseRetryTask?.cancel()
        responseRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 900_000_000)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }
            self.requestNextQueuedResponseIfPossible(after: reason)
        }
    }

    private func requestResponse(for itemID: String, detail: String) {
        let eventID = "hush_response_create_\(UUID().uuidString)"
        let outputModalities = lock.withLock {
            responseOutputModalitiesByItemID[itemID] ?? ["audio"]
        }
        lock.withLock {
            userItemIDByResponseCreateEventID[eventID] = itemID
        }

        recordDebugTransition(
            LiveVoiceDebugTransition(
                category: .response,
                title: "Response requested",
                detail: detail,
                itemID: itemID,
                responseState: .requested
            )
        )
        enqueueEvent(
            [
                "event_id": eventID,
                "type": "response.create",
                "response": [
                    "output_modalities": outputModalities,
                ],
            ]
        )
    }

    private func recordDebugTransition(_ transition: LiveVoiceDebugTransition) {
        onDebugTransition(transition)
    }

    private func shortDebugIdentifier(_ identifier: String?) -> String {
        guard let identifier else { return "unknown" }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        return trimmed.count > 8 ? String(trimmed.suffix(8)) : trimmed
    }

    private func localeLanguageCode() -> String? {
        if #available(macOS 13.0, *) {
            return locale.language.languageCode?.identifier
        }

        let legacyIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        return legacyIdentifier
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }
}
