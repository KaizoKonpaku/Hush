import Foundation
import Testing
@testable import Hush

struct SpeechTextTests {
    @Test func progressiveTranscriptsReplaceVolatileWords() {
        var transcript = SpeechTranscript()
        transcript.update(.init(start: 0, end: 1, text: "Find me a", isFinal: false))
        transcript.update(.init(start: 0, end: 2, text: "Find me a model.", isFinal: true))
        transcript.update(.init(start: 0, end: 1, text: "Stale guess", isFinal: false))
        transcript.update(.init(start: 2, end: 3, text: "A small one.", isFinal: true))
        #expect(transcript.text == "Find me a model. A small one.")
    }

    @Test func lateResultFromSubmittedTurnIsNotSubmittedAgain() {
        var transcript = SpeechTranscript()
        transcript.update(.init(start: 0, end: 2, text: "First question", isFinal: false))
        transcript.discard()
        transcript.update(.init(start: 0, end: 2, text: "First question.", isFinal: true))
        transcript.update(.init(start: 2, end: 4, text: "Next question", isFinal: false))
        #expect(transcript.text == "Next question")
    }

    @Test func speechChunksAreIncrementalAndFlushTheLastSentence() {
        var chunker = SpeechChunker()
        #expect(chunker.append(snapshot: "Hello", final: false).isEmpty)
        #expect(chunker.append(snapshot: "Hello there. ", final: false) == ["Hello there."])
        #expect(chunker.append(snapshot: "Hello there. Another thought", final: false).isEmpty)
        #expect(chunker.append(snapshot: "Hello there. Another thought.", final: true) == ["Another thought."])
        #expect(chunker.append(snapshot: "Hello there. Another thought.", final: true).isEmpty)
    }

    @Test func speechDoesNotReadReasoningCodeOrLinkDestinations() {
        let fence = String(repeating: "\u{60}", count: 3)
        let text = "<think>Internal reasoning</think>Hello [reader](https://example.com).\n\(fence)swift\nfatalError()\n\(fence)\nGoodbye."
        let clean = SpokenText.clean(text)
        #expect(!clean.contains("Internal reasoning"))
        #expect(!clean.contains("fatalError"))
        #expect(!clean.contains("https"))
        #expect(clean.contains("Hello reader."))
        #expect(clean.contains("Goodbye."))
    }

    @Test func echoGuardDoesNotSwallowAShortInterruption() {
        #expect(SpokenText.isEcho("The answer is forty two", of: "The answer is forty two."))
        #expect(!SpokenText.isEcho("Stop", of: "Stop and think for a moment."))
        #expect(!SpokenText.isEcho("Actually try something else", of: "The answer is forty two."))
    }

    @Test func currentWorkspaceSettingsDecodeWithoutNewOptionalVoiceFields() throws {
        let data = try JSONEncoder().encode(HushSettings())
        let settings = try JSONDecoder().decode(HushSettings.self, from: data)
        #expect(settings.voiceOptions == VoicePreferences())
        var options = VoicePreferences(rate: .infinity, silenceDuration: .nan)
        options.validate()
        #expect(options.rate == 0.5)
        #expect(options.silenceDuration == 1.1)
    }
}

@MainActor
struct LiveVoiceTests {
    @Test func silenceSubmitsOneTurnWithoutTouchingTypedDrafts() async throws {
        let input = TestSpeechInput()
        let output = TestSpeechOutput()
        let session = LiveVoiceSession(input: input, output: output)
        var submitted: [String] = []
        session.onTurn = { text, _ in submitted.append(text) }
        session.start(preferences: VoicePreferences(silenceDuration: 0.02))
        input.emit("Hello")
        input.emit("Hello there")
        try await eventually { submitted == ["Hello there"] }
        #expect(input.transcript.isEmpty)
        #expect(session.phase == .thinking)
        session.stop()
    }

