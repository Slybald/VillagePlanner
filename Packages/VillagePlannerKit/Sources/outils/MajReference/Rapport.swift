import VillagePlannerKit
import Foundation

enum Rapport {
    /// Écriture canonique de reference.json : clés triées, un type par ligne (diffs lisibles),
    /// aucune date d'exécution. Même entrée, mêmes octets.
    static func encoder(_ r: ReferenceData) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func json<T: Encodable>(_ v: T) throws -> String { String(decoding: try e.encode(v), as: UTF8.self) }
        let items = try r.items.map(json).joined(separator: ",\n")
        return Data("""
            {"format":\(r.format),"maxTownHall":\(r.maxTownHall),"source":\(try json(r.source)),
            "items":[
            \(items)
            ]}

            """.utf8)
    }

    private static func json<T: Encodable>(_ v: T) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    }

    /// Ce qui a changé depuis la version précédente de reference.json.
    static func changements(avant: ReferenceData?, apres: ReferenceData) -> String {
        guard let avant else { return "Aucune version précédente : tout est nouveau (\(apres.items.count) types).\n" }
        var lignes: [String] = []
        let anciens = Set(avant.items.map(\.id)), nouveaux = Set(apres.items.map(\.id))
        let ajoutes = apres.items.filter { !anciens.contains($0.id) }
        let retires = avant.items.filter { !nouveaux.contains($0.id) }
        lignes.append("- Source : \(avant.source.commit.prefix(7)) du \(avant.source.date) → "
                      + "\(apres.source.commit.prefix(7)) du \(apres.source.date)")
        lignes.append("- Éléments ajoutés (\(ajoutes.count)) : "
                      + (ajoutes.isEmpty ? "aucun" : ajoutes.map { "\($0.id) \($0.name)" }.joined(separator: ", ")))
        lignes.append("- Éléments retirés (\(retires.count)) : "
                      + (retires.isEmpty ? "aucun" : retires.map { "\($0.id) \($0.name)" }.joined(separator: ", ")))
        var niveauxAjoutes: [String] = [], valeurs: [String] = []
        for n in apres.items {
            guard let a = avant.item(n.id) else { continue }
            let anciensNiveaux = Dictionary(uniqueKeysWithValues: a.levels.map { ($0.level, $0) })
            let nouveauxNiveaux = Set(n.levels.map(\.level))
            let plus = n.levels.map(\.level).filter { anciensNiveaux[$0] == nil }
            if !plus.isEmpty { niveauxAjoutes.append("\(n.id) \(n.name) : \(plus.map(String.init).joined(separator: ", "))") }
            let moins = a.levels.map(\.level).filter { !nouveauxNiveaux.contains($0) }
            if !moins.isEmpty { valeurs.append("\(n.id) \(n.name) : niveaux retirés \(moins)") }
            for l in n.levels {
                if let v = anciensNiveaux[l.level], json(v) != json(l) {
                    valeurs.append("\(n.id) \(n.name), niveau \(l.level) : `\(json(v))` → `\(json(l))`")
                }
            }
            for (champ, x, y) in [("nom", json(a.names), json(n.names)),
                                  ("catégorie", json(a.category), json(n.category)),
                                  ("hors avancement", json(a.exclusion), json(n.exclusion)),
                                  ("poste", json(a.worker), json(n.worker)),
                                  ("nombre par HDV", json(a.countByTownHall), json(n.countByTownHall)),
                                  ("maximum par HDV", json(a.maxLevelByTownHall), json(n.maxLevelByTownHall)),
                                  ("fusion", json(a.mergedFrom), json(n.mergedFrom))] where x != y {
                valeurs.append("\(n.id) \(n.name), \(champ) : `\(x)` → `\(y)`")
            }
        }
        lignes.append("- Niveaux ajoutés (\(niveauxAjoutes.count) types)" + liste(niveauxAjoutes))
        lignes.append("- Valeurs changées (\(valeurs.count))" + liste(valeurs))
        return lignes.joined(separator: "\n") + "\n"
    }

    private static func liste(_ l: [String]) -> String {
        l.isEmpty ? " : aucune" : " :\n" + l.map { "  - \($0)" }.joined(separator: "\n")
    }

    /// Écarts avec la seconde source, et les tableaux à l'HDV de contrôle.
    static func ecarts(_ r: ReferenceData, _ s: SecondeSource, hdvControle: Int = 16) -> String {
        let nombres = Controle.nombres(r, s), maximums = Controle.maximums(r, s)
        func tableau(_ lignes: [Controle.Ligne]) -> String {
            "| ID | Nom | ClashKing | chiefpansancolt | |\n|---|---|---|---|---|\n"
                + lignes.map { "| \($0.id) | \($0.nom) | \($0.clashKing) | \($0.chief) | \($0.clashKing == $0.chief ? "=" : "**écart**") |" }
                .joined(separator: "\n") + "\n"
        }
        func bilan(_ lignes: [Controle.Ligne]) -> String {
            let e = lignes.filter { $0.clashKing != $0.chief }
            return "\(lignes.count - e.count) valeurs identiques sur \(lignes.count)."
                + (e.isEmpty ? "\n" : " Écarts :\n" + e.map {
                    "- HDV \($0.hdv), \($0.id) \($0.nom) : ClashKing \($0.clashKing), chiefpansancolt \($0.chief)"
                }.joined(separator: "\n") + "\n")
        }
        let absents = r.items.filter { s.fiches[$0.id] == nil && $0.exclusion == nil }
            .map { "\($0.id) \($0.name)" }
        let ids = Set(r.items.map(\.id))
        let inconnus = s.fiches.values.filter { !ids.contains($0.id) }.sorted { $0.id < $1.id }.map { "\($0.id) \($0.nom)" }
        return """
            ### Nombres de bâtiments et de pièges, tous HDV
            \(bilan(nombres))
            ### Niveaux maximums, tous HDV
            \(bilan(maximums))
            ### Nombres à l'HDV \(hdvControle)
            \(tableau(nombres.filter { $0.hdv == hdvControle }))
            ### Maximums à l'HDV \(hdvControle)
            \(tableau(maximums.filter { $0.hdv == hdvControle }))
            ### Identifiants d'une seule source
            - Comptés par ClashKing, absents de chiefpansancolt : \(absents.isEmpty ? "aucun" : absents.joined(separator: ", "))
            - Dans chiefpansancolt, absents de ClashKing : \(inconnus.isEmpty ? "aucun" : inconnus.joined(separator: ", "))

            """
    }
}
