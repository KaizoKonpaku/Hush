import AVFoundation
import Foundation
import Observation
import Speech

@MainActor @Observable
final class VoiceCapture {
    enum Phase { case idle, preparing, recording, transcribing }
    private(set) var phase: Phase = .idle
    var isActive: Bool { phase != .idle }
    var status: String {
        switch phase {
        case .idle: "Dictate on device"
        case .preparing: "Preparing on-device dictation"
        case .recording: "Listening on this device. Tap the mic to finish."
        case .transcribing: "Transcribing on this device"
        }
    }

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var transcriber: SpeechTranscriber?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var onText: (@MainActor (String) -> Void)?
    @ObservationIgnored private var onError: (@MainActor (Error) -> Void)?

    func start(onText: @escaping @MainActor (String) -> Void, onError: @escaping @MainActor (Error) -> Void) {
        guard phase == .idle else { return }
        let id = UUID()
        operationID = id
        phase = .preparing
        self.onText = onText
        self.onError = onError
        task = Task {
            do {
                guard SpeechTranscriber.isAvailable,
                      let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                    throw HushError.message("On-device dictation is not available for this device or language.")
                }
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw HushError.message("Allow microphone access in Settings to use dictation. You can still type or attach a document.")
                }
                try Task.checkCancellation()
                let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
                if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await installation.downloadAndInstall()
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                #if !os(macOS)
                try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let url = FileManager.default.temporaryDirectory.appending(path: "hush-dictation-\(id.uuidString).wav")
                recordingURL = url
                let recorder = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                ])
                guard recorder.record(forDuration: 60) else { throw HushError.message("The microphone could not start recording.") }
                self.recordingURL = url
                self.recorder = recorder
                self.transcriber = transcriber
                phase = .recording
                timeoutTask = Task { [self] in
                    do { try await Task.sleep(for: .seconds(60)); finish() }
                    catch { }
                }
            } catch {
                guard operationID == id else { return }
                let report = self.onError
                cancel()
                if !(error is CancellationError) { report?(error) }
            }
        }
    }

    func finish() {
        guard phase == .recording, let url = recordingURL, let transcriber, let id = operationID else { return }
        recorder?.stop()
        recorder = nil
        timeoutTask?.cancel()
        phase = .transcribing
        task = Task {
            do {
                let file = try AVAudioFile(forReading: url)
                let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
                guard operationID == id, !Task.isCancelled else {
                    await analyzer.cancelAndFinishNow()
                    return
                }
                self.analyzer = analyzer
                var text = ""
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    text += String(result.text.characters)
                }
                try Task.checkCancellation()
                guard operationID == id else { return }
                let completion = onText
                cancel()
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { completion?(text) }
            } catch {
                guard operationID == id else { return }
                let report = onError
                cancel()
                if !(error is CancellationError) { report?(error) }
            }
        }
    }

    func cancel() {
        operationID = nil
        task?.cancel()
        timeoutTask?.cancel()
        recorder?.stop()
        recorder = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        transcriber = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        onText = nil
        onError = nil
        phase = .idle
    }
}
