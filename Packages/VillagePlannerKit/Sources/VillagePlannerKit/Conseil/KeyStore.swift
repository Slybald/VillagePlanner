import Foundation
import Security
import Synchronization

// La clé d'API du conseiller (décision D7) : dans le Trousseau, sur cet appareil seulement. Jamais dans un fichier,
// une préférence ou un journal ; elle ne s'affiche plus en clair une fois enregistrée.

/// Un coffre à un seul secret. Le Trousseau dans l'app, un coffre en mémoire dans les tests et les captures.
public protocol SecretStore: Sendable {
    func read() throws(KeyStoreError) -> String?
    func save(_ secret: String) throws(KeyStoreError)
    func delete() throws(KeyStoreError)
}

public enum KeyStoreError: Error, Equatable, Sendable {
    /// Le texte collé n'est pas une clé (vide, espaces ou caractères invisibles au milieu).
    case invalidKey
    /// Le Trousseau a refusé ; le code `OSStatus` seulement, jamais la clé.
    case keychain(status: Int32)
}

/// Ce que l'app accepte comme clé, et ce qu'elle en montre.
public enum APIKey {
    /// La clé collée, débarrassée des espaces et retours à la ligne autour ; nil si ce n'est pas un texte ASCII visible
    /// d'un seul tenant (ce qui empêche aussi d'injecter une ligne dans l'en-tête HTTP).
    public static func normalized(_ pasted: String) -> String? {
        let key = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else { return nil }
        return key
    }

    /// Ce que les Réglages affichent : des points et les quatre derniers caractères.
    public static func masked(_ key: String) -> String {
        "••••••••" + (key.count > 12 ? String(key.suffix(4)) : "")
    }
}

/// Ce que les Réglages savent de la clé.
public enum KeyState: Equatable, Sendable {
    case absent
    case present(masked: String)
    case unavailable
}

extension APIKey {
    public static func state(of store: any SecretStore) -> KeyState {
        do {
            guard let key = try store.read().flatMap(normalized) else { return .absent }
            return .present(masked: masked(key))
        } catch { return .unavailable }
    }
}

/// Le Trousseau iOS : un mot de passe générique, accessible quand l'appareil est déverrouillé, jamais synchronisé
/// avec iCloud ni restauré sur un autre appareil.
public struct KeychainStore: SecretStore {
    public static let service = "fr.slybald.villageplanner.conseiller"
    public static let account = "anthropic-api-key"

    public init() {}

    /// La requête qui désigne l'élément.
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    /// Les attributs d'un nouvel élément.
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
        // Mise à jour d'abord : si elle échoue, l'ancienne clé reste.
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

/// Un coffre en mémoire : tests et captures (jamais une vraie clé).
public final class MemorySecretStore: SecretStore {
    private let secret: Mutex<String?>

    public init(_ secret: String? = nil) { self.secret = Mutex(secret) }

    public func read() throws(KeyStoreError) -> String? { secret.withLock { $0 } }

    public func save(_ secret: String) throws(KeyStoreError) {
        guard let key = APIKey.normalized(secret) else { throw .invalidKey }
        self.secret.withLock { $0 = key }
    }

    public func delete() throws(KeyStoreError) { secret.withLock { $0 = nil } }
}
