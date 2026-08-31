import AVFoundation
import Foundation
import Observation

@MainActor
protocol SpeechOutputServing: AnyObject {
    var isSpeaking: Bool { get }
    var currentText: String { get }
    var onActivityChanged: (@MainActor (Bool) -> Void)? { get set }
    var onError: (@MainActor (Error) -> Void)? { get set }
    func begin(id: UUID, preferences: VoicePreferences, playback: VoicePlayback?)
    func append(snapshot: String, final: Bool)
    func stop()
}

@MainActor @Observable
final class SpeechOutput: NSObject, SpeechOutputServing, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var messageID: UUID?
    private(set) var currentText = ""
    @ObservationIgnored var onActivityChanged: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var onError: (@MainActor (Error) -> Void)?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var playback: VoicePlayback?
    @ObservationIgnored private var preferences = VoicePreferences()
    @ObservationIgnored private var chunks: [String] = []
    @ObservationIgnored private var chunker = SpeechChunker()
    @ObservationIgnored private var utterance: AVSpeechUtterance?
    @ObservationIgnored private var utteranceID: UUID?
    @ObservationIgnored private var completedInput = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    func begin(id: UUID, preferences: VoicePreferences, playback: VoicePlayback? = nil) {
        stop()
        messageID = id
        self.preferences = preferences
        self.playback = playback
        chunker = SpeechChunker()
        completedInput = false
        #if !os(macOS)
        synthesizer.usesApplicationAudioSession = playback != nil
        #endif
    }

    func append(snapshot: String, final: Bool) {
        guard messageID != nil else { return }
        chunks.append(contentsOf: chunker.append(snapshot: snapshot, final: final))
        completedInput = final
        pump()
    }

    func togglePause() {
        guard isSpeaking else { return }
        isPaused.toggle()
        if let playback {
            do {
                if isPaused { playback.pause() } else { try playback.resume() }
            } catch { stop(); onError?(error) }
        } else {
            if isPaused { synthesizer.pauseSpeaking(at: .word) } else { synthesizer.continueSpeaking() }
        }
    }

    func stop() {
        messageID = nil
        utteranceID = nil
        utterance = nil
        chunks.removeAll()
        playback?.stop()
        playback = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentText = ""
        onActivityChanged?(false)
    }

    private func pump() {
        guard utteranceID == nil, messageID != nil else { return }
        guard !chunks.isEmpty else {
            if completedInput {
                isSpeaking = false
                isPaused = false
                onActivityChanged?(false)
            }
            return
        }
        let text = chunks.removeFirst()
        let value = AVSpeechUtterance(string: text)
        value.rate = Float(preferences.rate)
        value.voice = preferences.voiceIdentifier.flatMap { id in Self.voices.first { $0.identifier == id } }
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        let id = UUID()
        utterance = value
        utteranceID = id
        currentText = text
        isSpeaking = true
        isPaused = false
        onActivityChanged?(true)
        if let playback {
            // Play synthesized PCM through the same engine as the microphone so AEC has a reference.
            do { try playback.begin(id) { [weak self] in Task { @MainActor in self?.finished(id) } } }
            catch { stop(); onError?(error); return }
            synthesizer.write(value) { @Sendable [weak self, playback] buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 { playback.finish(id); return }
                do { try playback.append(pcm, identifier: id) }
                catch {
                    Task { @MainActor in
                        guard let self, self.utteranceID == id else { return }
                        self.stop()
                        self.onError?(error)
                    }
                }
            }
        } else { synthesizer.speak(value) }
    }

    private func finished(_ id: UUID) {
        guard utteranceID == id else { return }
        utterance = nil
        utteranceID = nil
        pump()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.playback == nil, let current = self.utterance,
                  ObjectIdentifier(current) == identity, let id = self.utteranceID else { return }
            self.finished(id)
        }
    }
}
