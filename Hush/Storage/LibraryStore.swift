import Foundation

struct LibraryArchive: Codable, Sendable {
    var version = 2
    var conversations: [Conversation] = []
    var settings = HushSettings()
}

actor LibraryStore {
    let root: URL
    private var latestRevision = 0

    init(root: URL) { self.root = root }

    static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true)
            .appending(path: "HUSH/LocalWorkspace", directoryHint: .isDirectory)
    }

    func load() throws -> LibraryArchive {
        try prepare()
        let url = root.appending(path: "library.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryArchive() }
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max <= 128 * 1024 * 1024 else {
            throw HushError.message("The library is too large to open safely.")
        }
        let data = try Data(contentsOf: url)
        var archive = try JSONDecoder().decode(LibraryArchive.self, from: data)
        guard archive.version == 2 else { throw HushError.message("This library was created by a different version of Hush. The saved file has not been changed.") }
        archive.settings.validate()
        for index in archive.conversations.indices {
            for messageIndex in archive.conversations[index].messages.indices
            where archive.conversations[index].messages[messageIndex].status == .generating {
                archive.conversations[index].messages[messageIndex].status = .stopped
            }
        }
        return archive
    }

    @discardableResult
    func save(_ archive: LibraryArchive, revision: Int) throws -> Bool {
        try Task.checkCancellation()
        guard revision >= latestRevision else { return false }
        try prepare()
        let url = root.appending(path: "library.json")
        let data = try JSONEncoder().encode(archive)
        // Atomic replacement protects the current library without retaining deleted chat backups.
        try data.write(to: url, options: .atomic)
        latestRevision = revision
        return true
    }

    func removeAttachments(_ filenames: Set<String>) throws {
        for filename in filenames {
            let url = try ModelPath.resolve(filename, under: root.appending(path: "Attachments"))
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    func pruneAttachments(keeping filenames: Set<String>) throws {
        let directory = root.appending(path: "Attachments")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try removeAttachments(Set(files.map(\.lastPathComponent)).subtracting(filenames))
    }

    func installedModels() throws -> [ModelRecord] {
        try prepare()
        let directories = try FileManager.default.contentsOfDirectory(
            at: root.appending(path: "Models"), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return directories.compactMap { directory in
            guard let data = try? Data(contentsOf: directory.appending(path: "hush-model.json")),
                  var model = try? JSONDecoder().decode(ModelRecord.self, from: data),
                  model.engine != .apple else { return nil }
            model.installedDirectory = directory.lastPathComponent
            return model
        }.sorted { ($0.installedAt ?? .distantPast) > ($1.installedAt ?? .distantPast) }
    }

    func removeModel(_ model: ModelRecord) throws {
        guard let directory = model.installedDirectory else { return }
        let url = try ModelPath.resolve(directory, under: root.appending(path: "Models"))
        guard FileManager.default.fileExists(atPath: url.appending(path: "hush-model.json").path) else {
            throw HushError.message("This folder is not a Hush model installation.")
        }
        try FileManager.default.removeItem(at: url)
    }

    private func prepare() throws {
        for name in ["", "Models", "Downloads", "Attachments"] {
            let url = name.isEmpty ? root : root.appending(path: name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        #if !os(tvOS)
        var directory = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        #endif
    }
}
