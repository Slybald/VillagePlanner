import VillagePlannerKit
import Foundation

// Second avis : chiefpansancolt/clash-of-clans-data (MIT), saisie à la main. On en tire, pour chaque
// identifiant (`dataId`), le nombre de bâtiments par HDV (valeur absolue, avant fusions) et le niveau
// maximum par HDV calculé avec la même règle de prérequis, puis on liste les écarts.

struct SecondeSource {
    struct Fiche {
        let id: Int
        let nom: String
        let nombres: [Int: Int]                    // HDV → nombre
        let niveaux: [[String: Int]]               // champs entiers de chaque niveau
    }
    let fiches: [Int: Fiche]

    static func lire(dossier: URL) throws -> SecondeSource {
        let fm = FileManager.default
        let chemins = (fm.enumerator(atPath: dossier.path)?.compactMap { $0 as? String } ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
        var fiches: [Int: Fiche] = [:]
        for chemin in chemins {
            let data = try Data(contentsOf: dossier.appendingPathComponent(chemin))
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = o["dataId"] as? Int, fiches[id] == nil else { continue }
            let nombres = (o["availablePerTownHall"] as? [[String: Any]] ?? []).reduce(into: [Int: Int]()) { r, e in
                if let n = e["townHallLevel"] as? Int, let c = e["count"] as? Int { r[n] = c }
            }
            // Les paliers de supercharge suivent les niveaux et recommencent à 1 : on s'arrête là.
            var niveaux: [[String: Int]] = []
            for n in (o["levels"] as? [[String: Any]] ?? []).map({ $0.compactMapValues { $0 as? Int } }) {
                guard (n["level"] ?? 0) > (niveaux.last?["level"] ?? 0) else { break }
                niveaux.append(n)
            }
            fiches[id] = Fiche(id: id, nom: o["name"] as? String ?? "?", nombres: nombres, niveaux: niveaux)
        }
        return SecondeSource(fiches: fiches)
    }

    /// Bâtiments et pièges : la fiche a un nombre par HDV.
    func place(_ id: Int) -> Bool { !(fiches[id]?.nombres.isEmpty ?? true) }

    func nombre(_ id: Int, _ hdv: Int) -> Int? {
        guard let f = fiches[id], !f.nombres.isEmpty else { return nil }
        return f.nombres[hdv] ?? 0
    }

    /// Même règle que la conversion : plus haut niveau dont les prérequis tiennent à l'HDV `hdv`.
    func maximum(_ id: Int, _ hdv: Int) -> Int? {
        if id == ConversionClashKing.hdv { return hdv }
        guard let f = fiches[id] else { return nil }
        if place(id) && (nombre(id, hdv) ?? 0) == 0 { return 0 }
        let batiments = ["laboratoryRequired": ConversionClashKing.labo,
                         "heroHallLevelRequired": ConversionClashKing.hallDesHeros,
                         "petHouseLevelRequired": ConversionClashKing.maisonDesFamiliers,
                         "blacksmithLevelRequired": ConversionClashKing.forgeron]
        var max = 0
        for n in f.niveaux {
            guard (n["townHallRequired"] ?? 0) <= hdv else { break }
            let ok = batiments.allSatisfy { cle, b in (n[cle] ?? 0) <= 0 || (maximum(b, hdv) ?? 0) >= n[cle]! }
            guard ok, let niveau = n["level"] else { break }
            max = niveau
        }
        return max
    }
}

enum Controle {
    struct Ligne { let id: Int; let nom: String; let hdv: Int; let clashKing: Int; let chief: Int }

    /// Nombres de bâtiments et pièges, à chaque HDV, pour les identifiants des deux sources.
    static func nombres(_ r: ReferenceData, _ s: SecondeSource) -> [Ligne] {
        r.items.filter { ["buildings", "traps", "guardians"].contains($0.section) && s.place($0.id) }
            .flatMap { i in
                (1...r.maxTownHall).map { Ligne(id: i.id, nom: i.name, hdv: $0, clashKing: i.count(atTownHall: $0),
                                                chief: s.nombre(i.id, $0) ?? 0) }
            }
    }

    /// Niveaux maximums, à chaque HDV, pour les identifiants des deux sources.
    static func maximums(_ r: ReferenceData, _ s: SecondeSource) -> [Ligne] {
        r.items.filter { s.fiches[$0.id] != nil }
            .flatMap { i in
                (1...r.maxTownHall).compactMap { n in
                    s.maximum(i.id, n).map { Ligne(id: i.id, nom: i.name, hdv: n, clashKing: i.maxLevel(atTownHall: n), chief: $0) }
                }
            }
    }
}
