import SwiftUI

/// Le seul écran quand l'app n'a aucune photo : le chemin dans le jeu, le bouton de collage, l'exemple.
/// Aucune autorisation demandée : le bouton système de collage lit sans alerte.
struct EcranPremierLancement: View {
    @Environment(ModeleApp.self) private var modele

    private let etapes = [
        "Dans Clash of Clans, ouvre ton profil, puis Réglages.",
        "Touche Plus de réglages, puis Data Export.",
        "Touche Copier, puis reviens ici.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                VStack(alignment: .leading, spacing: Theme.Espace.m) {
                    Text("Chantier")
                        .font(Theme.Police.date(52))
                    Text("Copie l'export de ton village dans le jeu, puis reviens ici.")
                        .font(Theme.Police.surtitre)
                        .foregroundStyle(Theme.Couleur.encreDouce)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: Theme.Espace.m) {
                    Text("Dans le jeu").etiquetteCarnet()
                    ForEach(Array(etapes.enumerated()), id: \.offset) { numero, texte in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
                            Text("\(numero + 1)")
                                .font(Theme.Police.chiffreGrand)
                                .frame(minWidth: 24, alignment: .leading)
                                .accessibilityHidden(true)
                            Text(texte).font(Theme.Police.texte)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Espace.m) {
                    if let retour = modele.retour {
                        CarteRetour(retour: retour)
                    }
                    BoutonColler()
                    Text("Le bouton s'allume quand un texte est copié.")
                        .font(Theme.Police.detail)
                        .foregroundStyle(Theme.Couleur.encreDouce)
                    Button("Voir un exemple") { modele.chargerExemple() }
                        .font(Theme.Police.texte)
                        .underline()
                        .padding(.top, Theme.Espace.s)
                }
            }
            .padding(.horizontal, Theme.Espace.marge)
            .padding(.vertical, Theme.Espace.xl)
        }
        .pageCarnet()
    }
}

#Preview("Premier lancement") {
    EcranPremierLancement().environment(ModeleApp())
}
