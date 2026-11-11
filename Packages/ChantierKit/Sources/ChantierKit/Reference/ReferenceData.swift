// Squelette du contrat §7.2. Le modèle, le chargement et reference.json sont la tâche T04.

/// Les données de référence : noms, niveaux, coûts, durées, maximums.
public struct ReferenceData: Sendable {
    public let items: [ReferenceItem]

    public init(items: [ReferenceItem] = []) {
        self.items = items
    }
}

public enum Category: String, Sendable, CaseIterable {
    case defenses, traps, economy, walls, heroes, laboratory, pets, equipment
}

public enum WorkerKind: Sendable { case builder, laboratory, petHouse, blacksmith }

public struct ReferenceItem: Sendable {
    public let id: Int
    public let names: [String: String]             // "fr", "en"
    public let category: Category?                 // nil : hors avancement
    public let worker: WorkerKind
    public let levels: [ReferenceLevel]
    public let countByTownHall: [Int]              // cumul, indice = niveau d'HDV
    public let maxLevelByTownHall: [Int]
    public let mergedFrom: [Requirement]           // bâtiments consommés par une fusion (V2)
}

public struct ReferenceLevel: Sendable {
    public let level: Int
    public let costs: [ResourceAmount]
    public let duration: Int                       // secondes
    public let requires: [Requirement]             // autre élément à un niveau donné
}

/// Un autre élément à un niveau donné.
public struct Requirement: Sendable, Equatable {
    public let itemID: Int
    public let level: Int
}

public enum Resource: String, Sendable, CaseIterable {
    case gold, elixir, darkElixir, shinyOre, glowyOre, starryOre
}

public struct ResourceAmount: Sendable, Equatable {
    public let resource: Resource
    public let amount: Int
}
