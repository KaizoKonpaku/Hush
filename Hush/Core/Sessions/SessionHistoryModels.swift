import Foundation

struct SessionInteraction: Codable, Identifiable, Sendable {
    let id: UUID
    let prompt: String
    let response: String
    let captureCount: Int
    let startedAt: Date
    let finishedAt: Date
    let openAIResponseID: String?
    let openAIConversationID: String?
    let assetIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case response
        case captureCount
        case startedAt
        case finishedAt
        case openAIResponseID
        case openAIConversationID
        case assetIDs
    }

    init(
        id: UUID = UUID(),
        prompt: String,
        response: String,
        captureCount: Int,
        startedAt: Date,
        finishedAt: Date,
        openAIResponseID: String? = nil,
        openAIConversationID: String? = nil,
        assetIDs: [UUID] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.response = response
        self.captureCount = captureCount
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.openAIResponseID = openAIResponseID
        self.openAIConversationID = openAIConversationID
        self.assetIDs = assetIDs
    }

    var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    var searchText: String {
        [prompt, response]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            prompt: try container.decode(String.self, forKey: .prompt),
            response: try container.decode(String.self, forKey: .response),
            captureCount: try container.decodeIfPresent(Int.self, forKey: .captureCount) ?? 0,
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            finishedAt: try container.decode(Date.self, forKey: .finishedAt),
            openAIResponseID: try container.decodeIfPresent(String.self, forKey: .openAIResponseID),
            openAIConversationID: try container.decodeIfPresent(String.self, forKey: .openAIConversationID),
            assetIDs: try container.decodeIfPresent([UUID].self, forKey: .assetIDs) ?? []
        )
    }
}

enum AttachmentAssetUploadStatus: String, Codable, Sendable {
    case notRequired
    case pending
    case uploaded
    case failed
}

struct AttachmentAssetRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String
    var source: OverlayCaptureSource
    var bookmarkData: Data?
    var localFilePath: String?
    var mimeType: String?
    var fileSizeBytes: Int?
    var sha256: String?
    var previewPNGData: Data?
    var extractedTextDigest: String?
    var degradedSummary: String?
    var openAIFileID: String?
    var uploadStatus: AttachmentAssetUploadStatus
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        source: OverlayCaptureSource,
        bookmarkData: Data? = nil,
        localFilePath: String? = nil,
        mimeType: String? = nil,
        fileSizeBytes: Int? = nil,
        sha256: String? = nil,
        previewPNGData: Data? = nil,
        extractedTextDigest: String? = nil,
        degradedSummary: String? = nil,
        openAIFileID: String? = nil,
        uploadStatus: AttachmentAssetUploadStatus = .notRequired,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.bookmarkData = bookmarkData
        self.localFilePath = localFilePath
        self.mimeType = mimeType
        self.fileSizeBytes = fileSizeBytes
        self.sha256 = sha256
        self.previewPNGData = previewPNGData
        self.extractedTextDigest = extractedTextDigest
        self.degradedSummary = degradedSummary
        self.openAIFileID = openAIFileID
        self.uploadStatus = uploadStatus
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var resolvedLocalURL: URL? {
        if let bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }

        if let localFilePath, !localFilePath.isEmpty {
            return URL(fileURLWithPath: localFilePath)
        }

        return nil
    }

    var searchableText: String {
        [
            title,
            subtitle,
            extractedTextDigest,
            degradedSummary,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        .joined(separator: "\n")
    }
}

enum ConversationItemRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

enum ConversationItemKind: String, Codable, Sendable {
    case message
    case summary
    case toolCall = "tool_call"
    case toolOutput = "tool_output"
}

enum ConversationItemOrigin: String, Codable, Sendable {
    case typed
    case live
    case system
    case migrated
}

enum ConversationItemStatus: String, Codable, Sendable {
    case pending
    case completed
    case failed
    case interrupted
    case truncated
}

