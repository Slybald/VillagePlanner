import ChantierKit

extension ChantierKit.Category {
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

    /// L'ordre d'affichage de la maquette (PLAN §3.1).
    static let ordreAffichage: [ChantierKit.Category] = [.defenses, .heroes, .laboratory, .walls, .traps, .economy, .pets, .equipment]
}
