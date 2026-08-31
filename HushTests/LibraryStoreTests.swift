import Foundation
import Testing
@testable import Hush

struct LibraryStoreTests {
    @Test func roundTripsAndRecoversInterruptedResponses() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        var conversation = Conversation(title: "A local thought")
        conversation.messages = [ChatMessage(role: .assistant, text: "Partial response", status: .generating)]
        try await store.save(LibraryArchive(conversations: [conversation]), revision: 1)
        let loaded = try await store.load()
        #expect(loaded.conversations.first?.title == "A local thought")
        #expect(loaded.conversations.first?.messages.first?.status == .stopped)
    }

    @Test func staleWritesCannotReplaceNewerState() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try await store.save(LibraryArchive(conversations: [Conversation(title: "New")]), revision: 2)
        try await store.save(LibraryArchive(conversations: [Conversation(title: "Stale")]), revision: 1)
        #expect(try await store.load().conversations.first?.title == "New")
    }

    @Test func corruptLibraryIsReportedAndKept() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "library.json")
        let corrupted = Data("not a library".utf8)
        try corrupted.write(to: url)
        await #expect(throws: DecodingError.self) { try await LibraryStore(root: root).load() }
        #expect(try Data(contentsOf: url) == corrupted)
    }

    @Test func newWorkspaceDoesNotImportOldChats() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{\"oldChat\":\"not imported\"}".utf8).write(to: root.appending(path: "sessions.json"))
        let archive = try await LibraryStore(root: root.appending(path: "LocalWorkspace")).load()
        #expect(archive.conversations.isEmpty)
    }

    @Test func prunesOnlyUnreferencedAttachmentFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        _ = try await store.load()
        let retained = root.appending(path: "Attachments/retained.txt")
        let orphan = root.appending(path: "Attachments/orphan.txt")
        try Data("keep".utf8).write(to: retained)
        try Data("discard".utf8).write(to: orphan)
        try await store.pruneAttachments(keeping: ["retained.txt"])
        #expect(FileManager.default.fileExists(atPath: retained.path))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func localWorkspaceIsExcludedFromSystemBackups() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await LibraryStore(root: root).load()
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}
