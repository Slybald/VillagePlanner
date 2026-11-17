import Foundation

/// L'enregistrement du profil de jeu : un seul blob JSON dans les préférences.
/// Un blob absent ou illisible donne le profil par défaut, sans rien effacer tant qu'on n'enregistre pas.
public struct ProfilStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "profil") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Profile {
        guard let data = defaults.data(forKey: key) else { return Profile() }
        return (try? JSONDecoder().decode(Profile.self, from: data)) ?? Profile()
    }

    public func save(_ profile: Profile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }
}
