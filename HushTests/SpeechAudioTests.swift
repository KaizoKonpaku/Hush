import AVFoundation
import Foundation
import Speech
import Testing
@testable import Hush

struct SpeechAudioTests {
    @Test func invalidAnalyzerFormatFailsBeforeReachingTheFrameworkPrecondition() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let (_, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
        #expect(throws: HushError.self) {
            try SpeechAudioBridge(format: format, continuation: continuation, onLevel: { _ in })
        }
        continuation.finish()
    }

    @MainActor @Test func synthesizedAudioUsesEnginePlaybackAndLateBuffersCannotRestartIt() throws {
        let engine = AVAudioEngine()
        let playback = try VoicePlayback(engine: engine)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        defer { playback.stop(); engine.stop() }
        let sourceFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 2400))
        source.frameLength = 2400
        if let channel = source.floatChannelData?.pointee {
            for index in 0..<2400 { channel[index] = sin(Float(index) * 0.07) * 0.2 }
        }
        let id = UUID()
        try playback.begin(id, completion: {})
        try playback.append(source, identifier: id)
        let rendered = try #require(AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096))
        _ = try engine.renderOffline(4096, to: rendered)
        let values = try #require(rendered.floatChannelData?.pointee)
        #expect((0..<Int(rendered.frameLength)).contains { abs(values[$0]) > 0.01 })
        playback.stop()
        try playback.append(source, identifier: id)
        _ = try engine.renderOffline(4096, to: rendered)
        #expect((0..<Int(rendered.frameLength)).allSatisfy { abs(values[$0]) < 0.001 })
    }

    @Test func immutableMicrophoneBuffersConvertToAnalyzerFormat() async throws {
        let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let analysisFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4800))
        buffer.frameLength = 4800
        if let channel = buffer.floatChannelData?.pointee {
            for index in 0..<4800 { channel[index] = sin(Float(index) * 0.04) * 0.1 }
        }
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(32))
        let bridge = try SpeechAudioBridge(format: analysisFormat, continuation: continuation, onLevel: { _ in })
        for _ in 0..<4 { bridge.append(AVReadOnlyAudioPCMBuffer(copying: buffer)) }
        bridge.finish()
        var duration = 0.0
        for try await input in stream {
            #expect(input.bufferFormat.sampleRate == 16_000)
            duration += input.bufferDuration.seconds
        }
        #expect(duration > 0.35)
        #expect(abs(bridge.audioTime - 0.4) < 0.001)
    }

    @Test func microphoneBackpressureFailsRatherThanSilentlyDroppingWords() async throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        if let channel = buffer.int16ChannelData?.pointee { channel.initialize(repeating: 0, count: 1600) }
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let bridge = try SpeechAudioBridge(format: format, continuation: continuation, onLevel: { _ in })
        for _ in 0..<10 { bridge.append(AVReadOnlyAudioPCMBuffer(copying: buffer)) }
        bridge.finish()
        var failed = false
        do { for try await _ in stream {} }
        catch { failed = error.localizedDescription.contains("keep up") }
        #expect(failed)
    }

    @Test func muteBoundaryDiscardsUnprocessedPreMuteSpeech() {
        var transcript = SpeechTranscript()
        transcript.update(.init(start: 0, end: 1, text: "Already recognized", isFinal: true))
        transcript.discard(through: 5)
        transcript.update(.init(start: 1, end: 4, text: "Arrived after unmute", isFinal: true))
        #expect(transcript.text.isEmpty)
        transcript.update(.init(start: 5, end: 6, text: "New turn", isFinal: false))
        #expect(transcript.text == "New turn")
    }
}

@MainActor @Suite(.serialized)
struct NativeSpeechSmokeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HUSH_RUN_MODEL_SMOKE"] == "1"
                   && SpeechTranscriber.isAvailable), .timeLimit(.minutes(3)))
    func nativeSpeechSynthesisAndStreamingTranscriptionRoundTrip() async throws {
        let locale = try #require(await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")))
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let modules: [any SpeechModule] = [transcriber, SpeechDetector()]
        if let assets = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await assets.downloadAndInstall()
        }
        let format = try #require(await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules))
        let (input, inputContinuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingNewest(256))
        let bridge = try SpeechAudioBridge(format: format, continuation: inputContinuation, onLevel: { _ in })
        let (audio, audioContinuation) = AsyncThrowingStream<AVReadOnlyAudioPCMBuffer, Error>.makeStream()
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "Hello. This is a local voice test. The blue bicycle is beside the garden. Everything stays on this device.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        let analyzer = SpeechAnalyzer(modules: modules)
        try await analyzer.prepareToAnalyze(in: format)
        let results = Task {
            var transcript = SpeechTranscript()
            for try await result in transcriber.results {
                transcript.update(.init(start: result.range.start.seconds, end: result.range.end.seconds,
                    text: String(result.text.characters), isFinal: result.isFinal))
            }
            return transcript.text
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(45))
            audioContinuation.finish(throwing: HushError.message("Native speech synthesis did not finish."))
        }
        defer { timeout.cancel(); synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.write(utterance) { @Sendable buffer in
            guard let buffer = buffer as? AVAudioPCMBuffer else { return }
            if buffer.frameLength == 0 { audioContinuation.finish() }
            else { audioContinuation.yield(AVReadOnlyAudioPCMBuffer(copying: buffer)) }
        }
        let producer = Task {
            var frames = 0
            do {
                for try await buffer in audio {
                    frames += buffer.frameLength
                    bridge.append(buffer)
                }
                bridge.finish()
                return frames
            } catch {
                inputContinuation.finish(throwing: error)
                throw error
            }
        }
        do {
            try await analyzer.start(inputSequence: input)
            let frames = try await producer.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await results.value
            #expect(frames > 10_000)
            #expect(text.localizedCaseInsensitiveContains("bicycle"))
            #expect(text.localizedCaseInsensitiveContains("garden"))
            print("Native speech round trip passed: \(frames) synthesized frames; transcript: \(text)")
        } catch {
            producer.cancel()
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }
}
