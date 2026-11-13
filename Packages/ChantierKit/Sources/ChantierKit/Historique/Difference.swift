import Foundation

/// Ce qui a changé entre deux photos (ticket de chantier, PLAN §1.3).
public struct PhotoDiff: Sendable, Equatable {
    public struct ItemCount: Sendable, Equatable {
        public let itemID: Int
        public let count: Int
    }

    /// Toujours `from <= to`. Si on a donné les photos à l'envers, `swapped` le dit : on compare dans l'ordre du temps.
    public let from: Date
    public let to: Date
    public let swapped: Bool
    /// Niveaux gagnés par type, rangés par identifiant. Une perte n'est jamais comptée : un bâtiment qui disparaît
    /// (fusion en Canon ricochet) n'est pas un niveau perdu.
    public let levelsGained: [ItemCount]
    /// Améliorations lancées depuis la première photo (en cours dans la seconde, pas dans la première).
    public let started: [ItemCount]
    /// Améliorations de la première photo qui sont terminées dans la seconde.
    public let finished: [ItemCount]
    /// Types présents seulement dans la seconde photo / seulement dans la première.
    public let added: [Int]
    public let removed: [Int]
    /// Déplacement du cap en secondes (positif : plus tard) ; nil si l'une des photos n'en a pas.
    public let capShift: TimeInterval?
    /// Variation de l'avancement total ; nil si l'une des photos n'en a pas (HDV inconnu).
    public let totalChange: Double?

    public var totalLevelsGained: Int { levelsGained.reduce(0) { $0 + $1.count } }
    public var isEmpty: Bool {
        levelsGained.isEmpty && started.isEmpty && finished.isEmpty && added.isEmpty && removed.isEmpty
            && (capShift ?? 0) == 0 && (totalChange ?? 0) == 0
    }

    /// Un exemplaire : son niveau et s'il est en cours d'amélioration (minuteur illisible compris).
    private struct Unit { let level: Int; let upgrading: Bool }

    /// Les exemplaires de chaque type, du niveau le plus haut au plus bas, les améliorations en cours d'abord :
    /// l'exemplaire n°i d'une photo est comparé à l'exemplaire n°i de l'autre.
    private static func units(_ village: Village) -> [Int: [Unit]] {
        var result: [Int: [Unit]] = [:]
        for e in village.elements {
            result[e.itemID, default: []] += Array(repeating: Unit(level: e.level, upgrading: e.upgrading), count: e.count)
        }
        return result.mapValues { $0.sorted { ($0.level, $0.upgrading ? 1 : 0) > ($1.level, $1.upgrading ? 1 : 0) } }
    }

    public init(old: Village, oldSummary: PhotoSummary?, new: Village, newSummary: PhotoSummary?) {
        let swap = new.date < old.date
        let (a, b) = swap ? (new, old) : (old, new)
        let (sa, sb) = swap ? (newSummary, oldSummary) : (oldSummary, newSummary)
        let before = Self.units(a), after = Self.units(b)
        var gained: [ItemCount] = [], started: [ItemCount] = [], finished: [ItemCount] = []
        for id in Set(before.keys).union(after.keys).sorted() {
            let (x, y) = (before[id] ?? [], after[id] ?? [])
            var g = 0, s = 0, f = 0
            // shortcut: après une fusion, les exemplaires consommés sont inconnus, on compare par rang ; à revoir si l ecran veut le détail.
            for i in 0..<y.count {                         // les exemplaires disparus (i >= y.count) sont ignorés
                let prev = i < x.count ? x[i] : Unit(level: 0, upgrading: false)
                g += max(0, y[i].level - prev.level)
                let done = prev.upgrading && y[i].level > prev.level
                if done { f += 1 }
                if y[i].upgrading && !(prev.upgrading && y[i].level == prev.level) { s += 1 }
            }
            if g > 0 { gained.append(ItemCount(itemID: id, count: g)) }
            if s > 0 { started.append(ItemCount(itemID: id, count: s)) }
            if f > 0 { finished.append(ItemCount(itemID: id, count: f)) }
        }
        from = a.date
        to = b.date
        swapped = swap
        levelsGained = gained
        self.started = started
        self.finished = finished
        added = after.keys.filter { before[$0] == nil }.sorted()
        removed = before.keys.filter { after[$0] == nil }.sorted()
        capShift = both(sa?.cap, sb?.cap).map { $1.timeIntervalSince($0) }
        totalChange = both(sa?.total, sb?.total).map { $1 - $0 }
    }
}

private func both<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    if let a, let b { return (a, b) }
    return nil
}
