import Foundation

// Contrat §7.2. Le lecteur est dans ExportReader.swift.

/// L'export lu : le JSON décodé, tout conservé.
public struct VillageExport: Sendable, Equatable {
    public let tag: String?
    public let date: Date
    public let sections: [String: [ExportEntry]]   // "buildings", "heroes"… connues ou non
    public let idLists: [String: [Int]]            // "skins", "house_parts"…
    public let boosts: [String: Int]
    public let warnings: [ExportWarning]           // ce qui a été ignoré ou réparé
    /// Clés de la racine (ou sections mal formées) qui ne rentrent dans aucun des champs ci-dessus.
    public let extras: [String: JSONValue]

    public init(tag: String?, date: Date, sections: [String: [ExportEntry]],
                idLists: [String: [Int]], boosts: [String: Int],
                warnings: [ExportWarning], extras: [String: JSONValue] = [:]) {
        self.tag = tag
        self.date = date
        self.sections = sections
        self.idLists = idLists
        self.boosts = boosts
        self.warnings = warnings
        self.extras = extras
    }
}

public struct ExportEntry: Sendable, Equatable {
    public let id: Int
    public let level: Int?                         // absent pour décorations et obstacles
    public let count: Int                          // 1 si "cnt" est absent
    public let timer: Int?                         // secondes restantes à la date de l'export
    public let extras: [String: JSONValue]         // gear_up, weapon, helper_recurrent, champs inconnus
    public let children: [ExportEntry]             // "types" et "modules"

    public init(id: Int, level: Int? = nil, count: Int = 1, timer: Int? = nil,
                extras: [String: JSONValue] = [:], children: [ExportEntry] = []) {
        self.id = id
        self.level = level
        self.count = count
        self.timer = timer
        self.extras = extras
        self.children = children
    }
}

public enum ExportError: Error, Equatable { case empty, tooLarge, notJSON, notAVillageExport }

/// Ce que le lecteur a ignoré ou réparé. Un test lit `kind`, `section`, `id` et `field`, jamais `message`.
public struct ExportWarning: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case unknownSection      // clé de la racine inconnue : conservée
        case malformedSection    // section connue de forme inattendue : conservée dans `extras`
        case entryDropped        // élément écarté (absent du résultat), jamais corrigé
        case fieldIgnored        // champ invalide d'un élément conservé : champ retiré
        case truncated           // trop d'avertissements : les suivants ne sont pas gardés
    }
    public let kind: Kind
    public let section: String?                    // nil : racine
    public let id: Int?                            // `data` de l'élément, s'il est lisible
    public let field: String?                      // "lvl", "cnt", "timer", "data"…
    public let message: String                     // pour l'humain

    public init(kind: Kind, section: String?, id: Int? = nil, field: String? = nil, message: String) {
        self.kind = kind
        self.section = section
        self.id = id
        self.field = field
        self.message = message
    }
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
