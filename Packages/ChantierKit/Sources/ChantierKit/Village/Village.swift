import Foundation

// Squelette du contrat §7.2. La fusion export + référence est la tâche T05.

/// Le village : fusion de l'export et de la référence.
public struct Village: Sendable {
    public let townHall: Int
    public let date: Date
    public let elements: [Element]
    public let workers: [WorkerKind: Int]
    public let unknown: [ExportEntry]              // identifiants absents de la référence (V5)
    public let status: VillageStatus               // .ok, .staleReference (V5, V6), .unknownTownHall (V7)

    public init(export: VillageExport, reference: ReferenceData) {
        // squelette : village vide, rempli par T05
        townHall = 0
        date = export.date
        elements = []
        workers = [:]
        unknown = []
        status = .ok
    }
}

public enum VillageStatus: Sendable, Equatable { case ok, staleReference, unknownTownHall }

/// Un groupe d'exemplaires identiques.
public struct Element: Sendable {
    public let itemID: Int
    public let level: Int                          // 0 : autorisé mais absent (V1, V3)
    public let count: Int                          // nombre d'exemplaires du groupe
    public let maxLevel: Int                       // à l'HDV actuel
    public let baseLevel: Int                      // maximum à l'HDV précédent
    public let upgradeEnds: Date?
}
