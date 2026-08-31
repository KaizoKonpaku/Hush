import AVFoundation
import Foundation
import Speech
import Synchronization

struct VoiceLevel: Sendable {
    let amplitude: Double
    let hasSpeechEnergy: Bool
}

final class SpeechAudioBridge: Sendable {
    private struct State {
        let converter: AnalyzerInputConverter
        var frames: AVAudioFramePosition = 0
        var sampleRate = 0.0
        var lastMeterTime = ContinuousClock.now
        var noiseFloor = 0.002
        var muted = false
        var finished = false
    }
    private let state: Mutex<State>
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let onLevel: @Sendable (VoiceLevel) -> Void

    init(format: AVAudioFormat, continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
         onLevel: @escaping @Sendable (VoiceLevel) -> Void) throws {
        guard format.commonFormat == .pcmFormatInt16 else {
            throw HushError.message("Speech analysis requires signed 16-bit audio.")
        }
        state = Mutex(State(converter: AnalyzerInputConverter(analyzerFormat: format)))
        self.continuation = continuation
        self.onLevel = onLevel
    }

    func append(_ readOnlyBuffer: AVReadOnlyAudioPCMBuffer) {
        // OS 27's immutable tap buffer crosses threads safely. Mutable conversion stays inside the lock.
        state.withLock { state in
            guard !state.finished else { return }
            let buffer = AVAudioPCMBuffer(copying: readOnlyBuffer)
            state.sampleRate = buffer.format.sampleRate
            let time = AVAudioTime(sampleTime: state.frames, atRate: buffer.format.sampleRate)
            state.frames += AVAudioFramePosition(buffer.frameLength)
            do {
                for input in try state.converter.convert(buffer, at: time) {
                    if case .dropped = continuation.yield(input) {
                        state.finished = true
                        continuation.finish(throwing: HushError.message("Speech could not keep up with the microphone. Please restart live voice."))
                        return
                    }
                }
                if state.lastMeterTime.duration(to: .now) >= .milliseconds(80) {
                    state.lastMeterTime = .now
                    var sum: Float = 0
                    if let channel = buffer.floatChannelData?.pointee {
                        for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
                    } else if let channel = buffer.int16ChannelData?.pointee {
                        for index in 0..<Int(buffer.frameLength) {
                            let sample = Float(channel[index]) / Float(Int16.max)
                            sum += sample * sample
                        }
                    }
                    let rms = sqrt(Double(sum) / Double(max(1, buffer.frameLength)))
                    let speech = !state.muted && rms > max(0.008, state.noiseFloor * 3)
                    if !speech { state.noiseFloor = state.noiseFloor * 0.95 + min(rms, 0.02) * 0.05 }
                    onLevel(VoiceLevel(amplitude: state.muted ? 0 : min(1, rms * 12), hasSpeechEnergy: speech))
                }
            } catch {
                state.finished = true
                continuation.finish(throwing: error)
            }
        }
    }

    func setMuted(_ muted: Bool) { state.withLock { $0.muted = muted } }
    var audioTime: Double { state.withLock { $0.sampleRate > 0 ? Double($0.frames) / $0.sampleRate : 0 } }
    func finish() {
        state.withLock { state in
            guard !state.finished else { return }
            state.finished = true
            do {
                for input in try state.converter.flush() { continuation.yield(input) }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
}

final class VoicePlayback: Sendable {
    private struct State {
        let player: AVAudioPlayerNode
        let format: AVAudioFormat
        var identifier: UUID?
        var scheduledBuffers = 0
        var ended = false
        var completion: (@Sendable () -> Void)?
        var converter: AVAudioConverter?
    }
    private let state: Mutex<State>

    @MainActor
    init(engine: AVAudioEngine) throws {
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        engine.attach(player)
        try engine.connectNode(player, to: engine.mainMixerNode, format: format)
        state = Mutex(State(player: player, format: format))
    }

    func begin(_ identifier: UUID, completion: @escaping @Sendable () -> Void) throws {
        stop()
        let player = state.withLock { state in
            state.identifier = identifier
            state.scheduledBuffers = 0
            state.ended = false
            state.completion = completion
            state.converter = nil
            return state.player
        }
        try player.playAudio()
    }

    func append(_ buffer: AVAudioPCMBuffer, identifier: UUID) throws {
        try state.withLock { state in
            guard state.identifier == identifier, buffer.frameLength > 0 else { return }
            if state.converter?.inputFormat != buffer.format {
                state.converter = AVAudioConverter(from: buffer.format, to: state.format)
                state.converter?.primeMethod = .none
            }
            guard let converter = state.converter, let converted = AVAudioPCMBuffer(pcmFormat: state.format,
                    frameCapacity: AVAudioFrameCount(ceil(Double(buffer.frameLength) * state.format.sampleRate / buffer.format.sampleRate)) + 32) else {
                throw HushError.message("This voice's audio format could not be played.")
            }
            var supplied = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if let conversionError { throw conversionError }
            guard converted.frameLength > 0 else { return }
            state.scheduledBuffers += 1
            state.player.scheduleBuffer(AVReadOnlyAudioPCMBuffer(copying: converted), completionCallbackType: .dataPlayedBack) { [weak self] in self?.played(identifier) }
        }
    }

    func finish(_ identifier: UUID) {
        let completion = state.withLock { state -> (@Sendable () -> Void)? in
            guard state.identifier == identifier else { return nil }
            state.ended = true
            guard state.scheduledBuffers == 0 else { return nil }
            defer { state.completion = nil }
            return state.completion
        }
        completion?()
    }

    private func played(_ identifier: UUID) {
        let completion = state.withLock { state -> (@Sendable () -> Void)? in
            guard state.identifier == identifier else { return nil }
            state.scheduledBuffers -= 1
            guard state.ended, state.scheduledBuffers == 0 else { return nil }
            defer { state.completion = nil }
            return state.completion
        }
        completion?()
    }

    func pause() { state.withLock { $0.player.pause() } }
    func resume() throws { try state.withLock { try $0.player.playAudio() } }
    func stop() {
        let player = state.withLock {
            $0.identifier = nil
            $0.completion = nil
            $0.scheduledBuffers = 0
            $0.converter = nil
            return $0.player
        }
        player.stop()
    }
}
