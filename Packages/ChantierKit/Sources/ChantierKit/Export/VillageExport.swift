import Foundation

// Squelette du contrat §7.2. Le lecteur réel est la tâche T03.

/// L'export lu : le JSON décodé, tout conservé.
public struct VillageExport: Sendable, Equatable {
    public let tag: String?
    public let date: Date
    public let sections: [String: [ExportEntry]]   // "buildings", "heroes"… connues ou non
    public let idLists: [String: [Int]]            // "skins", "house_parts"…
    public let boosts: [String: Int]
    public let warnings: [ExportWarning]           // ce qui a été ignoré ou réparé

    public static func parse(_ text: String) throws(ExportError) -> VillageExport {
        if text.allSatisfy(\.isWhitespace) { throw .empty }
        throw .notAVillageExport                   // squelette : le lecteur arrive avec T03
    }
}

public struct ExportEntry: Sendable, Equatable {
    public let id: Int
    public let level: Int?                         // absent pour décorations et obstacles
    public let count: Int                          // 1 si "cnt" est absent
    public let timer: Int?                         // secondes restantes à la date de l'export
    public let extras: [String: JSONValue]         // gear_up, weapon, helper_recurrent, champs inconnus
    public let children: [ExportEntry]             // "types" et "modules"
}

public enum ExportError: Error, Equatable { case empty, tooLarge, notJSON, notAVillageExport }

/// Ce que le lecteur a ignoré ou réparé. Détaillé par T03.
public struct ExportWarning: Sendable, Equatable {
    public let message: String
}

/// Une valeur JSON quelconque, pour garder les champs inconnus.
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
}
