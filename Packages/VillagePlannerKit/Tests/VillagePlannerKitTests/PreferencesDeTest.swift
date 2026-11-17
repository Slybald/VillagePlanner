import Foundation
import Testing

/// Préférences des tests : un `UserDefaults` qui garde tout en mémoire. Rien n'est écrit sur le disque (ni fichier
/// `.plist` dans `~/Library/Preferences`, ni passage par cfprefsd) : un test ne peut rien laisser derrière lui.
/// Les types de production n'utilisent que `data(forKey:)` et `set(_:forKey:)` ; les autres accès utilisés par les tests
/// sont surchargés aussi.
final class PreferencesDeTest: UserDefaults, @unchecked Sendable {
    private let verrou = NSLock()
    private var valeurs: [String: Any] = [:]

    /// Des préférences neuves et vides.
    static func neuves() -> PreferencesDeTest { PreferencesDeTest(suiteName: nil)! }

    override func object(forKey defaultName: String) -> Any? { verrou.withLock { valeurs[defaultName] } }
    override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }
    override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    override func set(_ value: Any?, forKey defaultName: String) { verrou.withLock { valeurs[defaultName] = value } }
    override func removeObject(forKey defaultName: String) { verrou.withLock { _ = valeurs.removeValue(forKey: defaultName) } }
    override func dictionaryRepresentation() -> [String: Any] { verrou.withLock { valeurs } }
}

@Suite struct PreferencesDeTestTests {
    @Test func apresUsage_rienSurLeDisque_etSuiteVideQuandOnLEfface() {
        let d = PreferencesDeTest.neuves()
        d.set(Data("x".utf8), forKey: "cle")
        #expect(d.data(forKey: "cle") == Data("x".utf8))
        #expect(PreferencesDeTest.neuves().data(forKey: "cle") == nil)                 // deux instances ne partagent rien
        #expect(UserDefaults.standard.object(forKey: "cle") == nil)                    // et rien ne passe par le domaine standard
        d.removeObject(forKey: "cle")
        #expect(d.dictionaryRepresentation().isEmpty)
    }
}
