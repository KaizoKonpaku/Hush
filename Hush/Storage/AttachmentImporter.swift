import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

actor AttachmentImporter {
    let root: URL
    init(root: URL) { self.root = root }

    func importFile(_ source: URL) async throws -> ChatAttachment {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentTypeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 25 * 1024 * 1024 else {
            throw HushError.message("Attach a regular file smaller than 25 MB.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let type = values.contentType ?? UTType(filenameExtension: source.pathExtension) ?? .data
        if type.conforms(to: .image) { return try await importImage(source) }
        let text: String
        if type.conforms(to: .pdf) {
            guard let document = PDFDocument(url: source), !document.isLocked else {
                throw HushError.message("This PDF is locked or could not be read.")
            }
            guard document.pageCount <= 200 else { throw HushError.message("Attach a PDF with 200 pages or fewer.") }
            text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
        } else if type.conforms(to: .text) || ["md", "json", "csv", "swift", "py", "js", "ts", "log"].contains(source.pathExtension.lowercased()) {
            guard let decoded = String(data: try Data(contentsOf: source), encoding: .utf8) else {
                throw HushError.message("This file is not UTF-8 text.")
            }
            text = decoded
        } else { throw HushError.message("Attach text, Markdown, code, a PDF, or an image.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HushError.message("This file has no readable text. For scanned PDFs, attach an image of the page instead.")
        }
        guard text.count <= 60_000 else { throw HushError.message("This document is too long for an attachment. Select a section of 60,000 characters or fewer.") }
        let name = UUID().uuidString + ".txt"
        try Data(text.utf8).write(to: root.appending(path: name), options: .atomic)
        return ChatAttachment(name: source.lastPathComponent, kind: .text, filename: name, extractedText: text, byteCount: Int64(text.utf8.count))
    }

    private func importImage(_ source: URL) async throws -> ChatAttachment {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1536
              ] as CFDictionary) else { throw HushError.message("This image could not be decoded.") }
        let name = UUID().uuidString + ".jpg"
        let target = root.appending(path: name)
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw HushError.message("The image could not be prepared.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw HushError.message("The image could not be saved.") }
        let request = RecognizeTextRequest()
        let text = try? await request.perform(on: image).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return ChatAttachment(name: source.lastPathComponent, kind: .image, filename: name,
                              extractedText: text.map { String($0.prefix(12_000)) }, byteCount: Int64(size))
    }
}
