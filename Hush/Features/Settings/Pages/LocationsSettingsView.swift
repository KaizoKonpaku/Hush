import SwiftUI

extension MainWindowView {
    var locationsSettings: some View {
        LocationsSettingsPage(accentColor: themesAccentColor)
            .settingsPageLayout()
    }
}

private enum StorageLocationMode: String, CaseIterable, Identifiable {
    case systemDefault = "default"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemDefault:
            return "Default"
        case .custom:
            return "Custom"
        }
    }
}

private enum StorageLocationTarget: String, CaseIterable, Identifiable {
    case sessions
    case archives

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions:
            return "Sessions"
        case .archives:
            return "Archives"
        }
    }
}

private enum LocationsSheetTarget: Hashable, Identifiable {
    case storage(StorageLocationTarget)
    case model(String)

    var id: String {
        switch self {
        case let .storage(target):
            return "storage-\(target.rawValue)"
        case let .model(key):
            return "model-\(key)"
        }
    }
}

private struct ModelLocationEntry: Identifiable, Equatable {
    let key: String
    let title: String
    let defaultPath: String
    let currentPath: String

    var id: String { key }

    var mode: StorageLocationMode {
        currentPath == defaultPath ? .systemDefault : .custom
    }
}

private struct InstalledModelCatalogEntry: Decodable {
    let displayName: String
    let modelID: String
    let repositoryID: String?
}

private struct LocationsSettingsPage: View {
    let accentColor: Color

    @AppStorage("locations.storage.sessions.mode") private var sessionsModeRaw = StorageLocationMode.systemDefault.rawValue
    @AppStorage("locations.storage.sessions.customPath") private var sessionsCustomPath = ""
    @AppStorage("locations.storage.archives.mode") private var archivesModeRaw = StorageLocationMode.systemDefault.rawValue
    @AppStorage("locations.storage.archives.customPath") private var archivesCustomPath = ""
    @AppStorage("locations.storage.models.customPaths") private var modelCustomPathsStorage = ""
    @AppStorage("locations.storage.allowExternalDrives") private var allowExternalDrives = false

    @State private var editingTarget: LocationsSheetTarget?
    @State private var installedModels: [ModelLocationEntry] = []
    @State private var modelCustomPaths: [String: String] = [:]
    @State private var draftModelModes: [String: StorageLocationMode] = [:]
    @State private var hasLoadedState = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isShowingAlert = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Allow External Drives", isOn: $allowExternalDrives)
                    Text("Lets custom storage locations live on removable volumes mounted in /Volumes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("External Drives")
            }

            Section {
                ForEach(StorageLocationTarget.allCases) { target in
                    StorageLocationRow(
                        title: target.title,
                        path: resolvedPath(for: target),
                        statusTitle: statusTitle(for: target),
                        statusColor: statusColor(for: target),
                        accentColor: accentColor,
                        onRevealPath: { revealPathInFinder(resolvedPath(for: target)) },
                        onShowDetails: { editingTarget = .storage(target) }
                    )
                }
            } header: {
                Text("Storage")
            } footer: {
                if let warningMessage = externalDriveWarningMessage {
                    Text(warningMessage)
                } else {
                    Text("Use the info button to switch between the default folder and a custom location.")
                }
            }

