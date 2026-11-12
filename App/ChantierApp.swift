import ChantierKit
import SwiftUI

@main
struct ChantierApp: App {
    @State private var modele = ModeleApp()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environment(modele)
                // L'app est en français seulement : formats de dates et de pourcentages compris.
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .onChange(of: phase) { if phase == .active { modele.rafraichirPressePapiers() } }
        }
    }
}

/// Premier lancement, ou les trois onglets.
struct RacineView: View {
    @Environment(ModeleApp.self) private var modele

    var body: some View {
        @Bindable var modele = modele
        if modele.reference == nil {
            EtatVide(titre: "Données du jeu illisibles",
                     message: "Le fichier de données embarqué est absent ou abîmé. Réinstalle l'app.",
                     symbole: "exclamationmark.triangle")
                .pageCarnet()
        } else if let affiche = modele.affiche, let reference = modele.reference {
            TabView(selection: $modele.onglet) {
                Tab("Cap", systemImage: "scope", value: OngletApp.cap) {
                    EcranCap(affiche: affiche, reference: reference)
                }
                Tab("Chantier", systemImage: "hammer", value: OngletApp.chantier) {
                    PageProvisoire(titre: "Le planning arrive", message: "Les couloirs des ouvriers viendront au jalon 2.",
                                   symbole: "calendar", estExemple: affiche.estExemple)
                }
                Tab("Village", systemImage: "house", value: OngletApp.village) {
                    PageProvisoire(titre: "Le détail arrive", message: "Chaque bâtiment et chaque niveau, au jalon 1.",
                                   symbole: "list.bullet", estExemple: affiche.estExemple)
                }
            }
            .tint(Theme.Couleur.encre)
        } else {
            EcranPremierLancement()
        }
    }
}

#Preview {
    RacineView().environment(ModeleApp())
}
