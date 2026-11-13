import Foundation
import Security

// La clé d'API de Supercell (décision D8) : dans le Trousseau, sous un compte qui n'est pas celui de la clé du conseiller.
// Elle ne sert qu'à `cocproxy.royaleapi.dev` ; jamais dans un fichier, une préférence ou un journal.

/// Le Trousseau iOS pour la clé Supercell : mêmes réglages que celui de T19 (accessible appareil déverrouillé, jamais
/// synchronisé ni restauré ailleurs), autre service et autre compte. T19 reste intact : ses requêtes sont testées telles quelles.
public struct KeychainStoreJoueur: SecretStore {
    public static let service = "fr.slybald.chantier.joueur"
    public static let account = "supercell-api-key"

    public init() {}

    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    static func attributes(for secret: String) -> [String: Any] {
        query.merging([kSecValueData as String: Data(secret.utf8),
                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { $1 }
    }

    public func read() throws(KeyStoreError) -> String? {
        var q = Self.query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw .keychain(status: status) }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ secret: String) throws(KeyStoreError) {
        guard let key = APIKey.normalized(secret) else { throw .invalidKey }
        let changes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(Self.query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(Self.attributes(for: key) as CFDictionary, nil) }
        guard status == errSecSuccess else { throw .keychain(status: status) }
    }

    public func delete() throws(KeyStoreError) {
        let status = SecItemDelete(Self.query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status: status) }
    }
}
