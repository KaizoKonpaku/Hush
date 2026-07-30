import AppKit
import Foundation

enum HUSHFileSystem {
    nonisolated static func applicationSupportDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let hushURL = baseURL.appendingPathComponent("HUSH", isDirectory: true)
        try ensureDirectoryExists(at: hushURL)
        return hushURL
    }

    nonisolated static func fallbackApplicationSupportDirectory() -> URL {
        let fallbackURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/HUSH", isDirectory: true)
        try? ensureDirectoryExists(at: fallbackURL)
        return fallbackURL
    }

    nonisolated static func archivesDirectory() throws -> URL {
        let url = try applicationSupportDirectory()
            .appendingPathComponent("Archives", isDirectory: true)
        try ensureDirectoryExists(at: url)
        return url
    }

    nonisolated static func modelsDirectory() throws -> URL {
        let url = try applicationSupportDirectory()
            .appendingPathComponent("Models", isDirectory: true)
        try ensureDirectoryExists(at: url)
        return url
    }

    nonisolated static func ensureDirectoryExists(at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    nonisolated static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    nonisolated static func isEmptyDirectory(at url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return false
        }

        return contents.isEmpty
    }

    nonisolated static func isExternalVolumePath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let standardizedPath = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        return standardizedPath.hasPrefix("/Volumes/")
    }
}

@MainActor
enum HUSHFileSystemUI {
    static func chooseDirectory(startingAt url: URL, prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = prompt

        if FileManager.default.fileExists(atPath: url.path) {
            panel.directoryURL = url
        } else {
            panel.directoryURL = url.deletingLastPathComponent()
        }

        guard panel.runModal() == .OK else { return nil }
        return panel.urls.first
    }

    static func revealInFinder(_ url: URL) {
        try? HUSHFileSystem.ensureDirectoryExists(at: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
