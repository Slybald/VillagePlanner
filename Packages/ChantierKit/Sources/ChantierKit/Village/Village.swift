import Foundation

/// Le village : fusion de l'export et de la référence (règles V1 à V8, PLAN §5.0).
public struct Village: Sendable {
    public let townHall: Int
    public let date: Date
    public let elements: [Element]
    public let workers: [WorkerKind: Int]
    public let unknown: [ExportEntry]              // identifiants absents de la référence (V5)
    public let status: VillageStatus               // .ok, .staleReference (V5, V6), .unknownTownHall (V7)

    /// Identifiant de l'hôtel de ville, dans la référence comme dans l'export.
    public static let townHallID = 1000001

    /// Sections du village principal. Les sections `*2` (base des ouvriers, V8), les décorations,
    /// les obstacles et les sections inconnues restent dans l'export, hors du village.
    static let sections = ["buildings", "traps", "units", "siege_machines", "spells", "heroes",
                           "pets", "equipment", "helpers", "guardians"]
    /// Sections dont un type déblocable mais absent s'ajoute au niveau 0 (V3).
    static let unlockSections: Set = ["units", "siege_machines", "spells", "heroes", "pets"]
    /// Bâtiments qui donnent un poste : cabanes d'ouvrier et B.O.B., labo, Maison des familiers, Forgeron.
    static let posts: [(id: Int, kind: WorkerKind)] = [(1000015, .builder), (1000064, .builder),
                                                       (1000007, .laboratory), (1000068, .petHouse),
                                                       (1000070, .blacksmith)]

    public init(export: VillageExport, reference: ReferenceData) {
        let entries = Self.sections.flatMap { export.sections[$0] ?? [] }
        let th = entries.filter { $0.id == Self.townHallID }.compactMap(\.level).max() ?? 0
        let thKnown = th >= 1 && th <= reference.maxTownHall      // sinon V7
        var elements: [Element] = []
        var unknown: [ExportEntry] = []
        var stale = false
        var present: [Int: Int] = [:]                             // exemplaires présents par type

        for entry in entries {
            guard let item = reference.item(entry.id) else {
                unknown.append(entry)                             // V5
                stale = true
                continue
            }
            let level = entry.level ?? 0
            // Minuteur illisible gardé brut par le lecteur : en cours, fin inconnue, jamais terminé.
            let upgrading = entry.timer != nil || entry.extras["timer"] != nil
            // V4 : un équipement au niveau 1 est tenu pour non possédé.
            if item.category == .equipment, level <= 1, !upgrading { continue }
            if level > (item.levels.map(\.level).max() ?? 0) { stale = true }   // V6
            present[item.id, default: 0] += entry.count
            elements.append(Element(item: item, townHall: th, level: level, count: entry.count,
                                    upgradeEnds: entry.timer.map { export.date.addingTimeInterval(TimeInterval($0)) },
                                    upgrading: upgrading))
        }

        if thKnown {
            // V2 : chaque bâtiment fusionné présent retire les exemplaires qu'il a consommés.
            var consumed: [Int: Int] = [:]
            for item in reference.items {
                for requirement in item.mergedFrom { consumed[requirement.itemID, default: 0] += present[item.id] ?? 0 }
            }
            // V1, V3. V8 : un type sans catégorie (hors avancement) n'est jamais ajouté.
            for item in reference.items where item.category != nil {
                var missing = 0
                if item.section == "buildings" || item.section == "traps" {
                    missing = item.count(atTownHall: th) - (consumed[item.id] ?? 0) - (present[item.id] ?? 0)
                } else if Self.unlockSections.contains(item.section), present[item.id] == nil,
                          item.maxLevel(atTownHall: th) > 0 {
                    missing = 1
                }
                if missing > 0 {
                    elements.append(Element(item: item, townHall: th, level: 0, count: missing,
                                            upgradeEnds: nil, upgrading: false))
                }
            }
        }

        var workers: [WorkerKind: Int] = [:]
        for post in Self.posts {
            let n = elements.filter { $0.itemID == post.id && $0.level > 0 }.reduce(0) { $0 + $1.count }
            if n > 0 { workers[post.kind, default: 0] += n }
        }

        townHall = th
        date = export.date
        self.elements = elements
        self.workers = workers
        self.unknown = unknown
        status = !thKnown ? .unknownTownHall : stale ? .staleReference : .ok
    }
}

public enum VillageStatus: Sendable, Equatable { case ok, staleReference, unknownTownHall }

/// Un groupe d'exemplaires identiques.
public struct Element: Sendable, Equatable {
    public let itemID: Int
    public let level: Int                          // 0 : autorisé mais absent (V1, V3)
    public let count: Int                          // nombre d'exemplaires du groupe
    public let maxLevel: Int                       // à l'HDV actuel
    public let baseLevel: Int                      // maximum à l'HDV précédent
    public let upgradeEnds: Date?
    /// En cours d'amélioration vers `level + 1`, même quand la fin est inconnue (minuteur illisible).
    public let upgrading: Bool

    public init(itemID: Int, level: Int, count: Int, maxLevel: Int, baseLevel: Int,
                upgradeEnds: Date? = nil, upgrading: Bool? = nil) {
        self.itemID = itemID
        self.level = level
        self.count = count
        self.maxLevel = maxLevel
        self.baseLevel = baseLevel
        self.upgradeEnds = upgradeEnds
        self.upgrading = upgrading ?? (upgradeEnds != nil)
    }

    init(item: ReferenceItem, townHall: Int, level: Int, count: Int, upgradeEnds: Date?, upgrading: Bool) {
        let max = item.maxLevel(atTownHall: townHall)
        // L'HDV atteint définit le chemin (D4) : son propre niveau n'est jamais « à faire » à cet HDV.
        let base = item.id == Village.townHallID ? max : item.maxLevel(atTownHall: townHall - 1)
        self.init(itemID: item.id, level: level, count: count, maxLevel: max, baseLevel: base,
                  upgradeEnds: upgradeEnds, upgrading: upgrading)
    }
}
