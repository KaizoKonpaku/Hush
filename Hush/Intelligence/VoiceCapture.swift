import AVFoundation
import Foundation
import Observation
import Speech

enum SpeechInputMode: Sendable { case dictation, conversation }

@MainActor
protocol SpeechInputServing: AnyObject {
    var transcript: String { get }
    var playback: VoicePlayback? { get }
    func start(mode: SpeechInputMode, onReady: @escaping @MainActor () -> Void,
               onUpdate: @escaping @MainActor (String) -> Void,
               onLevel: @escaping @MainActor (VoiceLevel) -> Void,
               onError: @escaping @MainActor (Error) -> Void)
    func finalizeTranscript() async throws -> String
    func discardTranscript()
    func setMuted(_ muted: Bool)
    func cancel()
}

@MainActor @Observable
final class VoiceCapture: SpeechInputServing {
    enum Phase { case idle, preparing, recording, transcribing }
    private(set) var phase: Phase = .idle
    private(set) var mode: SpeechInputMode = .dictation
    private(set) var transcript = ""
    private(set) var level = 0.0
    var isActive: Bool { phase != .idle }
    var isDictating: Bool { isActive && mode == .dictation }
    var status: String {
        switch phase {
        case .idle: "Dictate on device"
        case .preparing: "Preparing on-device speech"
        case .recording: "Listening live on this device"
        case .transcribing: "Finishing transcription"
        }
    }

    @ObservationIgnored private(set) var playback: VoicePlayback?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var bridge: SpeechAudioBridge?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var setupTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var resultTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var accumulator = SpeechTranscript()
    @ObservationIgnored private var update: (@MainActor (String) -> Void)?
    @ObservationIgnored private var reportError: (@MainActor (Error) -> Void)?
    @ObservationIgnored private var tapInstalled = false

    func start(mode: SpeechInputMode, onReady: @escaping @MainActor () -> Void,
               onUpdate: @escaping @MainActor (String) -> Void,
               onLevel: @escaping @MainActor (VoiceLevel) -> Void,
               onError: @escaping @MainActor (Error) -> Void) {
        guard !isActive else { return }
        let id = UUID()
        operationID = id
        self.mode = mode
        phase = .preparing
        accumulator = SpeechTranscript()
        transcript = ""
        update = onUpdate
        reportError = onError
        setupTask = Task { [self] in
            do {
                await cleanupTask?.value
                try Task.checkCancellation()
                guard SpeechTranscriber.isAvailable,
                      let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                    throw HushError.message("On-device speech is unavailable for this device or language.")
                }
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw HushError.message("Allow microphone access in Settings to use voice. You can still type.")
                }
                try Task.checkCancellation()
                let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                let modules: [any SpeechModule] = [transcriber, SpeechDetector()]
                if let installation = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                    try await installation.downloadAndInstall()
                }
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
                    throw HushError.message("No compatible microphone format is available.")
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                #if !os(macOS)
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat,
                    options: [.defaultToSpeaker, .allowBluetoothHFP])
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let engine = AVAudioEngine()
                self.engine = engine
                try engine.inputNode.setVoiceProcessingEnabled(true)
                self.playback = try VoicePlayback(engine: engine)
                let naturalFormat = engine.inputNode.outputFormat(forBus: 0)
                guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0 else {
                    throw HushError.message("Connect a microphone and try again.")
                }
                let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(32))
                let bridge = try SpeechAudioBridge(format: format, continuation: continuation) { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.operationID == id else { return }
                        self.level = value.amplitude
                        onLevel(value)
                    }
                }
                self.bridge = bridge
                let analyzer = SpeechAnalyzer(modules: modules)
                self.analyzer = analyzer
                try await analyzer.prepareToAnalyze(in: format)
                try Task.checkCancellation()
                guard operationID == id else { return }
                resultTask = Task { [weak self] in
                    do {
                        for try await result in transcriber.results {
                            guard let self, self.operationID == id else { return }
                            self.accumulator.update(.init(start: result.range.start.seconds, end: result.range.end.seconds,
                                text: String(result.text.characters), isFinal: result.isFinal))
                            let text = self.accumulator.text
                            guard text.count <= 8_000 else { throw HushError.message("This voice turn is too long. Finish it and start another.") }
                            self.transcript = text
                            self.update?(text)
                        }
                    } catch { self?.fail(error, id: id) }
                }
                analysisTask = Task { [weak self] in
                    do { try await analyzer.start(inputSequence: stream) }
                    catch { self?.fail(error, id: id) }
                }
                try engine.inputNode.installAudioTap(onBus: 0, bufferSize: AVAudioFrameCount(naturalFormat.sampleRate * 0.1), format: naturalFormat) { buffer, _ in bridge.append(buffer) }
                tapInstalled = true
                engine.prepare()
                try engine.start()
                phase = .recording
                installObservers(engine: engine, id: id)
                onReady()
                if mode == .dictation {
                    timeoutTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(300)); self?.finish() }
                        catch { }
                    }
                }
            } catch { fail(error, id: id) }
        }
    }

    func finalizeTranscript() async throws -> String {
        guard let analyzer else { return transcript }
        try await analyzer.finalize(through: nil)
        await Task.yield()
        return transcript
    }

    func discardTranscript() {
        accumulator.discard()
        transcript = ""
    }

    func setMuted(_ muted: Bool) {
        engine?.inputNode.isVoiceProcessingInputMuted = muted
        bridge?.setMuted(muted)
        accumulator.discard(through: bridge?.audioTime)
        transcript = ""
    }

    func finish(completion: (@MainActor () -> Void)? = nil) {
        guard phase == .recording, mode == .dictation, let analyzer, let id = operationID else { return }
        phase = .transcribing
        stopAudio()
        setupTask = Task {
            do {
                await analysisTask?.value
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                await resultTask?.value
                guard operationID == id else { return }
                cancel()
                completion?()
            } catch { fail(error, id: id) }
        }
    }

    func cancel() {
        operationID = nil
        setupTask?.cancel()
        timeoutTask?.cancel()
        stopAudio()
        analysisTask?.cancel()
        resultTask?.cancel()
        let oldAnalyzer = analyzer
        let oldCleanup = cleanupTask
        cleanupTask = Task {
            await oldCleanup?.value
            await oldAnalyzer?.cancelAndFinishNow()
        }
        analyzer = nil
        update = nil
        reportError = nil
        transcript = ""
        level = 0
        phase = .idle
    }

    private func stopAudio() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        playback?.stop()
        playback = nil
        if let engine {
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
            engine.stop()
        }
        tapInstalled = false
        engine = nil
        bridge?.finish()
        bridge = nil
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func fail(_ error: Error, id: UUID) {
        guard operationID == id else { return }
        let handler = reportError
        cancel()
        if !(error is CancellationError) { handler?(error) }
    }

    private func installObservers(engine: AVAudioEngine, id: UUID) {
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.fail(HushError.message("The audio device changed. Restart voice to use the new microphone or headphones."), id: id) }
        })
        #if !os(macOS)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.fail(HushError.message("Voice paused because another app needs audio. Tap Live when you are ready."), id: id) }
        })
        #endif
    }
}
