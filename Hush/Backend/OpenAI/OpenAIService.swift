import AppKit
import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

struct OpenAIAccountRefreshResult {
    let models: [AssistantModelOption]
    let realtimeModels: [AssistantModelOption]
    let realtimeTranscriptionModels: [AssistantModelOption]
    let status: ProviderAccountStatusSummary
}

struct OpenAIConversationSeedItem: Sendable {
    let role: ConversationItemRole
    let contents: [OpenAIConversationSeedContent]
    let metadata: [String: String]

    init(
        role: ConversationItemRole,
        contents: [OpenAIConversationSeedContent],
        metadata: [String: String] = [:]
    ) {
        self.role = role
        self.contents = contents
        self.metadata = metadata
    }
}

enum OpenAIConversationSeedContent: Sendable {
    case inputText(String)
    case outputText(String)
    case imageAsset(AttachmentAssetRecord)
    case fileAsset(AttachmentAssetRecord)
}

struct OpenAIGeneratedResponse: Sendable {
    let id: String
    let conversationID: String
    let text: String
    let assistantItemID: String?
    let assets: [AttachmentAssetRecord]
}

struct OpenAIRealtimeSessionCredentials: Sendable {
    let apiKey: String
    let organizationID: String
    let modelID: String
    let transcriptionModelID: String
    let instructions: String
}

enum OpenAIServiceError: LocalizedError {
    case missingAPIKey
    case invalidRequest
    case invalidResponse
    case emptyResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add a project API key to use OpenAI."
        case .invalidRequest:
            return "HUSH could not build the OpenAI request."
        case .invalidResponse:
            return "OpenAI returned an unreadable response."
        case .emptyResponse:
            return "OpenAI returned no text output."
        case let .requestFailed(message):
            return message
        }
    }
}

private struct OpenAIAPIConfiguration {
    let apiKey: String
    let adminKey: String
    let organizationID: String
    let projectID: String
}

private struct PreparedAttachmentTurn {
    let assets: [AttachmentAssetRecord]
    let content: [ResponseInputContent]
}

final class OpenAIService {
    static let shared = OpenAIService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func refreshAccount(
        record: ProviderAccountRecord,
        secrets: ProviderAccountLocalSecrets
    ) async throws -> OpenAIAccountRefreshResult {
        let configuration = try makeConfiguration(record: record, secrets: secrets)
        let modelIDs = try await listModels(configuration: configuration)
        let models = AssistantModelCatalog.openAIModelOptions(from: modelIDs)
        let realtimeModels = AssistantModelCatalog.openAIRealtimeModelOptions(from: modelIDs)
        let realtimeTranscriptionModels = AssistantModelCatalog.openAIRealtimeTranscriptionModelOptions(from: modelIDs)
        let status = await makeStatusSummary(
            record: record,
            configuration: configuration,
            modelCount: models.count
        )
        return OpenAIAccountRefreshResult(
            models: models,
            realtimeModels: realtimeModels,
            realtimeTranscriptionModels: realtimeTranscriptionModels,
            status: status
        )
    }

    func generateResponse(
        prompt: String,
        captures: [OverlayCapture],
        existingAssets: [AttachmentAssetRecord],
        seedItems: [OpenAIConversationSeedItem],
        modelID: String,
        modelMode: AssistantModelMode,
        conversationID: String?,
        record: ProviderAccountRecord,
        secrets: ProviderAccountLocalSecrets
    ) async throws -> OpenAIGeneratedResponse {
        let configuration = try makeConfiguration(record: record, secrets: secrets)
        let resolvedConversationID = try await ensureConversationID(
            existingConversationID: conversationID,
            seedItems: seedItems,
            configuration: configuration
        )
        let preparedAttachments = try await prepareAttachments(
            captures: captures,
            existingAssets: existingAssets,
            configuration: configuration
        )
        let input = makeInputMessages(
            prompt: prompt,
            attachmentContent: preparedAttachments.content
        )
        let body = CreateResponseRequest(
            model: modelID,
            instructions: instructionsText,
            input: input,
            reasoning: reasoningOptions(for: modelID, mode: modelMode),
            conversation: resolvedConversationID,
            contextManagement: responseContextManagement(for: modelID),
            store: true
        )
        let request = try makeJSONRequest(
            path: "/responses",
            configuration: configuration,
            useAdminKey: false,
            method: "POST",
            body: try encoder.encode(body)
        )
        let response: OpenAIResponsesEnvelope = try await performRequest(request, as: OpenAIResponsesEnvelope.self)
        let outputText = response.outputText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !outputText.isEmpty else {
            throw OpenAIServiceError.emptyResponse
        }

        return OpenAIGeneratedResponse(
            id: response.id,
            conversationID: resolvedConversationID,
            text: outputText,
            assistantItemID: response.assistantMessageID,
            assets: preparedAttachments.assets
        )
    }

