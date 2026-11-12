import SwiftUI

/// Jauge du jeu : un creux arrondi cerclé de sombre, rempli d'or (ou de l'élixir de la catégorie), avec un reflet
/// sur le haut. `.grande` pour l'avancement total, `.fine` pour une catégorie.
struct Jauge: View {
    enum Taille { case grande, fine }

    /// Entre 0 et 1.
    let valeur: Double
    var taille: Taille = .grande
    var couleur: Color = Theme.Couleur.or

    @ScaledMetric(relativeTo: .body) private var hauteurGrande: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var hauteurFine: CGFloat = 8

    var body: some View {
        let h = taille == .grande ? min(hauteurGrande, 30) : min(hauteurFine, 14)
        let bord = taille == .grande ? Theme.bord : Theme.filet
        GeometryReader { geo in
            let v = min(max(valeur, 0), 1)
            // Un remplissage non nul garde au moins la largeur d'un rond, comme dans le jeu.
            let largeur = v == 0 ? 0 : max(h - 2 * bord, (geo.size.width - 2 * bord) * v)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Couleur.creux)
                Capsule().fill(couleur)
                    .overlay(alignment: .top) {
                        Capsule().fill(Theme.Couleur.reflet).frame(height: h * 0.25)
                            .padding(.horizontal, h * 0.3).padding(.top, h * 0.1)
                    }
                    .frame(width: largeur)
                    .padding(bord)
                Capsule().strokeBorder(Theme.Couleur.contour, lineWidth: bord)
            }
        }
        .frame(height: h)
        .accessibilityElement()
        .accessibilityLabel("Avancement")
        .accessibilityValue(Text(valeur, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview("Jauge") {
    VStack(alignment: .leading, spacing: Theme.Espace.l) {
        Jauge(valeur: 0)
        Jauge(valeur: 0.64)
        Jauge(valeur: 1)
        Jauge(valeur: 0.31, taille: .fine, couleur: Theme.Couleur.elixir)
    }
    .padding(Theme.Espace.marge)
    .pageChantier()
}
