import ChantierKit
import SwiftUI

/// Une catégorie en tuile du jeu : son bâtiment au niveau du joueur, son nom, son avancement.
/// `valeur` nil : pas de pourcentage, `texte` le remplace (« rien à faire », « 12 éléments »).
struct TuileCategorie: View {
    let categorie: ChantierKit.Category
    let niveau: Int
    var valeur: Double? = nil
    var texte: String? = nil
    var lieu = "cap"

    @ScaledMetric(relativeTo: .body) private var image: CGFloat = 44

    var body: some View {
        HStack(spacing: Theme.Espace.s) {
            Illustration(id: categorie.representant, niveau: niveau, taille: min(image, 72), avecPastille: false, lieu: lieu)
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(categorie.nom).font(Theme.Police.texte).lineLimit(1).minimumScaleFactor(0.75)
                if let valeur {
                    HStack(spacing: Theme.Espace.s) {
                        Jauge(valeur: valeur, taille: .fine, couleur: categorie.couleur).accessibilityHidden(true)
                        Text(valeur, format: .percent.precision(.fractionLength(0)))
                            .font(Theme.Police.chiffre)
                            .foregroundStyle(valeur >= 1 ? Theme.Couleur.herbe : Theme.Couleur.texte)
                            .contentTransition(.numericText(value: valeur))
                            .fixedSize()
                    }
                } else if let texte {
                    Text(texte).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                }
            }
        }
        .padding(Theme.Espace.s)
        .tuileChantier()
        .accessibilityElement(children: .combine)
    }
}