    func ensureConversationID(
        existingConversationID: String?,
        seedItems: [OpenAIConversationSeedItem],
        record: ProviderAccountRecord,
        secrets: ProviderAccountLocalSecrets
    ) async throws -> String {
        let configuration = try makeConfiguration(record: record, secrets: secrets)
        return try await ensureConversationID(
            existingConversationID: existingConversationID,
            seedItems: seedItems,
            configuration: configuration
        )
    }

    func appendConversationItems(
        conversationID: String,
        items: [OpenAIConversationSeedItem],
        record: ProviderAccountRecord,
        secrets: ProviderAccountLocalSecrets
    ) async throws -> [String] {
        let configuration = try makeConfiguration(record: record, secrets: secrets)
        return try await appendConversationItems(
            conversationID: conversationID,
            items: items,
            configuration: configuration
        )
    }

    func realtimeSessionCredentials(
        record: ProviderAccountRecord,
        secrets: ProviderAccountLocalSecrets,
        preferredStoredValue: String = "",
        preferredTranscriptionStoredValue: String = ""
    ) async throws -> OpenAIRealtimeSessionCredentials {
        let configuration = try makeConfiguration(record: record, secrets: secrets)
        let modelIDs = try await listModels(configuration: configuration)
        let realtimeModelID = try resolveRealtimeModelID(
            from: modelIDs,
            preferredStoredValue: preferredStoredValue
        )
        let transcriptionModelID = resolveRealtimeTranscriptionModelID(
            from: modelIDs,
            preferredStoredValue: preferredTranscriptionStoredValue
        )

        return OpenAIRealtimeSessionCredentials(
            apiKey: configuration.apiKey,
            organizationID: configuration.organizationID,
            modelID: realtimeModelID,
            transcriptionModelID: transcriptionModelID,
            instructions: instructionsText
        )
    }

    private func ensureConversationID(
        existingConversationID: String?,
        seedItems: [OpenAIConversationSeedItem],
        configuration: OpenAIAPIConfiguration
    ) async throws -> String {
        if let existingConversationID = normalizeIdentifier(existingConversationID) {
            return existingConversationID
        }

        let conversationItems = try await buildConversationItems(
            from: seedItems,
            configuration: configuration
        )
        let metadata = [
            "source": "hush",
            "mode": "multimodal_session",
        ]
        let body = CreateConversationRequest(
            metadata: metadata,
            items: conversationItems
        )
        let request = try makeJSONRequest(
            path: "/conversations",
            configuration: configuration,
            useAdminKey: false,
            method: "POST",
            body: try encoder.encode(body)
        )
        let response: ConversationResource = try await performRequest(request, as: ConversationResource.self)
        guard let conversationID = normalizeIdentifier(response.id) else {
            throw OpenAIServiceError.invalidResponse
        }
        return conversationID
    }

    private func appendConversationItems(
        conversationID: String,
        items: [OpenAIConversationSeedItem],
        configuration: OpenAIAPIConfiguration
    ) async throws -> [String] {
        let normalizedConversationID = normalizeIdentifier(conversationID)
        guard let normalizedConversationID else {
            throw OpenAIServiceError.invalidRequest
        }
        guard !items.isEmpty else { return [] }

        let conversationItems = try await buildConversationItems(
            from: items,
            configuration: configuration
        )
        let body = ConversationItemsAppendRequest(items: conversationItems)
        let request = try makeJSONRequest(
            path: "/conversations/\(normalizedConversationID)/items",
            configuration: configuration,
            useAdminKey: false,
            method: "POST",
            body: try encoder.encode(body)
        )
        let responseData = try await performRawRequest(request)
        return extractConversationItemIDs(from: responseData)
    }

    private func prepareAttachments(
        captures: [OverlayCapture],
        existingAssets: [AttachmentAssetRecord],
        configuration: OpenAIAPIConfiguration
    ) async throws -> PreparedAttachmentTurn {
        guard !captures.isEmpty else {
            return PreparedAttachmentTurn(assets: [], content: [])
        }

        var preparedAssets: [AttachmentAssetRecord] = []
        var content: [ResponseInputContent] = []

        for capture in captures {
            let preparedAttachment = try await prepareAttachment(
                capture: capture,
                existingAssets: existingAssets,
                configuration: configuration
            )
            preparedAssets.append(contentsOf: preparedAttachment.assets)
            content.append(contentsOf: preparedAttachment.content)
        }

        return PreparedAttachmentTurn(
            assets: preparedAssets,
            content: content
        )
    }

