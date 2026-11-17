import VillagePlannerKit
import SwiftUI
import UIKit

/// L'icône d'une ressource du jeu (or, élixir, élixir noir, minerais), embarquée comme les autres images.
struct IconeRessource: View {
    let ressource: Resource
    var taille: CGFloat = 32

    /// Nom du fichier (`outils maj-images`) : `ressource-<nom en snake_case>.webp`.
    static func fichier(_ r: Resource) -> String {
        let nom = switch r {
        case .gold: "gold"
        case .elixir: "elixir"
        case .darkElixir: "dark_elixir"
        case .shinyOre: "shiny_ore"
        case .glowyOre: "glowy_ore"
        case .starryOre: "starry_ore"
        }
        return "ressource-\(nom).webp"
    }

    var body: some View {
        Group {
            if let image = UIImage(named: Self.fichier(ressource)) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "circle.fill").foregroundStyle(Theme.Couleur.or)
            }
        }
        .frame(width: taille, height: taille)
        .shadow(color: Theme.Couleur.ombre, radius: 1.5, y: 1.5)
        .accessibilityHidden(true)
    }
}

#Preview("Icônes de ressources") {
    HStack { ForEach(Resource.allCases, id: \.self) { IconeRessource(ressource: $0, taille: 40) } }
        .padding(Theme.Espace.marge)
        .pagePlanner()
}