    @Test func speakingInterruptsAndRejectsLateAudioFromTheOldResponse() async throws {
        let input = TestSpeechInput()
        let output = TestSpeechOutput()
        let session = LiveVoiceSession(input: input, output: output)
        var turn: UUID?
        var interruptions = 0
        session.onTurn = { _, id in turn = id }
        session.onInterrupt = { interruptions += 1 }
        session.start(preferences: VoicePreferences(silenceDuration: 0.02))
        input.emit("Explain this")
        try await eventually { turn != nil }
        let response = UUID()
        session.beginResponse(response, turnID: try #require(turn))
        session.receiveResponse("Here is an explanation. ", id: response, final: false)
        #expect(session.phase == .speaking)
        input.emit("Wait, a shorter answer")
        #expect(interruptions == 1)
        #expect(session.phase == .listening)
        let delivered = output.snapshots
        session.receiveResponse("Old answer must not resume.", id: response, final: true)
        #expect(output.snapshots == delivered)
        session.stop()
    }

    @Test func mutedVoiceDoesNotSubmitAndUnmuteStartsFresh() async throws {
        let input = TestSpeechInput()
        let session = LiveVoiceSession(input: input, output: TestSpeechOutput())
        var submitted: [String] = []
        session.onTurn = { text, _ in submitted.append(text) }
        session.start(preferences: VoicePreferences(silenceDuration: 0.02))
        input.emit("Do not send this")
        session.toggleMute()
        input.emit("Ignored while muted")
        try await Task.sleep(for: .milliseconds(50))
        #expect(submitted.isEmpty)
        session.toggleMute()
        input.emit("Fresh question")
        try await eventually { submitted == ["Fresh question"] }
        session.stop()
    }

    @Test func stoppingCancelsPendingEndpointAndStaleInputCallbacks() async throws {
        let input = TestSpeechInput()
        let session = LiveVoiceSession(input: input, output: TestSpeechOutput())
        var submitted = false
        session.onTurn = { _, _ in submitted = true }
        session.start(preferences: VoicePreferences(silenceDuration: 0.02))
        input.emit("Don't send")
        let late = input.onUpdate
        session.stop()
        late?("A late result")
        try await Task.sleep(for: .milliseconds(60))
        #expect(!submitted)
        #expect(!session.isActive)
        #expect(session.caption.isEmpty)
    }

    @Test func echoDoesNotInterruptButNewWordsDo() async throws {
        let input = TestSpeechInput()
        let output = TestSpeechOutput()
        let session = LiveVoiceSession(input: input, output: output)
        var turn: UUID?
        var interruptions = 0
        session.onTurn = { _, id in turn = id }
        session.onInterrupt = { interruptions += 1 }
        session.start(preferences: VoicePreferences(silenceDuration: 0.02))
        input.emit("What is it?")
        try await eventually { turn != nil }
        let response = UUID()
        session.beginResponse(response, turnID: try #require(turn))
        session.receiveResponse("The answer is forty two. ", id: response, final: false)
        input.emit("The answer is forty two")
        #expect(interruptions == 0)
        #expect(session.phase == .speaking)
        input.emit("Stop")
        #expect(interruptions == 1)
        session.stop()
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Live voice did not reach the expected state.")
    }
}

@MainActor
struct ConversationBranchTests {
    @Test func editingKeepsOriginalAndRegeneratesOnlyTheEditedBranch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ControlledRuntime()
        let workspace = WorkspaceModel(root: root, runtime: runtime)
        await workspace.bootstrap()
        let attachment = ChatAttachment(name: "Reference", kind: .text, filename: "reference.txt", extractedText: "Context", byteCount: 7)
        let user = ChatMessage(role: .user, text: "Original question", attachments: [attachment])
        let original = Conversation(title: "Original", messages: [
            ChatMessage(role: .user, text: "First"), ChatMessage(role: .assistant, text: "First answer"),
            user, ChatMessage(role: .assistant, text: "Original answer"),
        ])
        workspace.conversations = [original]
        workspace.selectConversation(original.id)
        workspace.draft = "Keep my unsent follow-up"
        workspace.editMessage(user.id, text: "Edited question")
        try await eventually { await runtime.hasStarted }
        #expect(workspace.conversations.first(where: { $0.id == original.id }) == original)
        #expect(workspace.currentConversation?.branch?.conversationID == original.id)
        #expect(workspace.currentConversation?.branch?.messageID == user.id)
        #expect(await runtime.lastRequest?.prompt == "Edited question")
        #expect(await runtime.lastRequest?.history.map(\.text) == ["First", "First answer"])
        #expect(await runtime.lastRequest?.attachments == [attachment])
        workspace.stop()
        try await eventually { !workspace.isGenerating }
        workspace.selectConversation(original.id)
        #expect(workspace.draft == "Keep my unsent follow-up")
        await workspace.prepareToClose()
    }

    @Test func branchingAnAnswerCopiesOnlyThePrefixAndRetainsSharedAttachments() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = WorkspaceModel(root: root, runtime: ControlledRuntime())
        await workspace.bootstrap()
        let attachment = ChatAttachment(name: "Shared", kind: .text, filename: "shared.txt", byteCount: 4)
        let answer = ChatMessage(role: .assistant, text: "First answer")
        let original = Conversation(title: "Original", messages: [
            ChatMessage(role: .user, text: "First", attachments: [attachment]), answer,
            ChatMessage(role: .user, text: "Later"), ChatMessage(role: .assistant, text: "Later answer"),
        ])
        try Data("test".utf8).write(to: root.appending(path: "Attachments/shared.txt"))
        workspace.conversations = [original]
        workspace.selectConversation(original.id)
        workspace.branchConversation(at: answer.id)
        #expect(workspace.messages.map(\.text) == ["First", "First answer"])
        #expect(!workspace.isGenerating)
        #expect(await workspace.flush())
        workspace.deleteConversation(original.id)
        #expect(await workspace.flush())
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Attachments/shared.txt").path))
        let loaded = try await LibraryStore(root: root).load()
        #expect(loaded.conversations.count == 1)
        #expect(loaded.conversations.first?.branch?.messageID == answer.id)
        await workspace.prepareToClose()
    }

