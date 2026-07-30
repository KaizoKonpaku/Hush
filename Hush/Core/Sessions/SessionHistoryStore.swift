import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SessionHistoryStore {
    static let shared = SessionHistoryStore()
    nonisolated static let customDirectoryDefaultsKey = "locations.storage.sessions.customPath"
    nonisolated static let directoryModeDefaultsKey = "locations.storage.sessions.mode"

    var sessions: [SessionRecord] = []
    var currentSession: SessionRecord
    var selectedSessionID: UUID?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let persistence: SessionHistoryPersistence
    private let storageURLProvider: @Sendable () throws -> URL

    init(
        storageURLProvider: @escaping @Sendable () throws -> URL = SessionHistoryStore.defaultStorageURL,
        persistence: SessionHistoryPersistence = SessionHistoryPersistence()
    ) {
        self.storageURLProvider = storageURLProvider
        self.persistence = persistence
        self.currentSession = SessionRecord()
        load()
    }

    var totalInteractions: Int {
        sessions.reduce(0) { $0 + $1.interactionCount } + currentSession.interactionCount
    }

    var totalCaptures: Int {
        sessions.reduce(0) { $0 + $1.captureCount } + currentSession.captureCount
    }

    var totalErrors: Int {
        sessions.reduce(0) { $0 + $1.errorCount } + currentSession.errorCount
    }

    var displayedSession: SessionRecord {
        guard let selectedSessionID else { return currentSession }
        return sessions.first(where: { $0.id == selectedSessionID }) ?? currentSession
    }

    var pinnedSessions: [SessionRecord] {
        sessions.filter { $0.isPinned && !$0.isArchived }
    }

    var archivedSessions: [SessionRecord] {
        sessions.filter(\.isArchived)
    }

    var activeSessions: [SessionRecord] {
        sessions.filter { !$0.isArchived }
    }

    var recentSessions: [SessionRecord] {
        activeSessions.filter { !$0.isPinned }
    }

    func startNewSession(seedSession: SessionRecord? = nil) {
        archiveCurrentSessionIfNeeded(markArchived: false)

        currentSession = seedSession ?? SessionRecord(startedAt: Date())
        selectedSessionID = nil
        persist(.current)
    }

    func selectCurrentSession() {
        selectedSessionID = nil
    }

    func selectSession(id: UUID) {
        selectedSessionID = id
    }

    func recordCaptureAdded(count: Int = 1) {
        let target = mutateDisplayedSession { session in
            session.captureCount += count
        }
        persist(target)
    }

    func recordError(title: String, message: String) {
        let target = mutateDisplayedSession { session in
            session.errors.append(SessionErrorEvent(title: title, message: message))
        }
        persist(target)
    }

    func recordInteraction(
        id: UUID = UUID(),
        prompt: String,
        response: String,
        captureCount: Int,
        startedAt: Date,
        finishedAt: Date,
        openAIResponseID: String? = nil
    ) {
        recordTypedTurn(
            interactionID: id,
            prompt: prompt,
            response: response,
            assets: [],
            captureCountOverride: captureCount,
            startedAt: startedAt,
            finishedAt: finishedAt,
            openAIConversationID: nil,
            openAIResponseID: openAIResponseID
        )
    }

    func recordTypedTurn(
        interactionID: UUID = UUID(),
        prompt: String,
        response: String,
        assets: [AttachmentAssetRecord],
        captureCountOverride: Int? = nil,
        startedAt: Date,
        finishedAt: Date,
        openAIConversationID: String?,
        openAIResponseID: String?,
        userRemoteItemID: String? = nil,
        assistantRemoteItemID: String? = nil
    ) {
        let target = mutateDisplayedSession { session in
            let mergedAssets = mergeAssets(into: &session.assets, newAssets: assets)
            upsertConversationTurn(
                in: &session,
                interactionID: interactionID,
                prompt: prompt,
                response: response,
                assets: mergedAssets,
                captureCountOverride: captureCountOverride,
                startedAt: startedAt,
                finishedAt: finishedAt,
                origin: .typed,
                openAIConversationID: openAIConversationID,
                openAIResponseID: openAIResponseID,
                realtimeSessionID: nil,
                userRemoteItemID: userRemoteItemID,
                assistantRemoteItemID: assistantRemoteItemID,
                userTextKind: .inputText,
                assistantTextKind: .outputText,
                assistantStatus: .completed
            )
        }
        persist(target)
    }

    func recordLiveTurn(
        interactionID: UUID = UUID(),
        prompt: String,
        response: String,
        startedAt: Date,
        finishedAt: Date,
        openAIConversationID: String?,
        realtimeSessionID: String?,
        assistantResponseID: String? = nil,
        userRemoteItemID: String? = nil,
        assistantRemoteItemID: String? = nil,
        wasInterrupted: Bool = false,
        wasTruncated: Bool = false
    ) {
        let target = mutateDisplayedSession { session in
            let assistantStatus: ConversationItemStatus = wasInterrupted ? .interrupted : (wasTruncated ? .truncated : .completed)
            var assistantMetadata = [String: String]()
            if wasInterrupted {
                assistantMetadata["interrupted"] = "true"
            }
            if wasTruncated {
                assistantMetadata["truncated"] = "true"
            }

            upsertConversationTurn(
                in: &session,
                interactionID: interactionID,
                prompt: prompt,
                response: response,
                assets: [],
                captureCountOverride: 0,
                startedAt: startedAt,
                finishedAt: finishedAt,
                origin: .live,
                openAIConversationID: openAIConversationID,
                openAIResponseID: assistantResponseID,
                realtimeSessionID: realtimeSessionID,
                userRemoteItemID: userRemoteItemID,
                assistantRemoteItemID: assistantRemoteItemID,
                userTextKind: .transcriptText,
                assistantTextKind: .transcriptText,
                assistantStatus: assistantStatus,
                assistantMetadata: assistantMetadata
            )
        }
        persist(target)
    }

    func upsertAssets(_ assets: [AttachmentAssetRecord]) {
        guard !assets.isEmpty else { return }
        let target = mutateDisplayedSession { session in
            _ = mergeAssets(into: &session.assets, newAssets: assets)
        }
        persist(target)
    }

    func setRemoteConversationID(_ conversationID: String?) {
        let target = mutateDisplayedSession { session in
            session.openAIConversationID = normalizeIdentifier(conversationID)
        }
        persist(target)
    }

    func setLatestResponseID(_ responseID: String?) {
        let target = mutateDisplayedSession { session in
            session.latestResponseID = normalizeIdentifier(responseID)
        }
        persist(target)
    }

    func setActiveRealtimeSessionID(_ sessionID: String?) {
        let target = mutateDisplayedSession { session in
            session.activeRealtimeSessionID = normalizeIdentifier(sessionID)
        }
        persist(target)
    }

    func persistCurrentState() {
        persistAll()
    }

    func togglePinned(for sessionID: UUID) {
        let target = mutateSession(withID: sessionID, touch: false) { session in
            session.pinnedAt = session.pinnedAt == nil ? Date() : nil
        }
        guard let target else {
            return
        }

        persist(target)
    }

    func renameSession(id: UUID, title: String) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let target = mutateSession(withID: id, touch: false, { session in
            session.customTitle = normalizedTitle
        }) else {
            return
        }

        persist(target)
    }

    func setArchived(_ isArchived: Bool, for sessionID: UUID) {
        if currentSession.id == sessionID {
            guard isArchived, currentSession.hasContent else { return }
            archiveCurrentSessionIfNeeded(markArchived: true)
            currentSession = SessionRecord(startedAt: Date())
            selectedSessionID = nil
            persist(.current)
            return
        }

        guard let target = mutateSession(withID: sessionID, touch: false, { session in
            session.archivedAt = isArchived ? Date() : nil
        }) else {
            return
        }

        persist(target)
    }

    func deleteSession(id: UUID) {
        if currentSession.id == id {
            currentSession = SessionRecord(startedAt: Date())
            selectedSessionID = nil
            persist(.current)
            return
        }

        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let deletedSession = sessions.remove(at: index)

        if selectedSessionID == deletedSession.id {
            selectedSessionID = nil
        }

        do {
            let url = try sessionFileURL(for: deletedSession.id)
            Task {
                await persistence.scheduleDelete(at: url)
            }
        } catch {
            NSLog("[HUSH] SessionHistoryStore delete failed: \(error.localizedDescription)")
        }
    }

    func sessionSearchResults(for query: String) -> [SessionSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let candidates = [currentSession] + sessions
        return candidates
            .compactMap { session in
                guard let snippet = session.searchSnippet(matching: trimmedQuery) else {
                    return nil
                }

                return SessionSearchResult(session: session, snippet: snippet)
            }
            .sorted { lhs, rhs in
                SessionRecord.sortDescending(lhs.session, rhs.session)
            }
    }

    private func load() {
        do {
            _ = try storageRootURL()
            try migrateLegacyStoreIfNeeded()
            self.currentSession = try loadCurrentSession()
            self.sessions = try loadArchivedSessions()
            sortSessions()
        } catch {
            NSLog("[HUSH] SessionHistoryStore load failed: \(error.localizedDescription)")
        }
    }

    private func persist(_ target: SessionPersistenceTarget) {
        do {
            let payload = try persistencePayload(for: target)
            Task {
                await persistence.schedulePersist(data: payload.data, to: payload.url)
            }
        } catch {
            NSLog("[HUSH] SessionHistoryStore persist failed: \(error.localizedDescription)")
        }
    }

    func storageDirectoryURL() throws -> URL {
        try storageRootURL()
    }

    func openStorageDirectory() {
        do {
            let directoryURL = try storageDirectoryURL()
            NSWorkspace.shared.open(directoryURL)
        } catch {
            NSLog("[HUSH] SessionHistoryStore open storage directory failed: \(error.localizedDescription)")
        }
    }

    nonisolated static func defaultStorageDirectoryURL() throws -> URL {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: directoryModeDefaultsKey) == "custom",
           let configuredPath = defaults.string(forKey: customDirectoryDefaultsKey),
           !configuredPath.isEmpty {
            let directoryURL = URL(fileURLWithPath: configuredPath, isDirectory: true)
            try HUSHFileSystem.ensureDirectoryExists(at: directoryURL)
            return directoryURL
        }

        return try HUSHFileSystem.applicationSupportDirectory()
    }

    nonisolated private static func defaultStorageURL() throws -> URL {
        try defaultStorageDirectoryURL()
            .appendingPathComponent("sessions.json")
    }

    private func persistAll() {
        do {
            let currentPayload = try persistencePayload(for: .current)
            let archivedPayloads = try sessions.map { session in
                try (data: encoder.encode(session), url: sessionFileURL(for: session.id))
            }

            Task {
                await persistence.schedulePersist(data: currentPayload.data, to: currentPayload.url)
                for payload in archivedPayloads {
                    await persistence.schedulePersist(data: payload.data, to: payload.url)
                }
            }
        } catch {
            NSLog("[HUSH] SessionHistoryStore persist-all failed: \(error.localizedDescription)")
        }
    }

    private func persistencePayload(for target: SessionPersistenceTarget) throws -> (data: Data, url: URL) {
        switch target {
        case .current:
            return try (encoder.encode(currentSession), currentSessionStorageURL())
        case let .archived(sessionID):
            guard let session = sessions.first(where: { $0.id == sessionID }) else {
                throw NSError(
                    domain: "HUSH.SessionHistoryStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing session for persistence."]
                )
            }
            return try (encoder.encode(session), sessionFileURL(for: session.id))
        }
    }

    private func archiveCurrentSessionIfNeeded(markArchived: Bool) {
        guard currentSession.hasContent else {
            return
        }

        currentSession.finishedAt = Date()
        currentSession.updatedAt = currentSession.finishedAt ?? Date()
        currentSession.archivedAt = markArchived ? Date() : nil
        sessions.removeAll { $0.id == currentSession.id }
        sessions.append(currentSession)
        sortSessions()
        persist(.archived(currentSession.id))
    }

    @discardableResult
    private func mutateDisplayedSession(
        touch: Bool = true,
        _ mutation: (inout SessionRecord) -> Void
    ) -> SessionPersistenceTarget {
        if let selectedSessionID,
           let target = mutateSession(withID: selectedSessionID, touch: touch, mutation) {
            return target
        }

        mutation(&currentSession)
        if touch {
            currentSession.updatedAt = Date()
        }
        return .current
    }

    @discardableResult
    private func mutateSession(
        withID sessionID: UUID,
        touch: Bool = true,
        _ mutation: (inout SessionRecord) -> Void
    ) -> SessionPersistenceTarget? {
        if currentSession.id == sessionID {
            mutation(&currentSession)
            if touch {
                currentSession.updatedAt = Date()
            }
            return .current
        }

        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return nil
        }

        mutation(&sessions[index])
        if touch {
            sessions[index].updatedAt = Date()
        }
        sortSessions()
        return .archived(sessionID)
    }

    private func sortSessions() {
        sessions.sort(by: SessionRecord.sortDescending)
    }

    private func mergeAssets(
        into existingAssets: inout [AttachmentAssetRecord],
        newAssets: [AttachmentAssetRecord]
    ) -> [AttachmentAssetRecord] {
        guard !newAssets.isEmpty else { return [] }

        var resolvedAssets: [AttachmentAssetRecord] = []
        resolvedAssets.reserveCapacity(newAssets.count)

        for asset in newAssets {
            if let directIndex = existingAssets.firstIndex(where: { $0.id == asset.id }) {
                existingAssets[directIndex] = mergedAsset(existingAssets[directIndex], with: asset)
                resolvedAssets.append(existingAssets[directIndex])
                continue
            }

            if let dedupedIndex = existingAssets.firstIndex(where: { existingAsset in
                if let incomingHash = asset.sha256?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !incomingHash.isEmpty,
                   incomingHash == existingAsset.sha256?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return true
                }

                if let incomingPath = asset.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !incomingPath.isEmpty,
                   incomingPath == existingAsset.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                   existingAsset.source == asset.source {
                    return true
                }

                return false
            }) {
                existingAssets[dedupedIndex] = mergedAsset(existingAssets[dedupedIndex], with: asset)
                resolvedAssets.append(existingAssets[dedupedIndex])
                continue
            }

            existingAssets.append(asset)
            resolvedAssets.append(asset)
        }

        existingAssets.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return resolvedAssets
    }

    private func mergedAsset(_ existing: AttachmentAssetRecord, with incoming: AttachmentAssetRecord) -> AttachmentAssetRecord {
        AttachmentAssetRecord(
            id: existing.id,
            title: incoming.title,
            subtitle: incoming.subtitle,
            source: incoming.source,
            bookmarkData: incoming.bookmarkData ?? existing.bookmarkData,
            localFilePath: incoming.localFilePath ?? existing.localFilePath,
            mimeType: incoming.mimeType ?? existing.mimeType,
            fileSizeBytes: incoming.fileSizeBytes ?? existing.fileSizeBytes,
            sha256: incoming.sha256 ?? existing.sha256,
            previewPNGData: incoming.previewPNGData ?? existing.previewPNGData,
            extractedTextDigest: incoming.extractedTextDigest ?? existing.extractedTextDigest,
            degradedSummary: incoming.degradedSummary ?? existing.degradedSummary,
            openAIFileID: incoming.openAIFileID ?? existing.openAIFileID,
            uploadStatus: incoming.uploadStatus == .notRequired ? existing.uploadStatus : incoming.uploadStatus,
            lastError: incoming.lastError ?? existing.lastError,
            createdAt: existing.createdAt,
            updatedAt: max(existing.updatedAt, incoming.updatedAt)
        )
    }

    private func upsertConversationTurn(
        in session: inout SessionRecord,
        interactionID: UUID,
        prompt: String,
        response: String,
        assets: [AttachmentAssetRecord],
        captureCountOverride: Int?,
        startedAt: Date,
        finishedAt: Date,
        origin: ConversationItemOrigin,
        openAIConversationID: String?,
        openAIResponseID: String?,
        realtimeSessionID: String?,
        userRemoteItemID: String?,
        assistantRemoteItemID: String?,
        userTextKind: ConversationPartKind,
        assistantTextKind: ConversationPartKind,
        assistantStatus: ConversationItemStatus,
        assistantMetadata: [String: String] = [:]
    ) {
        let normalizedConversationID = normalizeIdentifier(openAIConversationID)
        let normalizedResponseID = normalizeIdentifier(openAIResponseID)
        let normalizedRealtimeSessionID = normalizeIdentifier(realtimeSessionID)
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)

        var baseMetadata = [String: String]()
        if let normalizedConversationID {
            baseMetadata["conversation_id"] = normalizedConversationID
        }

        let assetParts = assets.map { asset in
            ConversationPartRecord(
                kind: asset.source == .file ? .inputFile : .inputImage,
                assetID: asset.id,
                mimeType: asset.mimeType,
                openAIFileID: asset.openAIFileID,
                metadata: [
                    "source": asset.source.rawValue,
                    "title": asset.title,
                ]
            )
        }

        let userTextParts = normalizedPrompt.isEmpty
            ? []
            : [ConversationPartRecord(kind: userTextKind, text: normalizedPrompt)]

        let userItem = ConversationItemRecord(
            id: UUID(),
            interactionID: interactionID,
            remoteItemID: normalizeIdentifier(userRemoteItemID),
            responseID: normalizedResponseID,
            realtimeSessionID: normalizedRealtimeSessionID,
            role: .user,
            kind: .message,
            origin: origin,
            status: .completed,
            parts: userTextParts + assetParts,
            createdAt: startedAt,
            finishedAt: startedAt,
            metadata: baseMetadata
        )

        let assistantTextParts = normalizedResponse.isEmpty
            ? []
            : [ConversationPartRecord(kind: assistantTextKind, text: normalizedResponse)]

        var mergedAssistantMetadata = baseMetadata
        for (key, value) in assistantMetadata {
            mergedAssistantMetadata[key] = value
        }

        let assistantItem = ConversationItemRecord(
            id: UUID(),
            interactionID: interactionID,
            remoteItemID: normalizeIdentifier(assistantRemoteItemID),
            responseID: normalizedResponseID,
            realtimeSessionID: normalizedRealtimeSessionID,
            role: .assistant,
            kind: .message,
            origin: origin,
            status: assistantStatus,
            parts: assistantTextParts,
            createdAt: finishedAt,
            finishedAt: finishedAt,
            metadata: mergedAssistantMetadata
        )

        session.items.removeAll { $0.interactionID == interactionID }

        let effectiveCaptureCount = captureCountOverride ?? assets.count

        if !userItem.parts.isEmpty || effectiveCaptureCount > 0 {
            session.items.append(userItem)
        }
        if !assistantItem.parts.isEmpty {
            session.items.append(assistantItem)
        }

        session.items.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        if let normalizedConversationID {
            session.openAIConversationID = normalizedConversationID
        }

        if let normalizedResponseID {
            session.latestResponseID = normalizedResponseID
        }

        if let normalizedRealtimeSessionID {
            session.activeRealtimeSessionID = normalizedRealtimeSessionID
        }

        session.captureCount = max(session.captureCount, effectiveCaptureCount)

        session.finishedAt = nil
    }

    private func normalizeIdentifier(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func storageRootURL() throws -> URL {
        let configuredURL = try storageURLProvider().standardizedFileURL
        let rootURL: URL

        if configuredURL.pathExtension.lowercased() == "json" {
            rootURL = configuredURL.deletingLastPathComponent()
        } else {
            rootURL = configuredURL
        }

        try HUSHFileSystem.ensureDirectoryExists(at: rootURL)
        return rootURL
    }

    private func legacyStorageURL() throws -> URL {
        let configuredURL = try storageURLProvider().standardizedFileURL

        if configuredURL.pathExtension.lowercased() == "json" {
            try HUSHFileSystem.ensureDirectoryExists(at: configuredURL.deletingLastPathComponent())
            return configuredURL
        }

        return try storageRootURL()
            .appendingPathComponent("sessions.json")
    }

    private func currentSessionStorageURL() throws -> URL {
        try storageRootURL()
            .appendingPathComponent("current-session.json")
    }

    private func archivedSessionsDirectoryURL() throws -> URL {
        let directoryURL = try storageRootURL()
            .appendingPathComponent("sessions", isDirectory: true)
        try HUSHFileSystem.ensureDirectoryExists(at: directoryURL)
        return directoryURL
    }

    private func sessionFileURL(for sessionID: UUID) throws -> URL {
        try archivedSessionsDirectoryURL()
            .appendingPathComponent("\(sessionID.uuidString).json")
    }

    private func migrateLegacyStoreIfNeeded() throws {
        let legacyURL = try legacyStorageURL()
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }

        let currentExists = FileManager.default.fileExists(atPath: try currentSessionStorageURL().path)
        let archivedDirectory = try archivedSessionsDirectoryURL()
        let archivedURLs = try FileManager.default.contentsOfDirectory(
            at: archivedDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        guard !currentExists, archivedURLs.isEmpty else { return }

        let data = try Data(contentsOf: legacyURL)
        let payload = try decoder.decode(PersistedSessions.self, from: data)
        try writeMigratedStore(payload)
    }

    private func writeMigratedStore(_ payload: PersistedSessions) throws {
        try encoder.encode(payload.currentSession)
            .write(to: currentSessionStorageURL(), options: .atomic)

        for session in payload.sessions {
            try encoder.encode(session)
                .write(to: sessionFileURL(for: session.id), options: .atomic)
        }
    }

    private func loadCurrentSession() throws -> SessionRecord {
        let currentURL = try currentSessionStorageURL()
        guard FileManager.default.fileExists(atPath: currentURL.path) else {
            return SessionRecord()
        }

        return try loadSessionRecord(at: currentURL)
    }

    private func loadArchivedSessions() throws -> [SessionRecord] {
        let archivedDirectory = try archivedSessionsDirectoryURL()
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: archivedDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }

        var loadedSessions: [SessionRecord] = []
        for fileURL in fileURLs {
            do {
                loadedSessions.append(try loadSessionRecord(at: fileURL))
            } catch {
                NSLog("[HUSH] SessionHistoryStore session load failed: \(error.localizedDescription)")
            }
        }

        return loadedSessions
    }

    private func loadSessionRecord(at url: URL) throws -> SessionRecord {
        let data = try Data(contentsOf: url)
        return try decoder.decode(SessionRecord.self, from: data)
    }
}

