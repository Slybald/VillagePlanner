import VillagePlannerKit
import SwiftUI

extension VillagePlannerKit.Category {
    /// Le nom affiché (l'app est en français ; les éléments, eux, gardent les noms anglais de la référence).
    var nom: String {
        switch self {
        case .defenses: "Défenses"
        case .traps: "Pièges"
        case .economy: "Économie"
        case .walls: "Murs"
        case .heroes: "Héros"
        case .laboratory: "Labo"
        case .pets: "Familiers"
        case .equipment: "Équipements"
        }
    }

    /// La ressource qui paie l'essentiel de la catégorie : sa couleur de jauge.
    var couleur: Color {
        switch self {
        case .defenses, .traps, .economy, .walls: Theme.Couleur.or
        case .laboratory: Theme.Couleur.elixir
        case .heroes, .pets: Theme.Couleur.elixirNoir
        case .equipment: Theme.Couleur.ciel
        }
    }

    /// Le bâtiment (ou le héros) qui représente la catégorie, dessiné au niveau du joueur.
    var representant: Int {
        switch self {
        case .defenses: 1000008      // canon
        case .traps: 12000000        // bombe
        case .economy: 1000005       // réserve d'or
        case .walls: 1000010         // rempart
        case .heroes: 28000000       // roi des barbares
        case .laboratory: 1000007    // laboratoire
        case .pets: 1000068          // maison des familiers
        case .equipment: 1000070     // forge
        }
    }

    /// L'ordre d'affichage de la maquette (PLAN §3.1).
    static let ordreAffichage: [VillagePlannerKit.Category] = [.defenses, .heroes, .laboratory, .walls, .traps, .economy, .pets, .equipment]
}
