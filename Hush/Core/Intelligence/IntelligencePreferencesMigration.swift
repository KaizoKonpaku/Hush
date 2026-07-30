import Combine
import Foundation

struct IntelligencePreferencesMigration {
    private static let migrationKey = "intelligence.preferencesMigration.v3"

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: migrationKey) == false else {
            return
        }

        if defaults.string(forKey: "accounts.primaryProvider") == nil
            || defaults.string(forKey: "accounts.primaryProvider") == IntelligenceProviderID.mock.rawValue {
            defaults.set(IntelligenceProviderID.openAI.rawValue, forKey: "accounts.primaryProvider")
        }

        if defaults.string(forKey: "accounts.enabledProviders") == nil
            || defaults.string(forKey: "accounts.enabledProviders") == IntelligenceProviderID.mock.rawValue {
            defaults.set(IntelligenceProviderID.openAI.rawValue, forKey: "accounts.enabledProviders")
        }

        defaults.set(true, forKey: "accounts.enabledProvidersMigrated")

        clearLegacyMockModelSelection(forKey: "intel.defaultModel", defaults: defaults)
        clearLegacyMockModelSelection(forKey: "intel.fastModel", defaults: defaults)
        clearLegacyMockModelSelection(forKey: "intel.advancedModel", defaults: defaults)

        if defaults.object(forKey: "assistant.selectedModelMode") == nil {
            defaults.set(AssistantModelMode.defaultMode.rawValue, forKey: "assistant.selectedModelMode")
        }

        defaults.set(true, forKey: migrationKey)
    }

    static func configuredProviderKeys(defaults: UserDefaults = .standard) -> [IntelligenceProviderID: String] {
        [:]
    }

    private static func clearLegacyMockModelSelection(forKey key: String, defaults: UserDefaults) {
        let currentValue = defaults.string(forKey: key) ?? ""
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == IntelligenceProviderID.mock.rawValue
            || trimmed == "hush-demo"
            || trimmed == "mock::hush-demo" {
            defaults.set("", forKey: key)
            return
        }

        if currentValue.isEmpty {
            defaults.set("", forKey: key)
        }
    }
}

struct AssistantPromptPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var instructions: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        instructions: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.updatedAt = updatedAt
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedInstructions: String {
        instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var previewText: String {
        let normalized = trimmedInstructions
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")

        guard normalized.count > 120 else {
            return normalized
        }

        let cutoffIndex = normalized.index(normalized.startIndex, offsetBy: 120)
        return String(normalized[..<cutoffIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

enum AssistantPromptPresetCatalog {
    static let presetsDefaultsKey = "intel.promptPresets.v1"
    static let selectedPresetDefaultsKey = "intel.defaultPromptPresetID"
    static let builtInPresetName = "HUSH Default"
    static let builtInInstructions = """
    You are an AI assistant. Answer clearly, stay grounded in the user's provided context, and prefer concise actionable guidance over filler.
    """

    static func load(defaults: UserDefaults = .standard) -> [AssistantPromptPreset] {
        guard let data = defaults.data(forKey: presetsDefaultsKey) else {
            return []
        }

        do {
            let decoded = try JSONDecoder().decode([AssistantPromptPreset].self, from: data)
            return decoded.sorted(by: assistantPromptPresetSortDescending)
        } catch {
            NSLog("[HUSH] Prompt preset load failed: \(error.localizedDescription)")
            return []
        }
    }

    static func save(_ presets: [AssistantPromptPreset], defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(presets.sorted(by: assistantPromptPresetSortDescending))
            defaults.set(data, forKey: presetsDefaultsKey)
        } catch {
            NSLog("[HUSH] Prompt preset save failed: \(error.localizedDescription)")
        }
    }

    static func selectedPresetID(defaults: UserDefaults = .standard) -> UUID? {
        guard let rawValue = defaults.string(forKey: selectedPresetDefaultsKey),
              !rawValue.isEmpty else {
            return nil
        }

        return UUID(uuidString: rawValue)
    }

    static func setSelectedPresetID(_ presetID: UUID?, defaults: UserDefaults = .standard) {
        if let presetID {
            defaults.set(presetID.uuidString, forKey: selectedPresetDefaultsKey)
        } else {
            defaults.removeObject(forKey: selectedPresetDefaultsKey)
        }
    }

    static func selectedPreset(defaults: UserDefaults = .standard) -> AssistantPromptPreset? {
        let presets = load(defaults: defaults)
        guard let presetID = selectedPresetID(defaults: defaults) else {
            return nil
        }

        return presets.first(where: { $0.id == presetID })
    }

    static func effectiveInstructions(defaults: UserDefaults = .standard) -> String {
        let selectedInstructions = selectedPreset(defaults: defaults)?.trimmedInstructions ?? ""
        return selectedInstructions.isEmpty ? builtInInstructions : selectedInstructions
    }

    static func selectedPresetTitle(defaults: UserDefaults = .standard) -> String {
        selectedPreset(defaults: defaults)?.trimmedName.nilIfEmpty ?? builtInPresetName
    }
}

@MainActor
final class AssistantPromptPresetStore: ObservableObject {
    static let shared = AssistantPromptPresetStore()

    @Published private(set) var presets: [AssistantPromptPreset] = []
    @Published private(set) var selectedPresetID: UUID?

    private let defaults = UserDefaults.standard

    private init() {
        refresh()
    }

    var selectedPreset: AssistantPromptPreset? {
        guard let selectedPresetID else { return nil }
        return presets.first(where: { $0.id == selectedPresetID })
    }

    var selectedPresetTitle: String {
        selectedPreset?.trimmedName.nilIfEmpty ?? AssistantPromptPresetCatalog.builtInPresetName
    }

    func refresh() {
        presets = AssistantPromptPresetCatalog.load(defaults: defaults)
        let persistedSelection = AssistantPromptPresetCatalog.selectedPresetID(defaults: defaults)

        if let persistedSelection,
           presets.contains(where: { $0.id == persistedSelection }) {
            selectedPresetID = persistedSelection
        } else {
            selectedPresetID = nil
            AssistantPromptPresetCatalog.setSelectedPresetID(nil, defaults: defaults)
        }
    }

    func selectPreset(id: UUID?) {
        if let id,
           presets.contains(where: { $0.id == id }) == false {
            return
        }

        selectedPresetID = id
        AssistantPromptPresetCatalog.setSelectedPresetID(id, defaults: defaults)
        objectWillChange.send()
    }

    @discardableResult
    func savePreset(id: UUID?, name: String, instructions: String) -> AssistantPromptPreset {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = normalizedName.isEmpty ? "Untitled Prompt" : normalizedName

        let preset = AssistantPromptPreset(
            id: id ?? UUID(),
            name: resolvedName,
            instructions: normalizedInstructions,
            updatedAt: Date()
        )

        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }

        presets.sort(by: assistantPromptPresetSortDescending)
        AssistantPromptPresetCatalog.save(presets, defaults: defaults)

        if selectedPresetID == nil {
            selectPreset(id: preset.id)
        } else {
            refresh()
        }

        return preset
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        AssistantPromptPresetCatalog.save(presets, defaults: defaults)

        if selectedPresetID == id {
            selectPreset(id: nil)
        } else {
            refresh()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private func assistantPromptPresetSortDescending(
    _ lhs: AssistantPromptPreset,
    _ rhs: AssistantPromptPreset
) -> Bool {
    if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
    }

    return lhs.trimmedName.localizedCaseInsensitiveCompare(rhs.trimmedName) == .orderedAscending
}