    private func prepareAttachment(
        capture: OverlayCapture,
        existingAssets: [AttachmentAssetRecord],
        configuration: OpenAIAPIConfiguration
    ) async throws -> PreparedAttachmentTurn {
        let previewPNGData = pngData(for: capture.image)
        let bookmarkData = capture.fileURL.flatMap { try? $0.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        let localFilePath = capture.fileURL?.path
        let mimeType = capture.fileURL.flatMap(mimeType(for:)) ?? "image/png"
        let fileData = capture.fileURL.flatMap { try? Data(contentsOf: $0) }
        let sha256 = fileData.map(sha256Hex(for:))
        let fileSizeBytes = fileData?.count
        let digest = digestText(for: capture, data: fileData)

        let matchingAsset = existingAssets.first(where: { asset in
            if let sha256, !sha256.isEmpty, sha256 == asset.sha256 {
                return true
            }

            if let localFilePath,
               !localFilePath.isEmpty,
               localFilePath == asset.localFilePath,
               asset.source == capture.source {
                return true
            }

            return false
        })

        var asset = AttachmentAssetRecord(
            id: matchingAsset?.id ?? UUID(),
            title: capture.title,
            subtitle: capture.subtitle,
            source: capture.source,
            bookmarkData: bookmarkData ?? matchingAsset?.bookmarkData,
            localFilePath: localFilePath ?? matchingAsset?.localFilePath,
            mimeType: mimeType,
            fileSizeBytes: fileSizeBytes ?? matchingAsset?.fileSizeBytes,
            sha256: sha256 ?? matchingAsset?.sha256,
            previewPNGData: previewPNGData ?? matchingAsset?.previewPNGData,
            extractedTextDigest: digest.extractedDigest ?? matchingAsset?.extractedTextDigest,
            degradedSummary: digest.degradedSummary ?? matchingAsset?.degradedSummary,
            openAIFileID: matchingAsset?.openAIFileID,
            uploadStatus: matchingAsset?.uploadStatus ?? .notRequired,
            lastError: matchingAsset?.lastError,
            createdAt: matchingAsset?.createdAt ?? Date(),
            updatedAt: Date()
        )

        switch capture.source {
        case .screenshot, .photo:
            let imageDataURL = dataURL(for: capture, fallbackPNGData: previewPNGData)
            let imageContent = imageDataURL.map { [ResponseInputContent.image($0)] } ?? [ResponseInputContent.text("Attached image context: \(capture.title).")]
            asset.uploadStatus = .notRequired
            return PreparedAttachmentTurn(
                assets: [asset],
                content: imageContent
            )

        case .file:
            if let reusedFileID = normalizeIdentifier(asset.openAIFileID) {
                asset.openAIFileID = reusedFileID
                asset.uploadStatus = .uploaded
                return PreparedAttachmentTurn(
                    assets: [asset],
                    content: [.fileID(reusedFileID)]
                )
            }

            guard let fileURL = asset.resolvedLocalURL ?? capture.fileURL else {
                asset.uploadStatus = .failed
                asset.lastError = "Attachment path is no longer available."
                return PreparedAttachmentTurn(
                    assets: [asset],
                    content: [.text(asset.degradedSummary ?? "Attached file: \(capture.title).")]
                )
            }

            if supportsDirectFileInput(fileURL),
               let uploadedFile = try? await uploadUserFile(at: fileURL, configuration: configuration) {
                asset.openAIFileID = uploadedFile.id
                asset.uploadStatus = .uploaded
                asset.lastError = nil
                return PreparedAttachmentTurn(
                    assets: [asset],
                    content: [.fileID(uploadedFile.id)]
                )
            }

            if supportsDirectFileInput(fileURL) {
                asset.uploadStatus = .failed
                asset.lastError = "OpenAI file upload failed. HUSH sent a degraded text digest instead."
            } else {
                asset.uploadStatus = .notRequired
            }

            let degradedText = asset.extractedTextDigest ?? asset.degradedSummary ?? "Attached file: \(capture.title)."
            return PreparedAttachmentTurn(
                assets: [asset],
                content: [.text(degradedText)]
            )
        }
    }

    private func buildConversationItems(
        from seedItems: [OpenAIConversationSeedItem],
        configuration: OpenAIAPIConfiguration
    ) async throws -> [ConversationAPIItem] {
        var items: [ConversationAPIItem] = []
        items.reserveCapacity(seedItems.count)

        for seedItem in seedItems {
            let contentPayload = try await makeConversationContentPayload(
                for: seedItem,
                configuration: configuration
            )

            guard contentPayload.isEmpty == false else { continue }

            items.append(
                ConversationAPIItem(
                    role: seedItem.role.rawValue,
                    content: contentPayload
                )
            )
        }

        return items
    }

    private func makeConversationContentPayload(
        for seedItem: OpenAIConversationSeedItem,
        configuration: OpenAIAPIConfiguration
    ) async throws -> ConversationContentPayload {
        var parts: [ResponseInputContent] = []
        parts.reserveCapacity(seedItem.contents.count)

        for content in seedItem.contents {
            switch content {
            case let .inputText(text):
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    parts.append(.text(normalized))
                }
            case let .outputText(text):
                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    parts.append(.outputText(normalized))
                }
            case let .imageAsset(asset):
                if let imageDataURL = dataURL(for: asset) {
                    parts.append(.image(imageDataURL))
                } else if let fallbackText = asset.degradedSummary ?? asset.extractedTextDigest {
                    parts.append(.text(fallbackText))
                }
            case let .fileAsset(asset):
                if let fileID = normalizeIdentifier(asset.openAIFileID) {
                    parts.append(.fileID(fileID))
                } else if let fileURL = asset.resolvedLocalURL,
                          supportsDirectFileInput(fileURL),
                          let uploadedFile = try? await uploadUserFile(at: fileURL, configuration: configuration) {
                    parts.append(.fileID(uploadedFile.id))
                } else if let digest = asset.extractedTextDigest ?? asset.degradedSummary {
                    parts.append(.text(digest))
                }
            }
        }

