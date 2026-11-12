import SwiftUI

/// Maquette de l'écran Cap (PLAN §3.1) avec des données inventées, pour juger le thème.
/// Aucun lien avec ChantierKit : le vrai écran est la tâche T07.
struct MaquetteCap: View {
    var avecBandeau = false

    private let categories: [(String, Double)] = [
        ("Défenses", 0.71), ("Héros", 0.58), ("Labo", 0.62), ("Murs", 0.31),
        ("Pièges", 0.80), ("Économie", 0.92), ("Familiers", 0.45), ("Équipements", 0.27),
    ]

    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if avecBandeau {
                    BandeauAvertissement(titre: "Données du jeu à mettre à jour",
                                         message: "Ton village contient des niveaux que l'app ne connaît pas encore.")
                }
                VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                    GrandeDate(surtitre: "HDV 16 terminé", date: "le 14 mars",
                               mouvement: "2 jours de gagnés depuis mardi",
                               mention: "hors murs et équipements")

                    VStack(alignment: .leading, spacing: Theme.Espace.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Avancement total").etiquetteCarnet()
                            Spacer()
                            Text(0.64, format: .percent.precision(.fractionLength(0)))
                                .font(Theme.Police.chiffreGrand)
                        }
                        Jauge(valeur: 0.64)
                    }
                    .accessibilityElement(children: .combine)

                    CarteConsigne(texte: "Demain 14 h, deux ouvriers se libèrent. Lance l'Arc-X 11 et la Tour de sorts 4 : prépare 18 M d'or.") {}

                    VStack(alignment: .leading, spacing: Theme.Espace.m) {
                        Text("Catégories").etiquetteCarnet()
                        // Deux colonnes, une seule aux tailles d'accessibilité.
                        let colonnes = Array(repeating: GridItem(.flexible(), spacing: Theme.Espace.l, alignment: .leading),
                                             count: tailleTexte.isAccessibilitySize ? 1 : 2)
                        LazyVGrid(columns: colonnes, alignment: .leading, spacing: Theme.Espace.m) {
                            ForEach(categories, id: \.0) { LigneCategorie(nom: $0.0, valeur: $0.1) }
                        }
                    }
                }
                .padding(.horizontal, Theme.Espace.marge)
                .padding(.vertical, Theme.Espace.l)
            }
        }
        .pageCarnet()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Photo d'hier, 17\u{A0}h\u{A0}28")
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.encreDouce)
                    .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Réglages", systemImage: "gearshape") {}
            }
        }
    }
}

/// Les trois onglets standards autour de la maquette.
struct MaquetteOnglets: View {
    var avecBandeau = false

    var body: some View {
        TabView {
            Tab("Cap", systemImage: "scope") {
                NavigationStack { MaquetteCap(avecBandeau: avecBandeau) }
            }
            Tab("Chantier", systemImage: "hammer") {
                EtatVide(titre: "Le planning arrive", message: "Les couloirs des ouvriers viendront au jalon 2.",
                         symbole: "calendar").pageCarnet()
            }
            Tab("Village", systemImage: "house") {
                EtatVide(titre: "Le détail arrive", message: "Chaque bâtiment et chaque niveau, au jalon 1.",
                         symbole: "list.bullet").pageCarnet()
            }
        }
        .tint(Theme.Couleur.encre)
    }
}

#Preview("Cap") { MaquetteOnglets() }
#Preview("Cap, sombre") { MaquetteOnglets().preferredColorScheme(.dark) }
#Preview("Cap, très grande police") { MaquetteOnglets().dynamicTypeSize(.accessibility5) }
#Preview("Cap, avec bandeau") { MaquetteOnglets(avecBandeau: true) }