    @Test func editingIsRejectedWhileGenerationOwnsTheConversation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = WorkspaceModel(root: root, runtime: ControlledRuntime())
        await workspace.bootstrap()
        workspace.send("Question")
        let id = try #require(workspace.messages.first?.id)
        workspace.editMessage(id, text: "Must not race")
        #expect(workspace.conversations.count == 1)
        #expect(workspace.messages.first?.text == "Question")
        workspace.stop()
        try await eventually { !workspace.isGenerating }
        await workspace.prepareToClose()
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The expected conversation state was not reached.")
    }
}

@MainActor
private final class TestSpeechInput: SpeechInputServing {
    var transcript = ""
    var playback: VoicePlayback? { nil }
    var onUpdate: (@MainActor (String) -> Void)?
    func start(mode: SpeechInputMode, onReady: @escaping @MainActor () -> Void,
               onUpdate: @escaping @MainActor (String) -> Void,
               onLevel: @escaping @MainActor (VoiceLevel) -> Void,
               onError: @escaping @MainActor (Error) -> Void) {
        self.onUpdate = onUpdate
        onReady()
    }
    func emit(_ text: String) { transcript = text; onUpdate?(text) }
    func finalizeTranscript() async throws -> String { transcript }
    func discardTranscript() { transcript = "" }
    func setMuted(_ muted: Bool) { discardTranscript() }
    func cancel() { transcript = ""; onUpdate = nil }
}

@MainActor
private final class TestSpeechOutput: SpeechOutputServing {
    var isSpeaking = false
    var currentText = ""
    var onActivityChanged: (@MainActor (Bool) -> Void)?
    var onError: (@MainActor (Error) -> Void)?
    var snapshots: [String] = []
    func begin(id: UUID, preferences: VoicePreferences, playback: VoicePlayback?) {}
    func append(snapshot: String, final: Bool) {
        currentText = snapshot
        snapshots.append(snapshot)
        isSpeaking = !snapshot.isEmpty
        onActivityChanged?(isSpeaking)
    }
    func stop() { isSpeaking = false; currentText = ""; onActivityChanged?(false) }
}
