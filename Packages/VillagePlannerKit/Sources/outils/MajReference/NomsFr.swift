import VillagePlannerKit
import Foundation

// Noms français : `Ressources/noms-fr.json` (identifiant → nom) rangé à la main, fusionné dans
// `names["fr"]` à chaque `maj-reference`. Un élément avec une catégorie sans nom est signalé.

enum NomsFr {
    static let fichier = MajReference.paquet
        .appendingPathComponent("Sources/VillagePlannerKit/Reference/Ressources/noms-fr.json")

    static func lire(_ url: URL = fichier) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    /// Renvoie la référence avec `names["fr"]` renseigné, et les identifiants comptés (avec catégorie) sans nom.
    static func fusionner(_ r: ReferenceData, noms: [String: String]) -> (ReferenceData, sansNom: [Int]) {
        var sansNom: [Int] = []
        let items = r.items.map { it -> ReferenceItem in
            var names = it.names
            if let nom = noms[String(it.id)] {
                names["fr"] = nom
            } else if it.category != nil {
                sansNom.append(it.id)
            }
            return ReferenceItem(id: it.id, names: names, section: it.section, category: it.category,
                                 exclusion: it.exclusion, worker: it.worker, levels: it.levels,
                                 countByTownHall: it.countByTownHall, maxLevelByTownHall: it.maxLevelByTownHall,
                                 mergedFrom: it.mergedFrom)
        }
        return (ReferenceData(items: items, source: r.source, maxTownHall: r.maxTownHall, format: r.format), sansNom)
    }
}
