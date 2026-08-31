import Foundation
import Observation

@MainActor @Observable
final class LiveVoiceSession {
    enum Phase { case off, preparing, listening, thinking, speaking }
    private(set) var phase: Phase = .off
    private(set) var isMuted = false
    private(set) var caption = ""
    private(set) var level = 0.0
    private(set) var pendingTurnID: UUID?
    var isActive: Bool { phase != .off }
    var status: String {
        if isMuted { return "Microphone muted" }
        return switch phase {
        case .off: "Live voice"
        case .preparing: "Preparing live voice"
        case .listening: "Listening"
        case .thinking: "Thinking on device"
        case .speaking: preferences.allowInterruptions ? "Speaking. You can interrupt." : "Speaking"
        }
    }

    @ObservationIgnored var onTurn: (@MainActor (String, UUID) async throws -> Void)?
    @ObservationIgnored var onInterrupt: (@MainActor () -> Void)?
    @ObservationIgnored var onError: (@MainActor (Error) -> Void)?
    @ObservationIgnored private let input: any SpeechInputServing
    @ObservationIgnored private let output: any SpeechOutputServing
    @ObservationIgnored private var preferences = VoicePreferences()
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var responseID: UUID?
    @ObservationIgnored private var endpointID: UUID?
    @ObservationIgnored private var endpointTask: Task<Void, Never>?
    @ObservationIgnored private var submissionTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var lastActivity = ContinuousClock.now
    @ObservationIgnored private var responseComplete = false

    init(input: any SpeechInputServing, output: any SpeechOutputServing) {
        self.input = input
        self.output = output
    }

    func start(preferences: VoicePreferences) {
        guard !isActive else { return }
        self.preferences = preferences
        let id = UUID()
        sessionID = id
        phase = .preparing
        caption = ""
        isMuted = false
        lastActivity = .now
        output.stop()
        output.onActivityChanged = { [weak self] speaking in
            guard let self, self.sessionID == id else { return }
            if speaking { self.phase = .speaking }
            else if self.responseComplete { self.phase = .listening; self.lastActivity = .now }
        }
        input.start(mode: .conversation, onReady: { [weak self] in
            guard let self, self.sessionID == id else { return }
            self.phase = .listening
        }, onUpdate: { [weak self] text in
            guard let self, self.sessionID == id else { return }
            self.receive(text)
        }, onLevel: { [weak self] value in
            guard let self, self.sessionID == id, !self.isMuted else { return }
            self.level = value.amplitude
            if self.phase == .listening, value.hasSpeechEnergy, !self.caption.isEmpty {
                self.scheduleEndpoint()
            }
        }, onError: { [weak self] error in
            guard let self, self.sessionID == id else { return }
            self.stop()
            self.onError?(error)
        })
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.sessionID == id else { return }
                if self.phase == .listening, self.lastActivity.duration(to: .now) > .seconds(120) {
                    self.stop()
                    self.onError?(HushError.message("Live voice ended after two minutes without a question. Tap Live to continue."))
                    return
                }
            }
        }
    }

    func stop() {
        let wasActive = isActive
        sessionID = nil
        responseID = nil
        pendingTurnID = nil
        endpointID = nil
        endpointTask?.cancel()
        submissionTask?.cancel()
        idleTask?.cancel()
        output.onActivityChanged = nil
        output.stop()
        input.cancel()
        phase = .off
        caption = ""
        level = 0
        isMuted = false
        if wasActive { onInterrupt?() }
    }

    func toggleMute() {
        guard isActive, phase != .preparing else { return }
        isMuted.toggle()
        endpointTask?.cancel()
        endpointID = nil
        caption = ""
        level = 0
        input.setMuted(isMuted)
        lastActivity = .now
    }

    func interrupt() {
        guard isActive else { return }
        responseID = nil
        pendingTurnID = nil
        responseComplete = false
        submissionTask?.cancel()
        output.stop()
        onInterrupt?()
        phase = .listening
        lastActivity = .now
    }

    func beginResponse(_ id: UUID, turnID: UUID) {
        guard isActive, pendingTurnID == turnID else { return }
        responseID = id
        responseComplete = false
        phase = .thinking
        output.begin(id: id, preferences: preferences, playback: input.playback)
    }

    func receiveResponse(_ text: String, id: UUID, final: Bool) {
        guard isActive, responseID == id else { return }
        responseComplete = final
        output.append(snapshot: text, final: final)
        if final, !output.isSpeaking { phase = .listening; lastActivity = .now }
    }

    func failedResponse(_ id: UUID) {
        guard responseID == id else { return }
        responseID = nil
        output.stop()
        phase = .listening
        lastActivity = .now
    }

    private func receive(_ text: String) {
        guard isActive, !isMuted else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if phase == .speaking || phase == .thinking {
            if !preferences.allowInterruptions || (output.isSpeaking && SpokenText.isEcho(text, of: output.currentText)) {
                input.discardTranscript()
                return
            }
            interrupt()
        }
        guard caption != text else { return }
        caption = text
        lastActivity = .now
        scheduleEndpoint()
    }

    private func scheduleEndpoint() {
        guard isActive, !isMuted, !caption.isEmpty, phase == .listening else { return }
        endpointTask?.cancel()
        let id = UUID()
        let session = sessionID
        endpointID = id
        endpointTask = Task { [weak self] in
            do {
                guard let self else { return }
                try await Task.sleep(for: .seconds(self.preferences.silenceDuration))
                let text = try await self.input.finalizeTranscript().trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard self.sessionID == session, self.endpointID == id, !self.isMuted, !text.isEmpty else { return }
                self.input.discardTranscript()
                self.caption = ""
                self.phase = .thinking
                let turnID = UUID()
                self.pendingTurnID = turnID
                self.submissionTask = Task {
                    do { try await self.onTurn?(text, turnID) }
                    catch {
                        guard self.sessionID == session, self.pendingTurnID == turnID else { return }
                        self.interrupt()
                        if !(error is CancellationError) { self.onError?(error) }
                    }
                }
            } catch is CancellationError { }
            catch {
                guard let self, self.sessionID == session else { return }
                self.stop()
                self.onError?(error)
            }
        }
    }
}
