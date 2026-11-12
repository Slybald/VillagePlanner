import Foundation

// Contrat §7.2. Le fichier `Ressources/reference.json` est produit par `outils maj-reference`
// (voir docs/mise-a-jour-du-jeu.md) ; ne pas le modifier à la main.

/// Les données de référence : noms, niveaux, coûts, durées, maximums.
public struct ReferenceData: Sendable, Codable {
    /// Version du format de `reference.json`.
    public static let currentFormat = 1

    public let format: Int
    public let source: ReferenceSource
    /// HDV le plus haut connu de la source (au-delà : règle V7).
    public let maxTownHall: Int
    public let items: [ReferenceItem]
    private let index: [Int: Int]

    public init(items: [ReferenceItem] = [], source: ReferenceSource = ReferenceSource(),
                maxTownHall: Int = 0, format: Int = ReferenceData.currentFormat) {
        self.format = format
        self.source = source
        self.maxTownHall = maxTownHall
        self.items = items
        index = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func item(_ id: Int) -> ReferenceItem? { index[id].map { items[$0] } }

    private enum CodingKeys: String, CodingKey { case format, source, maxTownHall, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: try c.decode([ReferenceItem].self, forKey: .items),
                  source: try c.decode(ReferenceSource.self, forKey: .source),
                  maxTownHall: try c.decode(Int.self, forKey: .maxTownHall),
                  format: try c.decode(Int.self, forKey: .format))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(source, forKey: .source)
        try c.encode(maxTownHall, forKey: .maxTownHall)
        try c.encode(items, forKey: .items)
    }
}

public enum ReferenceError: Error, Equatable {
    case missing                    // fichier absent
    case corrupt                    // pas du JSON, ou pas au format attendu
    case unsupportedFormat(Int)
}

extension ReferenceData {
    /// Emplacement du `reference.json` embarqué.
    public static var bundledURL: URL? { Bundle.module.url(forResource: "reference", withExtension: "json") }

    /// Le `reference.json` embarqué.
    public static func load() throws(ReferenceError) -> ReferenceData {
        guard let url = bundledURL else { throw .missing }
        return try load(from: url)
    }

    public static func load(from url: URL) throws(ReferenceError) -> ReferenceData {
        guard let data = try? Data(contentsOf: url) else { throw .missing }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws(ReferenceError) -> ReferenceData {
        guard let reference = try? JSONDecoder().decode(ReferenceData.self, from: data) else {
            throw .corrupt
        }
        guard reference.format == currentFormat else { throw .unsupportedFormat(reference.format) }
        return reference
    }
}

/// D'où viennent les données : dépôt, commit et date du commit (jamais la date d'exécution de l'outil).
public struct ReferenceSource: Sendable, Codable, Equatable {
    public let name: String
    public let license: String
    public let commit: String
    public let date: String         // ISO 8601, date du dernier commit des données

    public init(name: String = "", license: String = "", commit: String = "", date: String = "") {
        self.name = name
        self.license = license
        self.commit = commit
        self.date = date
    }
}

public enum Category: String, Sendable, CaseIterable, Codable {
    case defenses, traps, economy, walls, heroes, laboratory, pets, equipment
}

/// Pourquoi un type est hors avancement (`category == nil`).
public enum Exclusion: String, Sendable, CaseIterable, Codable {
    case superTroop, event, seasonal, guardian, helper, craftedDefense
}

public enum WorkerKind: String, Sendable, CaseIterable, Codable {
    case builder, laboratory, petHouse, blacksmith
}

public struct ReferenceItem: Sendable, Codable {
    public let id: Int
    public let names: [String: String]             // "fr", "en"
    /// Section de l'export où ce type apparaît : "buildings", "units", "siege_machines"…
    /// Les défenses fabriquées et leurs modules sont dans "buildings", sous le 1000097.
    public let section: String
    public let category: Category?                 // nil : hors avancement
    public let exclusion: Exclusion?               // la raison, quand category == nil
    public let worker: WorkerKind
    public let levels: [ReferenceLevel]
    public let countByTownHall: [Int]              // cumul, indice = niveau d'HDV
    public let maxLevelByTownHall: [Int]           // indice = niveau d'HDV ; 0 : pas déblocable
    public let mergedFrom: [Requirement]           // bâtiments consommés par une fusion (V2), un par exemplaire

    public init(id: Int, names: [String: String], section: String, category: Category?,
                exclusion: Exclusion?, worker: WorkerKind, levels: [ReferenceLevel],
                countByTownHall: [Int], maxLevelByTownHall: [Int], mergedFrom: [Requirement]) {
        self.id = id
        self.names = names
        self.section = section
        self.category = category
        self.exclusion = exclusion
        self.worker = worker
        self.levels = levels
        self.countByTownHall = countByTownHall
        self.maxLevelByTownHall = maxLevelByTownHall
        self.mergedFrom = mergedFrom
    }

    public var name: String { names["fr"] ?? names["en"] ?? "#\(id)" }

    /// Nombre autorisé à l'HDV `townHall`, avant les fusions (V2) ; 0 hors du tableau.
    public func count(atTownHall townHall: Int) -> Int {
        countByTownHall.indices.contains(townHall) ? countByTownHall[townHall] : 0
    }

    /// Niveau maximum à l'HDV `townHall` ; 0 hors du tableau.
    public func maxLevel(atTownHall townHall: Int) -> Int {
        maxLevelByTownHall.indices.contains(townHall) ? maxLevelByTownHall[townHall] : 0
    }
}

public struct ReferenceLevel: Sendable, Codable {
    public let level: Int
    public let costs: [ResourceAmount]
    public let duration: Int                       // secondes
    public let requires: [Requirement]             // autre élément à un niveau donné (HDV : 1000001)
    /// Murs : l'autre ressource acceptée à la place de `costs`, pour le même montant.
    public let alternativeResource: Resource?
    /// Assistants (règle S6) : multiplicateur et durée du service, en secondes.
    public let helperMultiplier: Int?
    public let helperSeconds: Int?

    public init(level: Int, costs: [ResourceAmount], duration: Int, requires: [Requirement],
                alternativeResource: Resource? = nil, helperMultiplier: Int? = nil,
                helperSeconds: Int? = nil) {
        self.level = level
        self.costs = costs
        self.duration = duration
        self.requires = requires
        self.alternativeResource = alternativeResource
        self.helperMultiplier = helperMultiplier
        self.helperSeconds = helperSeconds
    }
}

/// Un autre élément à un niveau donné.
public struct Requirement: Sendable, Equatable, Codable {
    public let itemID: Int
    public let level: Int

    public init(itemID: Int, level: Int) {
        self.itemID = itemID
        self.level = level
    }
}

public enum Resource: String, Sendable, CaseIterable, Codable {
    case gold, elixir, darkElixir, shinyOre, glowyOre, starryOre
}

public struct ResourceAmount: Sendable, Equatable, Codable {
    public let resource: Resource
    public let amount: Int

    public init(resource: Resource, amount: Int) {
        self.resource = resource
        self.amount = amount
    }
}
