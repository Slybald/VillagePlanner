import ChantierKit
import Foundation

/// Un élément du village avec sa fiche de référence et ce qui lui reste à faire.
struct ElementAffiche {
    let element: Element
    let fiche: ReferenceItem

    /// Niveaux restant jusqu'au maximum de l'HDV, pour un exemplaire. Un niveau en cours n'est pas fait.
    var restants: Int { max(0, element.maxLevel - element.level) }
    var estTermine: Bool { restants == 0 }
    /// Le critère de tri : niveaux restants sur l'ensemble des exemplaires.
    var reste: Int { restants * element.count }
}

enum Elements {
    /// Les éléments d'une catégorie (un groupe par niveau), les plus chargés d'abord, puis par nom.
    /// Les éléments hors avancement (catégorie nil) n'y sont jamais.
    static func de(_ categorie: ChantierKit.Category, village: Village, reference: ReferenceData) -> [ElementAffiche] {
        regroupes(village.elements)
            .compactMap { e in reference.item(e.itemID).map { ElementAffiche(element: e, fiche: $0) } }
            .filter { $0.fiche.category == categorie }
            .sorted { ($1.reste, $0.fiche.name, $0.element.level) < ($0.reste, $1.fiche.name, $1.element.level) }
    }
}

extension Elements {
    /// Regroupe les exemplaires identiques (même type, même niveau, même minuteur) venus d'entrées séparées de l'export.
    static func regroupes(_ elements: [Element]) -> [Element] {
        var resultat: [Element] = []
        for e in elements {
            if let i = resultat.firstIndex(where: {
                $0.itemID == e.itemID && $0.level == e.level && $0.upgrading == e.upgrading && $0.upgradeEnds == e.upgradeEnds
            }) {
                let a = resultat[i]
                resultat[i] = Element(itemID: a.itemID, level: a.level, count: a.count + e.count, maxLevel: a.maxLevel,
                                      baseLevel: a.baseLevel, upgradeEnds: a.upgradeEnds, upgrading: a.upgrading)
            } else {
                resultat.append(e)
            }
        }
        return resultat
    }
}