            Section {
                if installedModels.isEmpty {
                    Text("No downloaded models found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(installedModels) { model in
                        StorageLocationRow(
                            title: model.title,
                            path: model.currentPath,
                            statusTitle: modelStatusTitle(for: model),
                            statusColor: modelStatusColor(for: model),
                            accentColor: accentColor,
                            onRevealPath: { revealPathInFinder(model.currentPath) },
                            onShowDetails: { editingTarget = .model(model.key) }
                        )
                    }
                }
            } header: {
                Text("Models")
            } footer: {
                Text("Each downloaded model can stay in the default Models folder or be moved to its own custom location.")
            }
        }
        .sheet(item: $editingTarget, onDismiss: {
            draftModelModes.removeAll()
        }) { target in
            locationSheet(for: target)
        }
        .alert(alertTitle, isPresented: $isShowingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            loadStateIfNeeded()
        }
        .settingsPageLayout()
    }

    @ViewBuilder
    private func locationSheet(for target: LocationsSheetTarget) -> some View {
        switch target {
        case let .storage(storageTarget):
            LocationOptionsSheet(
                title: "\(storageTarget.title) Location",
                mode: storageModeBinding(for: storageTarget),
                accentColor: accentColor,
                displayedPath: displayedCustomPath(for: storageTarget),
                defaultPath: defaultPath(for: storageTarget),
                onChooseFolder: { chooseDirectory(for: storageTarget) }
            )
        case let .model(modelKey):
            LocationOptionsSheet(
                title: "\(modelTitle(for: modelKey)) Location",
                mode: modelModeBinding(for: modelKey),
                accentColor: accentColor,
                displayedPath: modelDisplayedCustomPath(for: modelKey),
                defaultPath: defaultModelPath(for: modelKey),
                onChooseFolder: { chooseDirectory(forModelKey: modelKey) }
            )
        }
    }

    private var externalDriveWarningMessage: String? {
        guard !allowExternalDrives else { return nil }

        let externalStoragePaths = StorageLocationTarget.allCases.contains { target in
            currentMode(for: target) == .custom && HUSHFileSystem.isExternalVolumePath(customPath(for: target))
        }

        let externalModelPaths = installedModels.contains { model in
            model.mode == .custom && HUSHFileSystem.isExternalVolumePath(model.currentPath)
        }

        guard externalStoragePaths || externalModelPaths else { return nil }
        return "Some current custom paths live on external drives and will not be available until External Drives is enabled."
    }

    private func loadStateIfNeeded() {
        guard !hasLoadedState else { return }
        hasLoadedState = true
        loadModelCustomPaths()
        loadInstalledModels()
    }

    private func storageModeBinding(for target: StorageLocationTarget) -> Binding<StorageLocationMode> {
        Binding(
            get: { currentMode(for: target) },
            set: { setMode($0, for: target) }
        )
    }

    private func currentMode(for target: StorageLocationTarget) -> StorageLocationMode {
        let rawValue: String
        switch target {
        case .sessions:
            rawValue = sessionsModeRaw
        case .archives:
            rawValue = archivesModeRaw
        }

        return StorageLocationMode(rawValue: rawValue) ?? .systemDefault
    }

    private func setMode(_ mode: StorageLocationMode, for target: StorageLocationTarget) {
        switch target {
        case .sessions:
            sessionsModeRaw = mode.rawValue
        case .archives:
            archivesModeRaw = mode.rawValue
        }

        syncSessionStorageIfNeeded(for: target)
    }

    private func customPath(for target: StorageLocationTarget) -> String {
        switch target {
        case .sessions:
            return sessionsCustomPath
        case .archives:
            return archivesCustomPath
        }
    }

    private func setCustomPath(_ path: String, for target: StorageLocationTarget) {
        switch target {
        case .sessions:
            sessionsCustomPath = path
        case .archives:
            archivesCustomPath = path
        }

        syncSessionStorageIfNeeded(for: target)
    }

    private func displayedCustomPath(for target: StorageLocationTarget) -> String {
        let path = customPath(for: target)
        return path.isEmpty ? defaultPath(for: target) : path
    }

    private func defaultPath(for target: StorageLocationTarget) -> String {
        switch target {
        case .sessions:
            return defaultSessionsDirectoryURL().path
        case .archives:
            return defaultArchivesDirectoryURL().path
        }
    }

    private func resolvedPath(for target: StorageLocationTarget) -> String {
        let mode = currentMode(for: target)
        let configuredPath = customPath(for: target)

        if mode == .custom, !configuredPath.isEmpty {
            return configuredPath
        }

        return defaultPath(for: target)
    }

    private func statusTitle(for target: StorageLocationTarget) -> String {
        let mode = currentMode(for: target)
        let configuredPath = customPath(for: target)

        if mode == .custom, !configuredPath.isEmpty, !allowExternalDrives,
           HUSHFileSystem.isExternalVolumePath(configuredPath) {
            return "Needs Access"
        }

        return mode.title
    }

    private func statusColor(for target: StorageLocationTarget) -> Color {
        let mode = currentMode(for: target)
        let configuredPath = customPath(for: target)

        if mode == .custom, !configuredPath.isEmpty, !allowExternalDrives,
           HUSHFileSystem.isExternalVolumePath(configuredPath) {
            return .orange
        }

        return .secondary
    }

    private func loadModelCustomPaths() {
        guard let data = modelCustomPathsStorage.data(using: .utf8),
              let decodedPaths = try? JSONDecoder().decode([String: String].self, from: data) else {
            modelCustomPaths = [:]
            return
        }

        modelCustomPaths = decodedPaths
    }

    private func saveModelCustomPaths() {
        guard let data = try? JSONEncoder().encode(modelCustomPaths),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }

        modelCustomPathsStorage = encoded
    }

    private func loadInstalledModels() {
        let modelsDirectory = defaultModelsDirectoryURL()
        try? HUSHFileSystem.ensureDirectoryExists(at: modelsDirectory)

        pruneMissingModelCustomPaths()

        let catalogEntries = loadInstalledModelCatalog()
        let defaultDirectories = (try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var entriesByKey: [String: ModelLocationEntry] = [:]

        for directoryURL in defaultDirectories where HUSHFileSystem.isDirectory(directoryURL) {
            let modelKey = directoryURL.lastPathComponent
            let customPath = validModelCustomPath(for: modelKey)
            entriesByKey[modelKey] = ModelLocationEntry(
                key: modelKey,
                title: installedModelTitle(for: modelKey, catalogEntries: catalogEntries),
                defaultPath: defaultModelPath(for: modelKey),
                currentPath: customPath ?? directoryURL.path
            )
        }

        for (modelKey, customPath) in modelCustomPaths where entriesByKey[modelKey] == nil {
            let customURL = URL(fileURLWithPath: customPath, isDirectory: true)
            guard HUSHFileSystem.isDirectory(customURL) else { continue }

            entriesByKey[modelKey] = ModelLocationEntry(
                key: modelKey,
                title: installedModelTitle(for: modelKey, catalogEntries: catalogEntries),
                defaultPath: defaultModelPath(for: modelKey),
                currentPath: customPath
            )
        }

        installedModels = entriesByKey.values.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func pruneMissingModelCustomPaths() {
        let cleanedPaths = modelCustomPaths.filter { _, path in
            HUSHFileSystem.isDirectory(URL(fileURLWithPath: path, isDirectory: true))
        }

        guard cleanedPaths != modelCustomPaths else { return }
        modelCustomPaths = cleanedPaths
        saveModelCustomPaths()
    }

    private func validModelCustomPath(for modelKey: String) -> String? {
        guard let customPath = modelCustomPaths[modelKey] else { return nil }
        let customURL = URL(fileURLWithPath: customPath, isDirectory: true)
        return HUSHFileSystem.isDirectory(customURL) ? customPath : nil
    }

    private func modelTitle(for modelKey: String) -> String {
        installedModels.first(where: { $0.key == modelKey })?.title
            ?? AssistantModelCatalog.prettyTitle(for: modelKey)
    }

    private func modelDisplayedCustomPath(for modelKey: String) -> String {
        installedModels.first(where: { $0.key == modelKey })?.currentPath
            ?? defaultModelPath(for: modelKey)
    }

    private func defaultModelPath(for modelKey: String) -> String {
        defaultModelURL(for: modelKey).path
    }

    private func defaultModelURL(for modelKey: String) -> URL {
        defaultModelsDirectoryURL()
            .appendingPathComponent(modelKey, isDirectory: true)
    }

    private func modelModeBinding(for modelKey: String) -> Binding<StorageLocationMode> {
        Binding(
            get: { draftModelModes[modelKey] ?? currentModelMode(for: modelKey) },
            set: { setModelMode($0, for: modelKey) }
        )
    }

    private func currentModelMode(for modelKey: String) -> StorageLocationMode {
        installedModels.first(where: { $0.key == modelKey })?.mode ?? .systemDefault
    }

    private func setModelMode(_ mode: StorageLocationMode, for modelKey: String) {
        switch mode {
        case .systemDefault:
            draftModelModes.removeValue(forKey: modelKey)
            moveModelToDefault(for: modelKey)
        case .custom:
            draftModelModes[modelKey] = .custom
        }
    }

    private func modelStatusTitle(for model: ModelLocationEntry) -> String {
        if model.mode == .custom, !allowExternalDrives,
           HUSHFileSystem.isExternalVolumePath(model.currentPath) {
            return "Needs Access"
        }

        return model.mode.title
    }

    private func modelStatusColor(for model: ModelLocationEntry) -> Color {
        if model.mode == .custom, !allowExternalDrives,
           HUSHFileSystem.isExternalVolumePath(model.currentPath) {
            return .orange
        }

        return .secondary
    }

    private func chooseDirectory(for target: StorageLocationTarget) {
        let startingPath = customPath(for: target).isEmpty ? defaultPath(for: target) : customPath(for: target)

        guard let selectedPath = chooseDirectory(startingAt: startingPath) else { return }
        guard validateExternalDriveSelection(path: selectedPath) else { return }

        try? HUSHFileSystem.ensureDirectoryExists(at: URL(fileURLWithPath: selectedPath, isDirectory: true))
        setCustomPath(selectedPath, for: target)
    }

    private func chooseDirectory(forModelKey modelKey: String) {
        guard let model = installedModels.first(where: { $0.key == modelKey }) else { return }
        guard let selectedPath = chooseDirectory(startingAt: model.currentPath) else { return }

        let destinationURL = resolvedModelDestinationURL(for: modelKey, selectionPath: selectedPath)
        guard validateExternalDriveSelection(path: destinationURL.path) else { return }

        moveModel(model, to: destinationURL)
    }

    private func resolvedModelDestinationURL(for modelKey: String, selectionPath: String) -> URL {
        let selectionURL = URL(fileURLWithPath: selectionPath, isDirectory: true)
        if selectionURL.lastPathComponent == modelKey {
            return selectionURL
        }

        return selectionURL.appendingPathComponent(modelKey, isDirectory: true)
    }

    private func moveModelToDefault(for modelKey: String) {
        guard let model = installedModels.first(where: { $0.key == modelKey }) else { return }
        moveModel(model, to: defaultModelURL(for: modelKey))
    }

    private func moveModel(_ model: ModelLocationEntry, to destinationURL: URL) {
        let sourceURL = URL(fileURLWithPath: model.currentPath, isDirectory: true).standardizedFileURL
        let targetURL = destinationURL.standardizedFileURL

        if sourceURL == targetURL {
            draftModelModes.removeValue(forKey: model.key)
            updateModelCustomPath(nilIfDefault: targetURL.path, for: model.key)
            loadInstalledModels()
            return
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            presentAlert(
                title: "Model Folder Missing",
                message: "HUSH couldn't find the current folder for \(model.title)."
            )
            return
        }

        try? HUSHFileSystem.ensureDirectoryExists(at: targetURL.deletingLastPathComponent())

        do {
            try prepareDestinationDirectory(at: targetURL)
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            draftModelModes.removeValue(forKey: model.key)
            updateModelCustomPath(nilIfDefault: targetURL.path, for: model.key)
            loadInstalledModels()
        } catch {
            presentAlert(
                title: "Couldn't Move Model",
                message: error.localizedDescription
            )
        }
    }

    private func updateModelCustomPath(nilIfDefault path: String, for modelKey: String) {
        let defaultPath = defaultModelPath(for: modelKey)
        if URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path ==
            URL(fileURLWithPath: defaultPath, isDirectory: true).standardizedFileURL.path {
            modelCustomPaths.removeValue(forKey: modelKey)
        } else {
            modelCustomPaths[modelKey] = path
        }

        saveModelCustomPaths()
    }

    private func prepareDestinationDirectory(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        if HUSHFileSystem.isEmptyDirectory(at: url) {
            try FileManager.default.removeItem(at: url)
            return
        }

        throw NSError(
            domain: "HUSH.Locations",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The destination folder already exists and is not empty."]
        )
    }

    private func loadInstalledModelCatalog() -> [InstalledModelCatalogEntry] {
        let catalogURL = HUSHFileSystem.fallbackApplicationSupportDirectory()
            .appendingPathComponent("model-catalog.json")

        guard let data = try? Data(contentsOf: catalogURL),
              let entries = try? JSONDecoder().decode([InstalledModelCatalogEntry].self, from: data) else {
            return []
        }

        return entries
    }

    private func installedModelTitle(
        for folderName: String,
        catalogEntries: [InstalledModelCatalogEntry]
    ) -> String {
        let normalizedFolderName = normalizedModelToken(folderName)

        if let catalogMatch = catalogEntries.first(where: { entry in
            normalizedModelToken(entry.modelID) == normalizedFolderName ||
                normalizedModelToken(entry.repositoryID?.components(separatedBy: "/").last ?? "") == normalizedFolderName
        }) {
            return catalogMatch.displayName
        }

        return AssistantModelCatalog.prettyTitle(for: folderName)
    }

    private func normalizedModelToken(_ value: String) -> String {
        value.lowercased().unicodeScalars.compactMap { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : nil
        }
        .joined()
    }

    private func validateExternalDriveSelection(path: String) -> Bool {
        guard HUSHFileSystem.isExternalVolumePath(path), !allowExternalDrives else { return true }

        presentAlert(
            title: "Enable External Drives",
            message: "Turn on External Drives at the top of Locations before choosing a folder on a removable volume."
        )
        return false
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isShowingAlert = true
    }

    private func revealPathInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        HUSHFileSystemUI.revealInFinder(url)
    }

    private func chooseDirectory(startingAt path: String) -> String? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return HUSHFileSystemUI.chooseDirectory(startingAt: url)?.path
    }

    private func syncSessionStorageIfNeeded(for target: StorageLocationTarget) {
        guard target == .sessions else { return }
        SessionHistoryStore.shared.persistCurrentState()
    }

    private func defaultSessionsDirectoryURL() -> URL {
        (try? SessionHistoryStore.defaultStorageDirectoryURL()) ?? HUSHFileSystem.fallbackApplicationSupportDirectory()
    }

    private func defaultArchivesDirectoryURL() -> URL {
        (try? HUSHFileSystem.archivesDirectory()) ?? HUSHFileSystem.fallbackApplicationSupportDirectory()
            .appendingPathComponent("Archives", isDirectory: true)
    }

    private func defaultModelsDirectoryURL() -> URL {
        (try? HUSHFileSystem.modelsDirectory()) ?? HUSHFileSystem.fallbackApplicationSupportDirectory()
            .appendingPathComponent("Models", isDirectory: true)
    }
}

