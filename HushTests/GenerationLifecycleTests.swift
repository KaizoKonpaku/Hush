import Foundation
import Testing
@testable import Hush

@MainActor
struct GenerationLifecycleTests {
    @Test func streamingStaysWithItsOriginalConversation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ControlledRuntime()
        let workspace = WorkspaceModel(root: root, runtime: runtime)
        await workspace.bootstrap()
        workspace.send("First conversation")
        let original = try #require(workspace.selectedConversationID)
        try await eventually { await runtime.hasStarted }
        workspace.newConversation()
        await runtime.emit(.snapshot("This belongs to the first conversation."))
        await runtime.emit(.completed(GenerationMetrics(outputTokens: 8)))
        await runtime.finish()
        try await eventually { !workspace.isGenerating }
        #expect(workspace.selectedConversationID == nil)
        #expect(workspace.messages.isEmpty)
        #expect(workspace.conversations.first(where: { $0.id == original })?.messages.last?.text == "This belongs to the first conversation.")
    }

    @Test func cancellationPreservesPartialResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ControlledRuntime()
        let workspace = WorkspaceModel(root: root, runtime: runtime)
        await workspace.bootstrap()
        workspace.send("A long response")
        try await eventually { await runtime.hasStarted }
        await runtime.emit(.snapshot("Keep this partial answer"))
        try await eventually { workspace.messages.last?.text == "Keep this partial answer" }
        workspace.stop()
        try await eventually { !workspace.isGenerating }
        #expect(workspace.messages.last?.status == .stopped)
        #expect(workspace.messages.last?.text == "Keep this partial answer")
    }

    @Test func duplicateSubmitDoesNotStartConcurrentModelRuns() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ControlledRuntime()
        let workspace = WorkspaceModel(root: root, runtime: runtime)
        await workspace.bootstrap()
        workspace.send("First")
        workspace.send("Second")
        try await eventually { await runtime.hasStarted }
        #expect(await runtime.requests == 1)
        #expect(workspace.messages.count == 2)
        workspace.stop()
        try await eventually { !workspace.isGenerating }
    }

    @Test func freshDraftSurvivesConversationNavigation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = WorkspaceModel(root: root, runtime: ControlledRuntime())
        await workspace.bootstrap()
        let existing = Conversation(title: "Another conversation")
        workspace.conversations = [existing]
        workspace.draft = "An unfinished idea"
        workspace.selectConversation(existing.id)
        workspace.draft = "A separate follow-up"
        workspace.newConversation()
        #expect(workspace.draft == "An unfinished idea")
        workspace.selectConversation(existing.id)
        #expect(workspace.draft == "A separate follow-up")
        await workspace.prepareToClose()
    }

    @Test func retryReplacesTheAnswerWithoutDuplicatingAssistantTurns() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ControlledRuntime()
        let workspace = WorkspaceModel(root: root, runtime: runtime)
        await workspace.bootstrap()
        var conversation = Conversation(title: "Retry")
        conversation.messages = [ChatMessage(role: .user, text: "Question"), ChatMessage(role: .assistant, text: "First answer")]
        workspace.conversations = [conversation]
        workspace.selectConversation(conversation.id)
        workspace.retry()
        try await eventually { await runtime.hasStarted }
        await runtime.emit(.snapshot("Replacement answer"))
        await runtime.emit(.completed(GenerationMetrics(outputTokens: 2)))
        await runtime.finish()
        try await eventually { !workspace.isGenerating }
        #expect(workspace.messages.map(\.role) == [.user, .assistant])
        #expect(workspace.messages.last?.text == "Replacement answer")
        await workspace.prepareToClose()
    }

    @Test func contextContainsOnlyAlternatingCompletedExchanges() {
        let messages = [
            ChatMessage(role: .user, text: "Failed question"),
            ChatMessage(role: .assistant, text: "Error", status: .failed),
            ChatMessage(role: .user, text: "Successful question"),
            ChatMessage(role: .assistant, text: "Answer"),
            ChatMessage(role: .assistant, text: "Duplicate answer"),
            ChatMessage(role: .user, text: "Unanswered question"),
        ]
        let context = ConversationContext.completedTurns(from: messages)
        #expect(context.map(\.role) == [.user, .assistant])
        #expect(context.map(\.text) == ["Successful question", "Answer"])
    }

    @Test func deletingWithHistoryOffRemovesSavedChatAndAttachments() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let attachment = ChatAttachment(name: "Private note", kind: .text, filename: "note.txt", byteCount: 4)
        var conversation = Conversation(title: "Delete this")
        conversation.messages = [ChatMessage(role: .user, text: "A note", attachments: [attachment])]
        try await store.save(LibraryArchive(conversations: [conversation]), revision: 0)
        let file = root.appending(path: "Attachments/note.txt")
        try Data("note".utf8).write(to: file)
        let workspace = WorkspaceModel(root: root, runtime: ControlledRuntime())
        await workspace.bootstrap()
        workspace.selectConversation(conversation.id)
        workspace.settings.keepHistory = false
        workspace.deleteConversation(conversation.id)
        try await eventually { !FileManager.default.fileExists(atPath: file.path) }
        #expect(try await store.load().conversations.isEmpty)
        #expect(workspace.selectedConversationID == nil)
        #expect(workspace.messages.isEmpty)
        await workspace.prepareToClose()
    }

    @Test func failedLibraryWriteKeepsReferencedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = WorkspaceModel(root: root, runtime: ControlledRuntime())
        await workspace.bootstrap()
        #expect(await workspace.flush())
        let attachment = ChatAttachment(name: "Keep", kind: .text, filename: "keep.txt", byteCount: 4)
        var conversation = Conversation(title: "Keep attachments on failure")
        conversation.messages = [ChatMessage(role: .user, text: "Read", attachments: [attachment])]
        workspace.conversations = [conversation]
        let file = root.appending(path: "Attachments/keep.txt")
        try Data("keep".utf8).write(to: file)
        let library = root.appending(path: "library.json")
        try FileManager.default.removeItem(at: library)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: false)
        workspace.deleteConversation(conversation.id)
        try await eventually { workspace.notice != nil }
        #expect(FileManager.default.fileExists(atPath: file.path))
        await workspace.prepareToClose()
    }

    @Test func modelRemovalPreventsGenerationDuringUnload() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = ControlledRuntime()
        let workspace = WorkspaceModel(root: root, runtime: runtime)
        await workspace.bootstrap()
        var model = ModelRecord(id: "tests/removal", name: "Removal", author: "Tests", engine: .mlx, summary: "")
        model.installedDirectory = model.diskKey
        let directory = root.appending(path: "Models/\(model.diskKey)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(model).write(to: directory.appending(path: "hush-model.json"))
        workspace.installedModels = [model]
        workspace.selectModel(model)
        workspace.draft = "Do not start while model files are being removed"
        await runtime.blockUnload()
        let removal = Task { await workspace.removeModel(model) }
        try await eventually { await runtime.unloadStarted }
        #expect(workspace.isRemovingModel)
        #expect(!workspace.canSend)
        workspace.send()
        #expect(!workspace.isGenerating)
        #expect(await runtime.requests == 0)
        await runtime.finishUnload()
        await removal.value
        #expect(!workspace.isRemovingModel)
        #expect(workspace.installedModels.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        await workspace.prepareToClose()
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The expected asynchronous state was not reached.")
    }
}

actor ControlledRuntime: InferenceServing {
    private var continuation: AsyncStream<GenerationEvent>.Continuation?
    var hasStarted = false
    var requests = 0
    var lastRequest: GenerationRequest?
    var unloadStarted = false
    private var unloadIsBlocked = false

    func generate(_ request: GenerationRequest, event: @Sendable @escaping (GenerationEvent) async -> Void) async throws {
        requests += 1
        lastRequest = request
        let (stream, continuation) = AsyncStream<GenerationEvent>.makeStream()
        self.continuation = continuation
        hasStarted = true
        for await item in stream { try Task.checkCancellation(); await event(item) }
        try Task.checkCancellation()
    }
    func emit(_ event: GenerationEvent) { continuation?.yield(event) }
    func finish() { continuation?.finish() }
    func blockUnload() { unloadIsBlocked = true }
    func finishUnload() { unloadIsBlocked = false }
    func unload() async {
        unloadStarted = true
        while unloadIsBlocked { try? await Task.sleep(for: .milliseconds(10)) }
    }
}
