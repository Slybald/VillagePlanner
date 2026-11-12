import Foundation

// Lecteur d'export (T03). Règle : jamais de plantage, une erreur typée ou une lecture avec avertissements.

extension VillageExport {
    /// Au-delà, le texte est refusé sans être décodé.
    public static let maxBytes = 1_000_000

    public static func parse(_ text: String) throws(ExportError) -> VillageExport {
        if text.utf8.count > maxBytes { throw .tooLarge }
        let sansBOM = text.drop(while: { $0 == "\u{FEFF}" })
        if sansBOM.firstIndex(where: { !$0.isWhitespace }) == nil { throw .empty }

        let racine: Any
        do {
            racine = try JSONSerialization.jsonObject(with: Data(sansBOM.utf8), options: [.fragmentsAllowed])
        } catch {
            throw .notJSON
        }
        guard case .object(let objet) = JSONValue(any: racine) else { throw .notAVillageExport }
        return try ExportReader.lire(objet)
    }
}

extension JSONValue {
    /// Convertit le résultat de `JSONSerialization` (Darwin : les booléens sont des `CFBoolean`).
    init(any: Any) {
        switch any {
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map(JSONValue.init(any:)))
        case let o as [String: Any]: self = .object(o.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }

    /// Entier exact et raisonnable (|x| ≤ 2^53), sinon nil : « valeur extrême » ou non entière.
    fileprivate var entier: Int? {
        guard case .number(let d) = self, d == d.rounded(.towardZero), abs(d) <= 9_007_199_254_740_992
        else { return nil }
        return Int(d)
    }
}

struct Avertissements {
    static let maximum = 200
    private(set) var liste: [ExportWarning] = []
    private var plein = false

    mutating func ajouter(_ kind: ExportWarning.Kind, _ section: String?, id: Int? = nil,
                          field: String? = nil, _ message: String) {
        if liste.count < Self.maximum {
            liste.append(ExportWarning(kind: kind, section: section, id: id, field: field, message: message))
        } else if !plein {
            plein = true
            liste.append(ExportWarning(kind: .truncated, section: nil, message: "trop d'avertissements, les suivants sont omis"))
        }
    }
}

private enum ExportReader {
    static let profondeurMax = 4   // types → modules → … ; au-delà, conservé tel quel dans `extras`

    static let basesEntrees = ["buildings", "traps", "units", "siege_machines", "spells", "heroes",
                               "pets", "equipment", "helpers", "guardians", "decos", "obstacles"]
    static let basesIdentifiants = ["skins", "sceneries", "house_parts"]
    static let sectionsEntrees = Set(basesEntrees + basesEntrees.map { $0 + "2" })
    static let sectionsIdentifiants = Set(basesIdentifiants + basesIdentifiants.map { $0 + "2" })

    static func lire(_ racine: [String: JSONValue]) throws(ExportError) -> VillageExport {
        guard case .number(let t)? = racine["timestamp"], t.isFinite, t >= 0, t <= 1e11
        else { throw .notAVillageExport }

        var w = Avertissements()
        var tag: String?
        var sections: [String: [ExportEntry]] = [:]
        var idLists: [String: [Int]] = [:]
        var boosts: [String: Int] = [:]
        var extras: [String: JSONValue] = [:]
        var connues = 0

        for (cle, valeur) in racine.sorted(by: { $0.key < $1.key }) {
            switch cle {
            case "timestamp":
                break
            case "tag":
                if case .string(let s) = valeur { tag = s } else if valeur != .null {
                    w.ajouter(.fieldIgnored, nil, field: "tag", "tag qui n'est pas du texte")
                }
            case "boosts":
                guard case .object(let o) = valeur else {
                    extras[cle] = valeur
                    w.ajouter(.malformedSection, cle, "boosts qui n'est pas un objet")
                    continue
                }
                for (nom, v) in o.sorted(by: { $0.key < $1.key }) {
                    if let n = v.entier { boosts[nom] = n } else {
                        w.ajouter(.fieldIgnored, cle, field: nom, "valeur de boost illisible")
                    }
                }
            case _ where sectionsEntrees.contains(cle):
                guard case .array(let a) = valeur else {
                    extras[cle] = valeur
                    w.ajouter(.malformedSection, cle, "section qui n'est pas une liste")
                    continue
                }
                sections[cle] = a.compactMap { entree($0, section: cle, profondeur: 0, &w) }
                connues += 1
            case _ where sectionsIdentifiants.contains(cle):
                guard case .array(let a) = valeur else {
                    extras[cle] = valeur
                    w.ajouter(.malformedSection, cle, "section qui n'est pas une liste")
                    continue
                }
                idLists[cle] = identifiants(a, section: cle, &w)
                connues += 1
            default:
                w.ajouter(.unknownSection, cle, "section inconnue, conservée")
                rangerInconnue(cle, valeur, &sections, &idLists, &extras, &w)
            }
        }
        guard connues > 0 else { throw .notAVillageExport }
        return VillageExport(tag: tag, date: Date(timeIntervalSince1970: t), sections: sections,
                             idLists: idLists, boosts: boosts, warnings: w.liste, extras: extras)
    }