enum ConversationPartKind: String, Codable, Sendable {
    case inputText = "input_text"
    case outputText = "output_text"
    case inputImage = "input_image"
    case inputFile = "input_file"
    case transcriptText = "transcript_text"
    case attachmentReference = "attachment_reference"
}

struct ConversationPartRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var kind: ConversationPartKind
    var text: String?
    var assetID: UUID?
    var mimeType: String?
    var openAIFileID: String?
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        kind: ConversationPartKind,
        text: String? = nil,
        assetID: UUID? = nil,
        mimeType: String? = nil,
        openAIFileID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.text = text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.assetID = assetID
        self.mimeType = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.openAIFileID = openAIFileID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.metadata = metadata
    }

    var searchableText: String {
        text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct ConversationItemRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var interactionID: UUID?
    var remoteItemID: String?
    var responseID: String?
    var realtimeSessionID: String?
    var role: ConversationItemRole
    var kind: ConversationItemKind
    var origin: ConversationItemOrigin
    var status: ConversationItemStatus
    var parts: [ConversationPartRecord]
    var createdAt: Date
    var finishedAt: Date?
    var errorMessage: String?
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        interactionID: UUID? = nil,
        remoteItemID: String? = nil,
        responseID: String? = nil,
        realtimeSessionID: String? = nil,
        role: ConversationItemRole,
        kind: ConversationItemKind = .message,
        origin: ConversationItemOrigin,
        status: ConversationItemStatus = .completed,
        parts: [ConversationPartRecord],
        createdAt: Date = Date(),
        finishedAt: Date? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.interactionID = interactionID
        self.remoteItemID = remoteItemID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.responseID = responseID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.realtimeSessionID = realtimeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.role = role
        self.kind = kind
        self.origin = origin
        self.status = status
        self.parts = parts
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.metadata = metadata
    }

    var assetIDs: [UUID] {
        parts.compactMap(\.assetID)
    }

    var preferredDisplayText: String {
        preferredText(for: role)
    }

    var searchableText: String {
        parts
            .map(\.searchableText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    func preferredText(for role: ConversationItemRole) -> String {
        let preferredKinds: [ConversationPartKind]
        switch role {
        case .assistant:
            preferredKinds = [.outputText, .transcriptText, .inputText]
        case .user, .system, .tool:
            preferredKinds = [.inputText, .transcriptText, .outputText]
        }

        for kind in preferredKinds {
            let combined = parts
                .filter { $0.kind == kind }
                .compactMap(\.text)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            if !combined.isEmpty {
                return combined
            }
        }

        return ""
    }
}

struct SessionErrorEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let message: String
    let occurredAt: Date

    init(id: UUID = UUID(), title: String, message: String, occurredAt: Date = Date()) {
        self.id = id
        self.title = title
        self.message = message
        self.occurredAt = occurredAt
    }
}