        guard !parts.isEmpty else { return .parts([]) }

        let plainTexts = parts.compactMap { part -> String? in
            switch part {
            case let .text(text):
                return text
            case let .outputText(text):
                return text
            case .image, .fileID, .fileURL:
                return nil
            }
        }

        if plainTexts.count == parts.count {
            return .string(plainTexts.joined(separator: "\n\n"))
        }

        return .parts(parts)
    }

    private func uploadUserFile(
        at fileURL: URL,
        configuration: OpenAIAPIConfiguration
    ) async throws -> OpenAIFileResource {
        let fileSize = ((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard fileSize > 0, fileSize <= 50_000_000 else {
            throw OpenAIServiceError.requestFailed(
                "Files larger than 50 MB fall back to a degraded text digest in HUSH."
            )
        }

        let request = try makeMultipartFileUploadRequest(
            path: "/files",
            configuration: configuration,
            useAdminKey: false,
            purpose: "user_data",
            fileURL: fileURL
        )
        return try await performRequest(request, as: OpenAIFileResource.self)
    }

    private func makeInputMessages(
        prompt: String,
        attachmentContent: [ResponseInputContent]
    ) -> [ResponseInputMessage] {
        var content: [ResponseInputContent] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptText = trimmedPrompt.isEmpty
            ? "Analyze the attached context and provide a concise answer with actionable next steps."
            : trimmedPrompt

        content.append(.text(promptText))
        content.append(contentsOf: attachmentContent)

        return [ResponseInputMessage(role: "user", content: content)]
    }

    private func dataURL(for capture: OverlayCapture, fallbackPNGData: Data?) -> String? {
        if let fileURL = capture.fileURL,
           isImageURL(fileURL),
           let data = try? Data(contentsOf: fileURL) {
            return "data:\(mimeType(for: fileURL));base64,\(data.base64EncodedString())"
        }

        guard let pngData = fallbackPNGData ?? pngData(for: capture.image) else {
            return nil
        }

        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }

    private func dataURL(for asset: AttachmentAssetRecord) -> String? {
        if let fileURL = asset.resolvedLocalURL,
           isImageURL(fileURL),
           let data = try? Data(contentsOf: fileURL) {
            return "data:\(mimeType(for: fileURL));base64,\(data.base64EncodedString())"
        }

        guard let previewPNGData = asset.previewPNGData else {
            return nil
        }

        return "data:image/png;base64,\(previewPNGData.base64EncodedString())"
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private func digestText(for capture: OverlayCapture, data: Data?) -> (extractedDigest: String?, degradedSummary: String?) {
        guard let fileURL = capture.fileURL else {
            return (nil, nil)
        }

        let fileName = fileURL.lastPathComponent
        let extensionLabel = fileURL.pathExtension.isEmpty ? "file" : fileURL.pathExtension.uppercased()

        if fileURL.pathExtension.lowercased() == "pdf",
           let document = PDFDocument(url: fileURL) {
            let text = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                return (
                    extractedDigest: "Attached PDF \(fileName):\n\(text.prefix(12_000))",
                    degradedSummary: nil
                )
            }
        }

        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "json", "jsonl", "csv", "log", "swift", "js", "ts", "jsx", "tsx",
            "py", "rb", "java", "go", "xml", "yaml", "yml", "html", "htm", "css", "scss", "sql",
            "sh", "zsh", "bash", "kt", "m", "mm", "c", "cc", "cpp", "h", "hpp", "rs", "php", "rtf"
        ]

        if textExtensions.contains(fileURL.pathExtension.lowercased()),
           let data,
           let text = String(data: Data(data.prefix(48_000)), encoding: .utf8) {
            let excerpt = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !excerpt.isEmpty {
                return (
                    extractedDigest: "Attached \(extensionLabel) file \(fileName):\n\(excerpt.prefix(12_000))",
                    degradedSummary: nil
                )
            }
        }

        return (
            extractedDigest: nil,
            degradedSummary: "Attached \(extensionLabel) file: \(fileName)."
        )
    }

    private func supportsDirectFileInput(_ url: URL) -> Bool {
        let supportedExtensions: Set<String> = [
            "pdf", "txt", "md", "markdown", "json", "jsonl", "csv", "log", "swift", "js", "ts", "jsx", "tsx",
            "py", "rb", "java", "go", "xml", "yaml", "yml", "html", "htm", "css", "scss", "sql", "rtf",
            "doc", "docx", "ppt", "pptx", "xls", "xlsx", "c", "cc", "cpp", "h", "hpp", "m", "mm", "kt",
            "rs", "php", "sh", "zsh", "bash"
        ]

        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func isImageURL(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension),
           let mimeType = utType.preferredMIMEType {
            return mimeType
        }

        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic", "heif":
            return "image/heic"
        case "bmp":
            return "image/bmp"
        case "tif", "tiff":
            return "image/tiff"
        case "pdf":
            return "application/pdf"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        case "md", "markdown":
            return "text/markdown"
        case "txt", "log", "swift", "js", "ts", "py", "rb", "java", "go", "xml", "yaml", "yml", "html", "htm", "css", "scss", "sql":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }

    private func sha256Hex(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeStatusSummary(
        record: ProviderAccountRecord,
        configuration: OpenAIAPIConfiguration,
        modelCount: Int
    ) async -> ProviderAccountStatusSummary {
        var segments = ["\(modelCount) model\(modelCount == 1 ? "" : "s") available"]
        let baseUsageSnapshot = makeUsageSnapshot(
            modelCount: modelCount,
            usage: nil,
            record: record,
            hasAdminKey: !configuration.adminKey.isEmpty
        )

        if !record.organizationID.isEmpty {
            segments.append("Org \(shortIdentifier(record.organizationID))")
        }

        if !record.projectID.isEmpty {
            segments.append("Project \(shortIdentifier(record.projectID))")
        }

        guard !configuration.adminKey.isEmpty else {
            segments.append("Add an admin key to see usage and costs")
            return .limited(detail: segments.joined(separator: " · "), usage: baseUsageSnapshot)
        }

        do {
            let usage = try await fetchUsageSummary(record: record, configuration: configuration)
            if let spendText = usage.spendText {
                segments.append("7d spend \(spendText)")
            }
            if let requestText = usage.requestText {
                segments.append(requestText)
            }
            return .connected(
                detail: segments.joined(separator: " · "),
                usage: makeUsageSnapshot(
                    modelCount: modelCount,
                    usage: usage,
                    record: record,
                    hasAdminKey: true
                )
            )
        } catch {
            segments.append("Admin usage lookup unavailable: \(error.localizedDescription)")
            return .limited(detail: segments.joined(separator: " · "), usage: baseUsageSnapshot)
        }
    }

    private func listModels(configuration: OpenAIAPIConfiguration) async throws -> [String] {
        let request = try makeJSONRequest(
            path: "/models",
            configuration: configuration,
            useAdminKey: false
        )
        let response: OpenAIModelsEnvelope = try await performRequest(request, as: OpenAIModelsEnvelope.self)
        return response.data.map(\.id)
    }

    private func fetchUsageSummary(
        record: ProviderAccountRecord,
        configuration: OpenAIAPIConfiguration
    ) async throws -> OpenAIUsageSummary {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date().addingTimeInterval(-604_800)
        let startTime = Int(sevenDaysAgo.timeIntervalSince1970)
        let projectIDs = record.projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [record.projectID.trimmingCharacters(in: .whitespacesAndNewlines)]

        var costQueryItems = [URLQueryItem(name: "start_time", value: "\(startTime)")]
        costQueryItems.append(contentsOf: queryItems(named: "project_ids", values: projectIDs))

        var usageQueryItems = [
            URLQueryItem(name: "start_time", value: "\(startTime)"),
            URLQueryItem(name: "group_by", value: "model"),
        ]
        usageQueryItems.append(contentsOf: queryItems(named: "project_ids", values: projectIDs))

        let costsRequest = try makeJSONRequest(
            path: "/organization/costs",
            configuration: configuration,
            useAdminKey: true,
            queryItems: costQueryItems
        )
        let costsResponse: OpenAIUsagePage<OpenAICostResult> = try await performRequest(costsRequest, as: OpenAIUsagePage<OpenAICostResult>.self)

        let usageRequest = try makeJSONRequest(
            path: "/organization/usage/completions",
            configuration: configuration,
            useAdminKey: true,
            queryItems: usageQueryItems
        )
        let usageResponse: OpenAIUsagePage<OpenAICompletionUsageResult> = try await performRequest(usageRequest, as: OpenAIUsagePage<OpenAICompletionUsageResult>.self)

        let totalCost = costsResponse.data
            .flatMap(\.results)
            .compactMap(\.amount?.value)
            .reduce(Decimal.zero, +)

        let requestCount = usageResponse.data
            .flatMap(\.results)
            .reduce(0) { $0 + $1.numModelRequests }
        let inputTokens = usageResponse.data
            .flatMap(\.results)
            .reduce(0) { $0 + $1.inputTokens }
        let outputTokens = usageResponse.data
            .flatMap(\.results)
            .reduce(0) { $0 + $1.outputTokens }

        return OpenAIUsageSummary(
            spendUSD: totalCost,
            requestCount: requestCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    private func makeConfiguration(
        record: ProviderAccountRecord,
        secrets: ProviderAccountLocalSecrets
    ) throws -> OpenAIAPIConfiguration {
        let apiKey = secrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        return OpenAIAPIConfiguration(
            apiKey: apiKey,
            adminKey: secrets.adminKey.trimmingCharacters(in: .whitespacesAndNewlines),
            organizationID: record.organizationID.trimmingCharacters(in: .whitespacesAndNewlines),
            projectID: record.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func makeJSONRequest(
        path: String,
        configuration: OpenAIAPIConfiguration,
        useAdminKey: Bool,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        var request = try baseRequest(
            path: path,
            configuration: configuration,
            useAdminKey: useAdminKey,
            method: method,
            queryItems: queryItems
        )
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body
        return request
    }

    private func makeMultipartFileUploadRequest(
        path: String,
        configuration: OpenAIAPIConfiguration,
        useAdminKey: Bool,
        purpose: String,
        fileURL: URL
    ) throws -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try baseRequest(
            path: path,
            configuration: configuration,
            useAdminKey: useAdminKey,
            method: "POST"
        )
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(
            boundary: boundary,
            purpose: purpose,
            fileURL: fileURL
        )
        return request
    }

    private func baseRequest(
        path: String,
        configuration: OpenAIAPIConfiguration,
        useAdminKey: Bool,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(string: "https://api.openai.com/v1\(path)") else {
            throw OpenAIServiceError.invalidRequest
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw OpenAIServiceError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue(
            "Bearer \(useAdminKey ? configuration.adminKey : configuration.apiKey)",
            forHTTPHeaderField: "Authorization"
        )

        if !configuration.organizationID.isEmpty {
            request.setValue(configuration.organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }

        if !configuration.projectID.isEmpty {
            request.setValue(configuration.projectID, forHTTPHeaderField: "OpenAI-Project")
        }

        return request
    }

    private func multipartBody(
        boundary: String,
        purpose: String,
        fileURL: URL
    ) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL)

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        body.append("\(purpose)\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func performRawRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? decoder.decode(OpenAIErrorEnvelope.self, from: data) {
                throw OpenAIServiceError.requestFailed(apiError.error.message)
            }

            let fallbackMessage = String(data: data, encoding: .utf8) ?? "OpenAI request failed with status \(httpResponse.statusCode)."
            throw OpenAIServiceError.requestFailed(fallbackMessage)
        }

        return data
    }

    private func performRequest<Response: Decodable>(
        _ request: URLRequest,
        as responseType: Response.Type
    ) async throws -> Response {
        let data = try await performRawRequest(request)

        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw OpenAIServiceError.invalidResponse
        }
    }

    private func extractConversationItemIDs(from data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let dictionary = root as? [String: Any] {
            if let items = dictionary["items"] as? [[String: Any]] {
                return items.compactMap { $0["id"] as? String }
            }

            if let dataItems = dictionary["data"] as? [[String: Any]] {
                return dataItems.compactMap { $0["id"] as? String }
            }

            if let id = dictionary["id"] as? String {
                return [id]
            }
        }

        if let array = root as? [[String: Any]] {
            return array.compactMap { $0["id"] as? String }
        }

        return []
    }

    private func normalizeIdentifier(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolveRealtimeModelID(
        from modelIDs: [String],
        preferredStoredValue: String
    ) throws -> String {
        let availableModelIDs = Set(modelIDs)

        if let decodedPreferred = AssistantModelCatalog.decodeStorageValue(preferredStoredValue),
           decodedPreferred.providerID == .openAI,
           availableModelIDs.contains(decodedPreferred.modelID),
           AssistantModelCatalog.openAIRealtimeModelOptions(from: [decodedPreferred.modelID]).isEmpty == false {
            return decodedPreferred.modelID
        }

        let fallbackOptions = AssistantModelCatalog.openAIRealtimeModelOptions(from: modelIDs)
        if let resolvedModelID = fallbackOptions
            .first(where: { !isDeprecatedRealtimePreviewModelID($0.modelID) })?
            .modelID {
            return resolvedModelID
        }

        throw OpenAIServiceError.requestFailed(
            "This OpenAI account does not expose a supported Realtime model for Live mode."
        )
    }

    private func resolveRealtimeTranscriptionModelID(
        from modelIDs: [String],
        preferredStoredValue: String
    ) -> String {
        let availableModelIDs = Set(modelIDs)

        if let decodedPreferred = AssistantModelCatalog.decodeStorageValue(preferredStoredValue),
           decodedPreferred.providerID == .openAI,
           AssistantModelCatalog.openAIRealtimeTranscriptionModelOptions(
               from: [decodedPreferred.modelID]
           ).isEmpty == false,
           availableModelIDs.contains(decodedPreferred.modelID) || modelIDs.isEmpty {
            return decodedPreferred.modelID
        }

        if let resolvedModelID = AssistantModelCatalog.openAIRealtimeTranscriptionModelOptions(from: modelIDs)
            .first?
            .modelID {
            return resolvedModelID
        }

        return AssistantModelCatalog.defaultRealtimeTranscriptionModels(for: .openAI)
            .first?
            .modelID
            ?? "gpt-4o-mini-transcribe"
    }

    private func queryItems(named name: String, values: [String]) -> [URLQueryItem] {
        values.map { URLQueryItem(name: name, value: $0) }
    }

    private func isDeprecatedRealtimePreviewModelID(_ modelID: String) -> Bool {
        modelID.lowercased().contains("preview")
    }

    private func shortIdentifier(_ value: String) -> String {
        guard value.count > 14 else { return value }
        return "\(value.prefix(8))...\(value.suffix(4))"
    }

    private func makeUsageSnapshot(
        modelCount: Int,
        usage: OpenAIUsageSummary?,
        record: ProviderAccountRecord,
        hasAdminKey: Bool
    ) -> ProviderAccountUsageSnapshot {
        ProviderAccountUsageSnapshot(
            modelCount: modelCount,
            spendText: usage?.spendText,
            requestCount: usage?.requestCount,
            inputTokens: usage?.inputTokens,
            outputTokens: usage?.outputTokens,
            organizationSummary: record.organizationID.isEmpty ? nil : shortIdentifier(record.organizationID),
            projectSummary: record.projectID.isEmpty ? nil : shortIdentifier(record.projectID),
            hasAdminKey: hasAdminKey
        )
    }

    private func reasoningOptions(for modelID: String, mode: AssistantModelMode) -> ResponseReasoningOptions? {
        let lower = modelID.lowercased()
        let supportsReasoning = lower.hasPrefix("gpt-5")
            || lower.hasPrefix("o1")
            || lower.hasPrefix("o3")
            || lower.hasPrefix("o4")

        guard supportsReasoning else {
            return nil
        }

        let effort: String
        switch mode {
        case .fast:
            effort = "minimal"
        case .advanced:
            effort = "medium"
        case .defaultMode:
            effort = "low"
        }

        return ResponseReasoningOptions(effort: effort)
    }

    private func compactionThreshold(for modelID: String) -> Int {
        let lower = modelID.lowercased()
        if lower.hasPrefix("gpt-5.4") || lower.hasPrefix("gpt-5") {
            return 80_000
        }
        if lower.hasPrefix("gpt-4.1") {
            return 48_000
        }
        return 32_000
    }

    private func responseContextManagement(for modelID: String) -> [ResponseContextManagementEntry] {
        [
            .compaction(threshold: compactionThreshold(for: modelID)),
        ]
    }

    private var instructionsText: String {
        AssistantPromptPresetCatalog.effectiveInstructions()
    }
}

private struct OpenAIUsageSummary {
    let spendUSD: Decimal
    let requestCount: Int
    let inputTokens: Int
    let outputTokens: Int

    var spendText: String? {
        guard spendUSD > 0 else { return "$0.00" }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: spendUSD as NSDecimalNumber)
    }

    var requestText: String? {
        guard requestCount > 0 else { return "No recent completions usage" }
        return "\(requestCount) request\(requestCount == 1 ? "" : "s")"
    }
}

private struct OpenAIModelsEnvelope: Decodable {
    let data: [OpenAIModelItem]
}

private struct OpenAIModelItem: Decodable {
    let id: String
}

private struct OpenAIUsagePage<Result: Decodable>: Decodable {
    let data: [OpenAIUsageBucket<Result>]
}

private struct OpenAIUsageBucket<Result: Decodable>: Decodable {
    let results: [Result]
}

private struct OpenAICostResult: Decodable {
    let amount: OpenAICurrencyAmount?
}

private struct OpenAICurrencyAmount: Decodable {
    let value: Decimal
}

private struct OpenAICompletionUsageResult: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let numModelRequests: Int
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIErrorPayload
}

private struct OpenAIErrorPayload: Decodable {
    let message: String
}

private struct CreateConversationRequest: Encodable {
    let metadata: [String: String]
    let items: [ConversationAPIItem]
}

private struct ConversationItemsAppendRequest: Encodable {
    let items: [ConversationAPIItem]
}

private struct ConversationAPIItem: Encodable {
    let type = "message"
    let role: String
    let content: ConversationContentPayload

    init(role: String, content: ConversationContentPayload) {
        self.role = role
        self.content = content
    }
}

private enum ConversationContentPayload: Encodable {
    case string(String)
    case parts([ResponseInputContent])

    var isEmpty: Bool {
        switch self {
        case let .string(text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .parts(parts):
            return parts.isEmpty
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .string(text):
            var singleValueContainer = encoder.singleValueContainer()
            try singleValueContainer.encode(text)
        case let .parts(parts):
            var singleValueContainer = encoder.singleValueContainer()
            try singleValueContainer.encode(parts)
        }
    }
}

private struct ConversationResource: Decodable {
    let id: String
}

private struct OpenAIFileResource: Decodable {
    let id: String
    let filename: String?
}

private struct CreateResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: [ResponseInputMessage]
    let reasoning: ResponseReasoningOptions?
    let conversation: String
    let contextManagement: [ResponseContextManagementEntry]?
    let store: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case reasoning
        case conversation
        case contextManagement = "context_management"
        case store
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encode(conversation, forKey: .conversation)
        try container.encodeIfPresent(contextManagement, forKey: .contextManagement)
        try container.encode(store, forKey: .store)
    }
}

