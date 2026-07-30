import Foundation
import AppKit

enum CaptureMode: String {
    case full
    case selection
    case window
}

enum CaptureAttemptResult {
    case image(NSImage)
    case cancelled
    case failed
}

enum OverlayCaptureSource: String, Codable, Sendable {
    case screenshot
    case photo
    case file
}

struct OverlayCapture: Identifiable {
    let id = UUID()
    let image: NSImage
    let title: String
    let subtitle: String
    let source: OverlayCaptureSource
    let fileURL: URL?

    init(
        image: NSImage,
        title: String = "Screen Capture",
        subtitle: String = "Capture",
        source: OverlayCaptureSource = .screenshot,
        fileURL: URL? = nil
    ) {
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.fileURL = fileURL
    }

    var usesImageFill: Bool {
        source != .file
    }
}

struct OverlayProcessEntry: Identifiable {
    let id: UUID
    let prompt: String
    let captures: [OverlayCapture]
    let captureCount: Int
    let createdAt: Date
    var response: String?
    var errorMessage: String? = nil
    var isProcessing: Bool
    var openAIResponseID: String?

    init(
        id: UUID = UUID(),
        prompt: String,
        captures: [OverlayCapture],
        captureCount: Int? = nil,
        createdAt: Date,
        response: String? = nil,
        errorMessage: String? = nil,
        isProcessing: Bool,
        openAIResponseID: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.captures = captures
        self.captureCount = captureCount ?? captures.count
        self.createdAt = createdAt
        self.response = response
        self.errorMessage = errorMessage
        self.isProcessing = isProcessing
        self.openAIResponseID = openAIResponseID
    }
}

enum OverlayProcessEntryState {
    case pending
    case processing
    case completed
    case failed
}

extension OverlayProcessEntry {
    var hasStoredAttachmentSummary: Bool {
        captureCount > captures.count
    }

    var storedAttachmentCount: Int {
        max(0, captureCount - captures.count)
    }

    var normalizedPrompt: String {
        prompt
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    var normalizedResponse: String {
        (response ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedErrorMessage: String {
        (errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var state: OverlayProcessEntryState {
        if isProcessing {
            return .processing
        }

        if !normalizedErrorMessage.isEmpty {
            return .failed
        }

        if !normalizedResponse.isEmpty {
            return .completed
        }

        return .pending
    }
}

enum OverlayResultScrollCommand: Equatable {
    case top
    case bottom
    case entry(UUID)
}
