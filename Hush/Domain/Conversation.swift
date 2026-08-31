import Foundation

struct Conversation: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title = "New conversation"
    var createdAt = Date()
    var updatedAt = Date()
    var isPinned = false
    var modelID = ModelRecord.apple.id
    var messages: [ChatMessage] = []
    var branch: ConversationBranch?

    var searchText: String { ([title] + messages.map(\.text)).joined(separator: "\n") }
    var exportText: String {
        "# \(title)\n\n" + messages.map { message in
            "## \(message.role == .user ? "You" : (message.modelName ?? "Hush"))\n\n\(message.text)"
        }.joined(separator: "\n\n")
    }
}

struct ConversationBranch: Codable, Equatable, Sendable {
    let conversationID: UUID
    let messageID: UUID
}

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    enum Status: String, Codable, Sendable { case complete, generating, stopped, failed }

    var id = UUID()
    var role: Role
    var text: String
    var createdAt = Date()
    var attachments: [ChatAttachment] = []
    var modelName: String?
    var status: Status = .complete
    var metrics: GenerationMetrics?
}

struct ChatAttachment: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case text, image }
    var id = UUID()
    var name: String
    var kind: Kind
    var filename: String
    var extractedText: String?
    var byteCount: Int64
}

enum ConversationContext {
    static func completedTurns(from messages: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        var pendingUser: ChatMessage?
        for message in messages {
            if message.role == .user { pendingUser = message }
            else if let user = pendingUser,
                    message.status == .complete || message.status == .stopped,
                    !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(contentsOf: [user, message])
                pendingUser = nil
            }
        }
        return result
    }
}

struct GenerationMetrics: Codable, Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var cachedTokens = 0
    var timeToFirstToken: Double?
    var duration: Double = 0
    var peakMemoryBytes: Int = 0
    var tokensPerSecond: Double {
        let decodingTime = duration - (timeToFirstToken ?? 0)
        return decodingTime > 0 && outputTokens > 1 ? Double(outputTokens - 1) / decodingTime : 0
    }
}

struct GenerationRequest: Sendable {
    let conversationID: UUID
    let model: ModelRecord
    let modelDirectory: URL?
    let history: [ChatMessage]
    let prompt: String
    let attachments: [ChatAttachment]
    let attachmentDirectory: URL
    let settings: HushSettings
    let memoryBudget: Int
}

enum GenerationEvent: Sendable {
    case status(String)
    case snapshot(String)
    case completed(GenerationMetrics)
}

enum HushError: LocalizedError, Equatable {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

struct HushNotice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}
