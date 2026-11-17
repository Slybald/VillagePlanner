import SwiftUI

/// Une catégorie et son avancement.
struct LigneCategorie: View {
    let nom: String
    /// Entre 0 et 1.
    let valeur: Double
    /// Une jauge fine sous la ligne (écran Village) ; sans, sur le Cap.
    var avecJauge = false
    var couleur: Color = Theme.Couleur.or

    var body: some View {
        VStack(spacing: Theme.Espace.xs) {
            HStack(alignment: .lastTextBaseline, spacing: Theme.Espace.xs) {
                Text(nom).font(Theme.Police.texte).layoutPriority(1)
                Spacer(minLength: Theme.Espace.m)
                Text(valeur, format: .percent.precision(.fractionLength(0)))
                    .font(Theme.Police.chiffre)
                    .fixedSize()
                    .foregroundStyle(valeur >= 1 ? Theme.Couleur.herbe : Theme.Couleur.texte)
            }
            if avecJauge {
                Jauge(valeur: valeur, taille: .fine, couleur: couleur).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Ligne de catégorie") {
    VStack(spacing: Theme.Espace.m) {
        LigneCategorie(nom: "Défenses", valeur: 0.71)
        LigneCategorie(nom: "Murs", valeur: 0.31, avecJauge: true)
        LigneCategorie(nom: "Pièges", valeur: 1)
    }
    .padding(Theme.Espace.marge)
    .pagePlanner()
}