    /// Liste d'objets : entrées ; liste d'entiers : identifiants ; le reste : `extras`.
    static func rangerInconnue(_ cle: String, _ valeur: JSONValue, _ sections: inout [String: [ExportEntry]],
                               _ idLists: inout [String: [Int]], _ extras: inout [String: JSONValue],
                               _ w: inout Avertissements) {
        guard case .array(let a) = valeur else { extras[cle] = valeur; return }
        if a.allSatisfy({ if case .object = $0 { true } else { false } }) {
            sections[cle] = a.compactMap { entree($0, section: cle, profondeur: 0, &w) }
        } else if a.allSatisfy({ $0.entier != nil }) {
            idLists[cle] = identifiants(a, section: cle, &w)
        } else {
            extras[cle] = valeur
        }
    }

    static func identifiants(_ a: [JSONValue], section: String, _ w: inout Avertissements) -> [Int] {
        a.compactMap { v in
            if let n = v.entier, n >= 0 { return n }
            w.ajouter(.fieldIgnored, section, field: "data", "identifiant illisible, écarté")
            return nil
        }
    }

    /// nil : élément écarté (avertissement ajouté). Jamais corrigé.
    static func entree(_ v: JSONValue, section: String, profondeur: Int, _ w: inout Avertissements) -> ExportEntry? {
        guard case .object(var o) = v else {
            w.ajouter(.entryDropped, section, "élément qui n'est pas un objet")
            return nil
        }
        guard let id = o.removeValue(forKey: "data")?.entier, id >= 0 else {
            w.ajouter(.entryDropped, section, field: "data", "identifiant (data) absent ou illisible")
            return nil
        }
        var level: Int?
        if let brut = o.removeValue(forKey: "lvl") {
            guard let n = brut.entier, n >= 0 else {
                w.ajouter(.entryDropped, section, id: id, field: "lvl", "niveau illisible ou négatif, élément écarté")
                return nil
            }
            level = n
        }
        var count = 1
        if let brut = o.removeValue(forKey: "cnt") {
            guard let n = brut.entier, n >= 1 else {
                w.ajouter(.entryDropped, section, id: id, field: "cnt", "nombre illisible ou inférieur à 1, élément écarté")
                return nil
            }
            count = n
        }
        var timer: Int?
        if let brut = o.removeValue(forKey: "timer") {
            if let n = brut.entier, n >= 0 { timer = n } else {
                w.ajouter(.fieldIgnored, section, id: id, field: "timer", "minuteur illisible, retiré")
            }
        }
        var enfants: [ExportEntry] = []
        for cle in ["types", "modules"] {
            guard let brut = o.removeValue(forKey: cle) else { continue }
            if case .array(let a) = brut, profondeur < profondeurMax {
                enfants += a.compactMap { entree($0, section: section, profondeur: profondeur + 1, &w) }
            } else {
                o[cle] = brut   // conservé tel quel
                w.ajouter(.fieldIgnored, section, id: id, field: cle, "\(cle) non lisible, conservé dans extras")
            }
        }
        return ExportEntry(id: id, level: level, count: count, timer: timer, extras: o, children: enfants)
    }
}
