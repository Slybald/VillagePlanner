import Foundation
import Testing

/// Préférences jetables pour les tests : chaque suite créée ici est effacée (domaine et fichier `.plist`) à la fin du
/// processus de test, ou plus tôt par `effacer`. Un test ne laisse rien dans `~/Library/Preferences`.
enum PreferencesDeTest {
    private final class Registre: @unchecked Sendable {
        let verrou = NSLock()
        var noms: Set<String> = []
    }
    private static let registre: Registre = {
        atexit { PreferencesDeTest.toutEffacer() }
        return Registre()
    }()

    /// Une suite neuve (ou celle de ce nom), enregistrée pour être effacée.
    static func neuves(_ nom: String = "chantier-test-\(UUID().uuidString)") -> UserDefaults {
        registre.verrou.withLock { _ = registre.noms.insert(nom) }
        return UserDefaults(suiteName: nom)!
    }

    static func effacer(_ defaults: UserDefaults, nom: String) {
        defaults.removePersistentDomain(forName: nom)
        let fichier = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(nom).plist")
        try? FileManager.default.removeItem(at: fichier)
    }

    static func toutEffacer() {
        let noms = registre.verrou.withLock { registre.noms }
        for nom in noms { effacer(UserDefaults(suiteName: nom)!, nom: nom) }
    }

    /// Le nom du fichier `.plist` d'une suite (pour les vérifications).
    static func fichier(_ nom: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(nom).plist")
    }
}

@Suite struct PreferencesDeTestTests {
    @Test func apresUsage_laSuiteEstVideEtLeFichierAbsent() {
        let nom = "chantier-test-effacement-\(UUID().uuidString)"
        let d = PreferencesDeTest.neuves(nom)
        d.set("valeur", forKey: "cle")
        d.synchronize()
        #expect(d.string(forKey: "cle") == "valeur")
        PreferencesDeTest.effacer(d, nom: nom)
        #expect((d.persistentDomain(forName: nom) ?? [:]).isEmpty)
        #expect(UserDefaults(suiteName: nom)!.dictionaryRepresentation().keys.allSatisfy { $0 != "cle" })
        #expect(!FileManager.default.fileExists(atPath: PreferencesDeTest.fichier(nom).path))
    }
}
