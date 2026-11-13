import Foundation

// L'API officielle de Supercell (statistiques de joueur) : tâches T29 et T30. Aucun type au contrat §7.2.
// Le profil lu par `GET /players/{tag}`. Tout champ absent, d'un autre type ou inconnu est toléré : seul `tag` est exigé,
// pour reconnaître un profil. Un élément de liste illisible est écarté sans emporter les autres.

/// Les longueurs maximales des textes lus : un nom de joueur tient en 15 caractères dans le jeu ; 32 laisse de la marge.
enum Texte {
    static let court = 32
    static let long = 64
}

public struct LigueJoueur: Codable, Sendable, Equatable {
    public var id: Int?
    public var name: String?

    public init(id: Int? = nil, name: String? = nil) { (self.id, self.name) = (id, name) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id)
        name = c.texte(.name, max: Texte.long)
    }
}

/// Un niveau de troupe, de sort, de héros ou d'équipement.
public struct ItemJoueur: Codable, Sendable, Equatable {
    public var name: String
    public var level: Int?
    public var maxLevel: Int?
    public var village: String?

    public init(name: String, level: Int? = nil, maxLevel: Int? = nil, village: String? = nil) {
        (self.name, self.level, self.maxLevel, self.village) = (name, level, maxLevel, village)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = String(try c.decode(String.self, forKey: .name).prefix(Texte.long))   // sans nom, l'élément ne sert à rien : écarté par la liste
        level = c.lenient(.level)
        maxLevel = c.lenient(.maxLevel)
        village = c.texte(.village, max: Texte.court)
    }
}

public struct HeroJoueur: Codable, Sendable, Equatable {
    public var name: String
    public var level: Int?
    public var maxLevel: Int?
    public var village: String?
    /// Les équipements équipés sur ce héros (`heroes[].equipment`).
    public var equipment: [ItemJoueur]

    public init(name: String, level: Int? = nil, maxLevel: Int? = nil, village: String? = nil, equipment: [ItemJoueur] = []) {
        (self.name, self.level, self.maxLevel, self.village, self.equipment) = (name, level, maxLevel, village, equipment)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = String(try c.decode(String.self, forKey: .name).prefix(Texte.long))
        level = c.lenient(.level)
        maxLevel = c.lenient(.maxLevel)
        village = c.texte(.village, max: Texte.court)
        equipment = c.lenientList(.equipment)
    }
}

public struct SuccesJoueur: Codable, Sendable, Equatable {
    public var name: String
    public var stars: Int?
    public var value: Int?
    public var target: Int?
    public var village: String?

    public init(name: String, stars: Int? = nil, value: Int? = nil, target: Int? = nil, village: String? = nil) {
        (self.name, self.stars, self.value, self.target, self.village) = (name, stars, value, target, village)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = String(try c.decode(String.self, forKey: .name).prefix(Texte.long))
        stars = c.lenient(.stars)
        value = c.lenient(.value)
        target = c.lenient(.target)
        village = c.texte(.village, max: Texte.court)
    }
}

public struct ProfilJoueur: Codable, Sendable, Equatable {
    public var tag: String
    public var name: String?
    public var expLevel: Int?
    public var townHallLevel: Int?
    public var trophies: Int?
    public var bestTrophies: Int?
    public var attackWins: Int?
    public var defenseWins: Int?
    public var donations: Int?
    public var donationsReceived: Int?
    public var warStars: Int?
    /// Le rang du système de ligues de 2025. Le champ `league` (ancien système) n'est pas lu.
    public var leagueTier: LigueJoueur?
    public var achievements: [SuccesJoueur]
    public var heroes: [HeroJoueur]
    /// Tous les équipements possédés (`heroEquipment`), équipés ou non.
    public var heroEquipment: [ItemJoueur]

    public init(tag: String, name: String? = nil, expLevel: Int? = nil, townHallLevel: Int? = nil, trophies: Int? = nil,
                bestTrophies: Int? = nil, attackWins: Int? = nil, defenseWins: Int? = nil, donations: Int? = nil,
                donationsReceived: Int? = nil, warStars: Int? = nil, leagueTier: LigueJoueur? = nil,
                achievements: [SuccesJoueur] = [], heroes: [HeroJoueur] = [], heroEquipment: [ItemJoueur] = []) {
        self.tag = tag; self.name = name; self.expLevel = expLevel; self.townHallLevel = townHallLevel
        self.trophies = trophies; self.bestTrophies = bestTrophies; self.attackWins = attackWins
        self.defenseWins = defenseWins; self.donations = donations; self.donationsReceived = donationsReceived
        self.warStars = warStars; self.leagueTier = leagueTier; self.achievements = achievements
        self.heroes = heroes; self.heroEquipment = heroEquipment
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.decode(String.self, forKey: .tag)
        name = c.texte(.name, max: Texte.court)
        expLevel = c.lenient(.expLevel)
        townHallLevel = c.lenient(.townHallLevel)
        trophies = c.lenient(.trophies)
        bestTrophies = c.lenient(.bestTrophies)
        attackWins = c.lenient(.attackWins)
        defenseWins = c.lenient(.defenseWins)
        donations = c.lenient(.donations)
        donationsReceived = c.lenient(.donationsReceived)
        warStars = c.lenient(.warStars)
        leagueTier = c.lenient(.leagueTier)
        achievements = c.lenientList(.achievements)
        heroes = c.lenientList(.heroes)
        heroEquipment = c.lenientList(.heroEquipment)
    }

    /// Le profil d'une réponse 200 ; nil si ce n'est pas un objet JSON portant un `tag`.
    static func decode(_ data: Data) -> ProfilJoueur? { try? JSONDecoder().decode(ProfilJoueur.self, from: data) }
}

/// Un élément qui se décode sans jamais échouer : `value` vaut nil quand il est illisible.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    /// Un texte du service, borné : il s'affiche dans les Réglages, et un relais fautif ne doit pas y mettre un roman.
    func texte(_ key: Key, max: Int) -> String? { lenient(key).map { (s: String) in String(s.prefix(max)) } }

    /// La valeur, ou nil si le champ manque, est nul ou d'un autre type.
    func lenient<T: Decodable>(_ key: Key) -> T? { (try? decode(Lenient<T>.self, forKey: key))?.value }

    /// Les éléments lisibles ; une liste absente ou qui n'en est pas une donne `[]`.
    func lenientList<T: Decodable>(_ key: Key) -> [T] {
        ((try? decode([Lenient<T>].self, forKey: key)) ?? []).compactMap(\.value)
    }
}
