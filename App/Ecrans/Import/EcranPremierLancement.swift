import ChantierKit
import SwiftUI

/// Le seul écran quand l'app n'a aucune photo : le chemin dans le jeu, le bouton de collage, l'exemple.
/// Aucune autorisation demandée : le bouton système de collage lit sans alerte.
struct EcranPremierLancement: View {
    @Environment(ModeleApp.self) private var modele
    @ScaledMetric(relativeTo: .body) private var pastille: CGFloat = 30

    private let etapes = [
        "Dans Clash of Clans, ouvre ton profil, puis Réglages.",
        "Touche Plus de réglages, puis Data Export.",
        "Touche Copier, puis reviens ici.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                VStack(alignment: .leading, spacing: Theme.Espace.m) {
                    // Le terrain vide, l'hôtel de ville le plus haut en fantôme : il attend ton village.
                    Terrain(hdv: 0, fantome: modele.reference?.maxTownHall ?? 1)
                        .padding(.bottom, Theme.Espace.s)
                    Text("Chantier")
                        .font(Theme.Police.grandeDate)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Copie l'export de ton village dans le jeu, puis reviens ici.")
                        .font(Theme.Police.surtitre)
                        .foregroundStyle(Theme.Couleur.texteDoux)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: Theme.Espace.m) {
                    Text("Dans le jeu").etiquetteChantier()
                    ForEach(Array(etapes.enumerated()), id: \.offset) { numero, texte in
                        HStack(alignment: .center, spacing: Theme.Espace.m) {
                            Text("\(numero + 1)")
                                .font(Theme.Police.chiffre)
                                .foregroundStyle(Theme.Couleur.surOr)
                                .frame(minWidth: pastille, minHeight: pastille)
                                .background(Theme.Couleur.or, in: .circle)
                                .overlay(Circle().strokeBorder(Theme.Couleur.contour, lineWidth: Theme.bord))
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
                        .foregroundStyle(Theme.Couleur.texteDoux)
                    Button("Voir un exemple") { modele.chargerExemple() }
                        .font(Theme.Police.texte)
                        .foregroundStyle(Theme.Couleur.elixirTexte)
                        .underline()
                        .padding(.top, Theme.Espace.s)
                }
            }
            .padding(.horizontal, Theme.Espace.marge)
            .padding(.vertical, Theme.Espace.xl)
        }
        .pageChantier()
    }
}

#Preview("Premier lancement") {
    EcranPremierLancement().environment(ModeleApp())
}