private struct ResponseContextManagementEntry: Encodable {
    let type: String
    let compactThreshold: Int?

    static func compaction(threshold: Int) -> Self {
        Self(type: "compaction", compactThreshold: threshold)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case compactThreshold = "compact_threshold"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(compactThreshold, forKey: .compactThreshold)
    }
}

private struct ResponseReasoningOptions: Encodable {
    let effort: String
}

private struct ResponseInputMessage: Encodable {
    let role: String
    let content: [ResponseInputContent]
}

private enum ResponseInputContent: Encodable {
    case text(String)
    case outputText(String)
    case image(String)
    case fileID(String)
    case fileURL(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .outputText(text):
            try container.encode("output_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(imageURL):
            try container.encode("input_image", forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        case let .fileID(fileID):
            try container.encode("input_file", forKey: .type)
            try container.encode(fileID, forKey: .fileID)
        case let .fileURL(fileURL):
            try container.encode("input_file", forKey: .type)
            try container.encode(fileURL, forKey: .fileURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
        case fileID = "file_id"
        case fileURL = "file_url"
    }
}

private struct OpenAIResponsesEnvelope: Decodable {
    let id: String
    let output: [OpenAIOutputItem]

    var outputText: String {
        output
            .flatMap { item in
                (item.content ?? []).compactMap { content in
                    content.type == "output_text" ? content.text : nil
                }
            }
            .joined()
    }

    var assistantMessageID: String? {
        output.first(where: { $0.type == "message" && $0.role == "assistant" })?.id
    }
}

private struct OpenAIOutputItem: Decodable {
    let id: String?
    let type: String?
    let role: String?
    let content: [OpenAIOutputContent]?
}

private struct OpenAIOutputContent: Decodable {
    let type: String
    let text: String?
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
