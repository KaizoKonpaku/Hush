import Foundation
import Security

enum ProviderSecretSlot: String {
    case apiKey = "api-key"
    case adminKey = "admin-key"
}

final class KeychainSecretStore {
    static let shared = KeychainSecretStore()

    private init() {}

    func save(
        _ secret: String,
        for accountID: UUID,
        providerID: IntelligenceProviderID,
        slot: ProviderSecretSlot
    ) -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteSecret(for: accountID, providerID: providerID, slot: slot)
            return true
        }

        let query = keychainQuery(for: accountID, providerID: providerID, slot: slot)
        let attributes: [CFString: Any] = [
            kSecValueData: Data(trimmed.utf8),
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        var createQuery = query
        createQuery[kSecValueData as String] = Data(trimmed.utf8)
        createQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    func loadSecret(
        for accountID: UUID,
        providerID: IntelligenceProviderID,
        slot: ProviderSecretSlot
    ) -> String {
        var query = keychainQuery(for: accountID, providerID: providerID, slot: slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }

        return string
    }

    func deleteSecrets(for accountID: UUID, providerID: IntelligenceProviderID) {
        deleteSecret(for: accountID, providerID: providerID, slot: .apiKey)
        deleteSecret(for: accountID, providerID: providerID, slot: .adminKey)
    }

    private func deleteSecret(
        for accountID: UUID,
        providerID: IntelligenceProviderID,
        slot: ProviderSecretSlot
    ) {
        let query = keychainQuery(for: accountID, providerID: providerID, slot: slot)
        SecItemDelete(query as CFDictionary)
    }

    private func keychainQuery(
        for accountID: UUID,
        providerID: IntelligenceProviderID,
        slot: ProviderSecretSlot
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.kaizosha.HUSH.\(providerID.rawValue)",
            kSecAttrAccount as String: "\(accountID.uuidString).\(slot.rawValue)",
        ]
    }
}