private struct StorageLocationRow: View {
    let title: String
    let path: String
    let statusTitle: String
    let statusColor: Color
    let accentColor: Color
    let onRevealPath: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)

                Button(action: onRevealPath) {
                    HStack(spacing: 4) {
                        Text(path)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)

            Text(statusTitle)
                .foregroundStyle(statusColor)

            Button(action: onShowDetails) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Show location options")
        }
        .padding(.vertical, 2)
    }
}

private struct LocationOptionsSheet: View {
    let title: String
    @Binding var mode: StorageLocationMode
    let accentColor: Color
    let displayedPath: String
    let defaultPath: String
    let onChooseFolder: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var animatedModeBinding: Binding<StorageLocationMode> {
        Binding(
            get: { mode },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.18)) {
                    mode = newValue
                }
            }
        )
    }

    private var customRowPath: String {
        displayedPath.isEmpty ? defaultPath : displayedPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(.headline)

                Spacer()

                Picker("Location", selection: animatedModeBinding) {
                    ForEach(StorageLocationMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }

            Divider()

            ZStack {
                if mode == .custom {
                    HStack {
                        Spacer(minLength: 16)

                        Button(action: onChooseFolder) {
                            HStack(spacing: 8) {
                                Text(customRowPath)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                } else {
                    HStack(spacing: 6) {
                        Text(defaultPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
                }
            }
            .clipped()

            Divider()

            HStack {
                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
