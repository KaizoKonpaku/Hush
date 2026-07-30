import Foundation
import XCTest
@testable import Hush

private final class PersistWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var writes: [(url: URL, data: Data)] = []

    func record(_ data: Data, url: URL) {
        lock.withLock {
            writes.append((url: url, data: data))
        }
    }

    var writeCount: Int {
        lock.withLock { writes.count }
    }

    var lastWrite: (url: URL, data: Data)? {
        lock.withLock { writes.last }
    }
}

@MainActor
final class SessionHistoryStoreTests: XCTestCase {
    func testPersistenceDebouncesBurstUpdatesIntoSingleWrite() async throws {
        let recorder = PersistWriteRecorder()
        let persistence = SessionHistoryPersistence(
            debounceNanoseconds: 50_000_000,
            writer: { data, url in
                recorder.record(data, url: url)
            }
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hush-session-tests-\(UUID().uuidString).json")
        let store = SessionHistoryStore(
            storageURLProvider: { tempURL },
            persistence: persistence
        )

        store.recordCaptureAdded()
        store.recordError(title: "Oops", message: "Something failed")
        store.recordInteraction(
            prompt: "Hello",
            response: "Hi",
            captureCount: 1,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 11)
        )

        try await Task.sleep(nanoseconds: 120_000_000)
        await persistence.flush()

        XCTAssertEqual(recorder.writeCount, 1)

        let lastWrite = try XCTUnwrap(recorder.lastWrite)
        XCTAssertEqual(lastWrite.url.lastPathComponent, "current-session.json")

        let session = try JSONDecoder().decode(SessionRecord.self, from: lastWrite.data)
        XCTAssertEqual(session.captureCount, 1)
        XCTAssertEqual(session.errorCount, 1)
        XCTAssertEqual(session.interactionCount, 1)
    }

    func testLegacySingleJSONMigratesToPerSessionFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hush-session-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let archivedSession = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20),
            interactions: [
                SessionInteraction(
                    prompt: "Past prompt",
                    response: "Past response",
                    captureCount: 0,
                    startedAt: Date(timeIntervalSince1970: 10),
                    finishedAt: Date(timeIntervalSince1970: 20),
                    openAIResponseID: "resp_past"
                )
            ]
        )
        let currentSession = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 30),
            interactions: [
                SessionInteraction(
                    prompt: "Current prompt",
                    response: "Current response",
                    captureCount: 1,
                    startedAt: Date(timeIntervalSince1970: 30),
                    finishedAt: Date(timeIntervalSince1970: 35),
                    openAIResponseID: "resp_current"
                )
            ],
            captureCount: 1
        )

        let legacyURL = rootURL.appendingPathComponent("sessions.json")
        let payload = PersistedSessions(sessions: [archivedSession], currentSession: currentSession)
        try JSONEncoder().encode(payload).write(to: legacyURL, options: .atomic)

        let store = SessionHistoryStore(storageURLProvider: { legacyURL })

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.currentSession.interactionCount, 1)
        XCTAssertEqual(store.currentSession.latestOpenAIResponseID, "resp_current")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("current-session.json").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootURL
                    .appendingPathComponent("sessions", isDirectory: true)
                    .appendingPathComponent("\(archivedSession.id.uuidString).json")
                    .path
            )
        )
    }

    func testArchivingCurrentSessionResetsWorkspaceAndPreservesMetadata() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hush-session-archive-\(UUID().uuidString).json")
        let store = SessionHistoryStore(storageURLProvider: { tempURL })

        store.recordInteraction(
            prompt: "Draft a release note",
            response: "Here is a polished version.",
            captureCount: 2,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 12)
        )
        store.renameSession(id: store.currentSession.id, title: "Release Notes")

        let archivedID = store.currentSession.id
        store.setArchived(true, for: archivedID)

        XCTAssertNotEqual(store.currentSession.id, archivedID)
        XCTAssertTrue(store.currentSession.interactions.isEmpty)
        XCTAssertTrue(store.currentSession.errors.isEmpty)
        XCTAssertTrue(store.currentSession.captureCount == 0)

        let archivedSession = store.sessions.first(where: { $0.id == archivedID })
        XCTAssertEqual(archivedSession?.displayTitle, "Release Notes")
        XCTAssertTrue(archivedSession?.isArchived == true)
        XCTAssertEqual(archivedSession?.interactionCount, 1)
        XCTAssertEqual(archivedSession?.captureCount, 2)
    }

    func testLoadingLegacyArchivedSessionWithoutAssetIDsKeepsSessionAccessible() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hush-session-legacy-load-\(UUID().uuidString)", isDirectory: true)
        let sessionsURL = rootURL.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)

        let legacyArchivedSession = """
        {
          "id": "AB789D31-31C4-4B38-ACB5-6B9A44FCDFCC",
          "startedAt": 797243035.076204,
          "updatedAt": 797243490.06243,
          "finishedAt": 797243490.06243,
          "captureCount": 1,
          "errors": [],
          "interactions": [
            {
              "id": "301C2822-F764-463E-A2AC-9F31A546879F",
              "prompt": "",
              "response": "Legacy response",
              "captureCount": 1,
              "finishedAt": 797243372.210767,
              "startedAt": 797243371.782413
            }
          ]
        }
        """

        try legacyArchivedSession.data(using: .utf8)?
            .write(to: sessionsURL.appendingPathComponent("AB789D31-31C4-4B38-ACB5-6B9A44FCDFCC.json"))

        let store = SessionHistoryStore(storageURLProvider: { rootURL })

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.interactionCount, 1)
        XCTAssertEqual(store.sessions.first?.interactions.first?.assetIDs, [])
        XCTAssertEqual(store.sessions.first?.interactions.first?.response, "Legacy response")
    }
}