struct PersistedSessions: Codable, Sendable {
    var sessions: [SessionRecord]
    var currentSession: SessionRecord
}

private enum SessionPersistenceTarget {
    case current
    case archived(UUID)
}

actor SessionHistoryPersistence {
    private var pendingTasks: [URL: Task<Void, Never>] = [:]
    private let debounceNanoseconds: UInt64
    private let writer: @Sendable (Data, URL) throws -> Void

    init(
        debounceNanoseconds: UInt64 = 250_000_000,
        writer: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.debounceNanoseconds = debounceNanoseconds
        self.writer = writer
    }

    func schedulePersist(data: Data, to url: URL) {
        scheduleTask(for: url) { [writer] in
            try writer(data, url)
        }
    }

    func scheduleDelete(at url: URL) {
        scheduleTask(for: url) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        }
    }

    func flush() async {
        let tasks = Array(pendingTasks.values)
        for task in tasks {
            _ = await task.value
        }
    }

    private func scheduleTask(for url: URL, operation: @escaping @Sendable () throws -> Void) {
        pendingTasks[url]?.cancel()
        pendingTasks[url] = Task { [debounceNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
                try Task.checkCancellation()
                try operation()
            } catch is CancellationError {
            } catch {
                NSLog("[HUSH] SessionHistoryStore persist failed: \(error.localizedDescription)")
            }

            clearPendingTask(for: url)
        }
    }

    private func clearPendingTask(for url: URL) {
        pendingTasks[url] = nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
