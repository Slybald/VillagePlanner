// L'avancement (règles A1 à A5, PLAN §5.1) : le chemin entre « HDV précédent terminé » et « HDV actuel terminé ».

/// L'avancement d'une catégorie : fait, à faire, unité.
public struct Progress: Sendable, Equatable {
    public enum Unit: Sendable, Equatable {
        case seconds                               // A1 : durée des améliorations
        case cost                                  // A2 : coût des murs
        case levels                                // A3 (équipements), ou A1 quand toutes les durées sont nulles
    }
    /// Somme des poids faits.
    public let done: Int
    /// Somme des poids à faire à cet HDV (0 : rien à cet HDV).
    public let total: Int
    public let unit: Unit

    public init(done: Int, total: Int, unit: Unit) {
        self.done = done
        self.total = total
        self.unit = unit
    }

    /// Faux : « rien à cet HDV », la catégorie sort de la moyenne (A4).
    public var hasWork: Bool { total > 0 }
    /// Entre 0 et 1 ; 1 quand il n'y a rien à faire.
    public var fraction: Double { total > 0 ? Double(done) / Double(total) : 1 }
}

/// L'avancement par catégorie et au total.
public struct ProgressReport: Sendable, Equatable {
    /// Les huit catégories ; vide quand l'HDV est inconnu (V7).
    public let categories: [Category: Progress]
    /// Moyenne simple des catégories qui ont quelque chose à faire (A4) ; nil quand l'HDV est inconnu (V7).
    public let total: Double?

    public init(categories: [Category: Progress] = [:], total: Double? = nil) {
        self.categories = categories
        self.total = total
    }
}

public func progress(of village: Village, reference: ReferenceData) -> ProgressReport {
    guard village.status != .unknownTownHall else { return ProgressReport() }   // V7
    // Par catégorie : (poids fait, poids à faire, niveaux faits, niveaux à faire).
    var sums: [Category: (done: Int, total: Int, doneLevels: Int, levels: Int)] = [:]
    for element in village.elements {
        // A5 : hors avancement (V8). V4 et V5 sont déjà hors des éléments du village.
        guard let item = reference.item(element.itemID), let category = item.category else { continue }
        let first = min(element.level, element.baseLevel) + 1
        guard first <= element.maxLevel else { continue }
        var s = sums[category] ?? (0, 0, 0, 0)
        // Un niveau en cours n'est pas fait : `level` est le niveau avant la fin de l'amélioration.
        for n in first...element.maxLevel {
            let w = weight(of: item.levels.first { $0.level == n }, in: category) * element.count
            s.total += w
            s.levels += element.count
            if n <= element.level {
                s.done += w
                s.doneLevels += element.count
            }
        }
        sums[category] = s
    }
    var categories: [Category: Progress] = [:]
    for category in Category.allCases {
        let s = sums[category] ?? (0, 0, 0, 0)
        let unit: Progress.Unit = category == .walls ? .cost : category == .equipment ? .levels : .seconds
        // A1 : si tous les niveaux à faire pèsent 0, chacun pèse 1.
        categories[category] = s.total == 0
            ? Progress(done: s.doneLevels, total: s.levels, unit: .levels)
            : Progress(done: s.done, total: s.total, unit: unit)
    }
    // Ordre fixe des catégories : la somme flottante ne dépend pas de l’ordre du dictionnaire.
    let working = Category.allCases.compactMap { categories[$0] }.filter(\.hasWork)
    let total = working.isEmpty ? 1 : working.map(\.fraction).reduce(0, +) / Double(working.count)
    return ProgressReport(categories: categories, total: total)
}

/// Poids d'un niveau : durée (A1), coût pour les murs (A2), 1 pour les équipements (A3).
func weight(of level: ReferenceLevel?, in category: Category) -> Int {
    switch category {
    case .equipment: 1
    case .walls: level?.costs.reduce(0) { $0 + $1.amount } ?? 0
    default: level?.duration ?? 0
    }
}