struct SessionRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var startedAt: Date
    var updatedAt: Date
    var finishedAt: Date?
    var pinnedAt: Date?
    var archivedAt: Date?
    var customTitle: String?
    var openAIConversationID: String?
    var latestResponseID: String?
    var activeRealtimeSessionID: String?
    var items: [ConversationItemRecord]
    var assets: [AttachmentAssetRecord]
    var captureCount: Int
    var errors: [SessionErrorEvent]

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case updatedAt
        case finishedAt
        case pinnedAt
        case archivedAt
        case customTitle
        case openAIConversationID
        case latestResponseID
        case activeRealtimeSessionID
        case items
        case assets
        case interactions
        case captureCount
        case errors
    }

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        updatedAt: Date? = nil,
        finishedAt: Date? = nil,
        pinnedAt: Date? = nil,
        archivedAt: Date? = nil,
        customTitle: String? = nil,
        openAIConversationID: String? = nil,
        latestResponseID: String? = nil,
        activeRealtimeSessionID: String? = nil,
        interactions: [SessionInteraction] = [],
        items: [ConversationItemRecord]? = nil,
        assets: [AttachmentAssetRecord] = [],
        captureCount: Int = 0,
        errors: [SessionErrorEvent] = []
    ) {
        let canonicalItems = items ?? Self.canonicalItems(from: interactions, conversationID: openAIConversationID)

        self.id = id
        self.startedAt = startedAt
        self.updatedAt = updatedAt ?? finishedAt ?? startedAt
        self.finishedAt = finishedAt
        self.pinnedAt = pinnedAt
        self.archivedAt = archivedAt
        self.customTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.openAIConversationID = openAIConversationID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.latestResponseID = (latestResponseID ?? canonicalItems.reversed().lazy.compactMap(\.responseID).first)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        self.activeRealtimeSessionID = activeRealtimeSessionID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.items = canonicalItems.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        self.assets = assets.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        self.captureCount = captureCount
        self.errors = errors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let startedAt = try container.decode(Date.self, forKey: .startedAt)
        let finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        let captureCount = try container.decodeIfPresent(Int.self, forKey: .captureCount) ?? 0
        let errors = try container.decodeIfPresent([SessionErrorEvent].self, forKey: .errors) ?? []
        let decodedItems = try container.decodeIfPresent([ConversationItemRecord].self, forKey: .items) ?? []
        let decodedAssets = try container.decodeIfPresent([AttachmentAssetRecord].self, forKey: .assets) ?? []
        let legacyInteractions = try container.decodeIfPresent([SessionInteraction].self, forKey: .interactions) ?? []
        let openAIConversationID = try container.decodeIfPresent(String.self, forKey: .openAIConversationID)
            ?? legacyInteractions.last?.openAIConversationID
        let latestResponseID = try container.decodeIfPresent(String.self, forKey: .latestResponseID)
            ?? legacyInteractions.reversed().lazy.compactMap(\.openAIResponseID).first

        self.init(
            id: id,
            startedAt: startedAt,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? finishedAt ?? startedAt,
            finishedAt: finishedAt,
            pinnedAt: try container.decodeIfPresent(Date.self, forKey: .pinnedAt),
            archivedAt: try container.decodeIfPresent(Date.self, forKey: .archivedAt),
            customTitle: try container.decodeIfPresent(String.self, forKey: .customTitle),
            openAIConversationID: openAIConversationID,
            latestResponseID: latestResponseID,
            activeRealtimeSessionID: try container.decodeIfPresent(String.self, forKey: .activeRealtimeSessionID),
            interactions: legacyInteractions,
            items: decodedItems.isEmpty ? nil : decodedItems,
            assets: decodedAssets,
            captureCount: captureCount,
            errors: errors
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(finishedAt, forKey: .finishedAt)
        try container.encodeIfPresent(pinnedAt, forKey: .pinnedAt)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try container.encodeIfPresent(openAIConversationID, forKey: .openAIConversationID)
        try container.encodeIfPresent(latestResponseID, forKey: .latestResponseID)
        try container.encodeIfPresent(activeRealtimeSessionID, forKey: .activeRealtimeSessionID)
        try container.encode(items, forKey: .items)
        try container.encode(assets, forKey: .assets)
        try container.encode(interactions, forKey: .interactions)
        try container.encode(captureCount, forKey: .captureCount)
        try container.encode(errors, forKey: .errors)
    }

    var interactions: [SessionInteraction] {
        Self.derivedInteractions(from: items)
    }

    var interactionCount: Int { interactions.count }
    var errorCount: Int { errors.count }
    var isPinned: Bool { pinnedAt != nil }
    var isArchived: Bool { archivedAt != nil }
    var hasContent: Bool { !items.isEmpty || captureCount > 0 || errorCount > 0 }
    var lastActivityAt: Date { updatedAt }
    var latestOpenAIResponseID: String? {
        (latestResponseID ?? interactions.reversed().lazy.compactMap(\.openAIResponseID).first)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
    var displayTitle: String {
        if let customTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customTitle.isEmpty {
            return customTitle
        }

        guard let firstPrompt = interactions.first?.prompt else { return "Assistant" }

        let normalized = firstPrompt
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        guard !normalized.isEmpty else { return "Assistant" }
        if normalized.count <= 44 {
            return normalized
        }

        let cutoffIndex = normalized.index(normalized.startIndex, offsetBy: 44)
        return String(normalized[..<cutoffIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    var duration: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var searchText: String {
        var segments = [displayTitle]
        segments.append(contentsOf: interactions.map(\.searchText))
        segments.append(contentsOf: assets.map(\.searchableText))
        segments.append(contentsOf: errors.map { "\($0.title)\n\($0.message)" })
        return segments.joined(separator: "\n")
    }

    func searchSnippet(matching query: String) -> String? {
        let candidates = [displayTitle]
            + interactions.flatMap { [$0.prompt, $0.response] }
            + assets.map(\.searchableText)
            + errors.flatMap { [$0.title, $0.message] }

        return candidates.lazy.compactMap { SessionSearchSupport.snippet(in: $0, matching: query) }.first
    }

    func interaction(with interactionID: UUID) -> SessionInteraction? {
        interactions.first(where: { $0.id == interactionID })
    }

    func asset(with assetID: UUID) -> AttachmentAssetRecord? {
        assets.first(where: { $0.id == assetID })
    }

    func assets(for interactionID: UUID) -> [AttachmentAssetRecord] {
        let assetIDs = interaction(with: interactionID)?.assetIDs ?? []
        guard !assetIDs.isEmpty else { return [] }

        let wanted = Set(assetIDs)
        return assets.filter { wanted.contains($0.id) }
    }

    func interactions(
        upTo interactionID: UUID,
        includeSelectedInteraction: Bool
    ) -> [SessionInteraction]? {
        let interactions = interactions
        guard let index = interactions.firstIndex(where: { $0.id == interactionID }) else {
            return nil
        }

        let upperBound = includeSelectedInteraction ? index + 1 : index
        return Array(interactions.prefix(upperBound))
    }

    func continuationResponseID(before interactionID: UUID?) -> String? {
        let interactions = interactions

        guard let interactionID else {
            return latestOpenAIResponseID
        }

        guard let index = interactions.firstIndex(where: { $0.id == interactionID }) else {
            return latestOpenAIResponseID
        }

        return interactions[..<index].reversed().lazy.compactMap(\.openAIResponseID).first
    }

    func seedCopy(with interactions: [SessionInteraction], startedAt: Date = Date()) -> SessionRecord {
        let selectedAssetIDs = Set(interactions.flatMap(\.assetIDs))
        let seededAssets = assets.filter { selectedAssetIDs.contains($0.id) }

        return SessionRecord(
            startedAt: startedAt,
            updatedAt: startedAt,
            finishedAt: nil,
            pinnedAt: nil,
            archivedAt: nil,
            customTitle: customTitle,
            openAIConversationID: nil,
            latestResponseID: nil,
            activeRealtimeSessionID: nil,
            interactions: interactions,
            assets: seededAssets,
            captureCount: interactions.reduce(0) { $0 + $1.captureCount },
            errors: []
        )
    }

    static func sortDescending(_ lhs: SessionRecord, _ rhs: SessionRecord) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        if lhs.pinnedAt != rhs.pinnedAt {
            return (lhs.pinnedAt ?? .distantPast) > (rhs.pinnedAt ?? .distantPast)
        }

        if lhs.lastActivityAt != rhs.lastActivityAt {
            return lhs.lastActivityAt > rhs.lastActivityAt
        }

        return lhs.startedAt > rhs.startedAt
    }

    private static func canonicalItems(
        from interactions: [SessionInteraction],
        conversationID: String?
    ) -> [ConversationItemRecord] {
        interactions.flatMap { interaction in
            var baseMetadata = [String: String]()
            if let conversationID = conversationID?.trimmingCharacters(in: .whitespacesAndNewlines), !conversationID.isEmpty {
                baseMetadata["conversation_id"] = conversationID
            }

            let promptParts = interaction.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [
                    ConversationPartRecord(
                        kind: .inputText,
                        text: interaction.prompt
                    )
                ]

            let assistantParts = interaction.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [
                    ConversationPartRecord(
                        kind: .outputText,
                        text: interaction.response
                    )
                ]

            let userItem = ConversationItemRecord(
                id: UUID(),
                interactionID: interaction.id,
                responseID: interaction.openAIResponseID,
                role: .user,
                origin: .migrated,
                status: .completed,
                parts: promptParts,
                createdAt: interaction.startedAt,
                finishedAt: interaction.startedAt,
                metadata: baseMetadata
            )

            let assistantItem = ConversationItemRecord(
                id: UUID(),
                interactionID: interaction.id,
                responseID: interaction.openAIResponseID,
                role: .assistant,
                origin: .migrated,
                status: .completed,
                parts: assistantParts,
                createdAt: interaction.finishedAt,
                finishedAt: interaction.finishedAt,
                metadata: baseMetadata
            )

            return [userItem, assistantItem]
        }
    }

    private static func derivedInteractions(from items: [ConversationItemRecord]) -> [SessionInteraction] {
        let groupedItems = Dictionary(grouping: items.compactMap { item in
            item.interactionID.map { ($0, item) }
        }, by: \.0)

        return groupedItems
            .map { interactionID, grouped in
                let records = grouped.map(\.1).sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                let userItem = records.first(where: { $0.role == .user || $0.role == .system })
                let assistantItem = records.reversed().first(where: { $0.role == .assistant })
                let prompt = userItem?.preferredText(for: .user) ?? ""
                let response = assistantItem?.preferredText(for: .assistant) ?? ""
                let captureAssetIDs = userItem?.assetIDs ?? []
                let startedAt = userItem?.createdAt ?? records.first?.createdAt ?? Date()
                let finishedAt = assistantItem?.finishedAt
                    ?? assistantItem?.createdAt
                    ?? userItem?.finishedAt
                    ?? startedAt
                let openAIResponseID = assistantItem?.responseID
                    ?? userItem?.responseID
                let openAIConversationID = assistantItem?.metadata["conversation_id"]
                    ?? userItem?.metadata["conversation_id"]

                return SessionInteraction(
                    id: interactionID,
                    prompt: prompt,
                    response: response,
                    captureCount: captureAssetIDs.count,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    openAIResponseID: openAIResponseID,
                    openAIConversationID: openAIConversationID,
                    assetIDs: captureAssetIDs
                )
            }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt {
                    return lhs.startedAt < rhs.startedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }
}

struct SessionSearchResult: Identifiable, Sendable {
    let session: SessionRecord
    let snippet: String

    var id: UUID { session.id }
}

private enum SessionSearchSupport {
    static func snippet(in text: String, matching query: String, radius: Int = 72) -> String? {
        let trimmedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty, !trimmedQuery.isEmpty else { return nil }

        let tokens = trimmedQuery
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }

        let normalizedText = normalized(trimmedText)
        guard !tokens.isEmpty else { return nil }
        guard tokens.allSatisfy({ normalizedText.contains(normalized($0)) }) else { return nil }

        let index = normalizedText.range(of: normalized(tokens[0]))?.lowerBound ?? normalizedText.startIndex
        let utf16Distance = normalizedText.utf16.distance(from: normalizedText.startIndex, to: index)
        let textIndex = trimmedText.index(trimmedText.startIndex, offsetBy: min(utf16Distance, trimmedText.count))
        let start = trimmedText.index(textIndex, offsetBy: -min(radius, trimmedText.distance(from: trimmedText.startIndex, to: textIndex)), limitedBy: trimmedText.startIndex) ?? trimmedText.startIndex
        let end = trimmedText.index(textIndex, offsetBy: min(radius, trimmedText.distance(from: textIndex, to: trimmedText.endIndex)), limitedBy: trimmedText.endIndex) ?? trimmedText.endIndex

        var snippet = String(trimmedText[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > trimmedText.startIndex {
            snippet = "..." + snippet
        }
        if end < trimmedText.endIndex {
            snippet += "..."
        }
        return snippet
    }

    private static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
