import VillagePlannerKit
import SwiftUI

@main
struct VillagePlannerApp: App {
    @State private var modele = ModeleApp.partage
    @State private var conseil = ModeleConseil()
    @Environment(\.scenePhase) private var phase

    init() {
        Theme.Police.enregistrer()
    }

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environment(modele)
                .environment(conseil)
                // L'app est en français seulement : formats de dates et de pourcentages compris.
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .onChange(of: phase) { if phase == .active { modele.rafraichirPressePapiers(); modele.rafraichirPlan() } }
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
                .pagePlanner()
        } else if let affiche = modele.affiche, let reference = modele.reference {
            TabView(selection: $modele.onglet) {
                Tab("Cap", systemImage: "scope", value: OngletApp.cap) {
                    EcranCap(affiche: affiche, reference: reference)
                }
                Tab("Ouvriers", systemImage: "hammer", value: OngletApp.ouvriers) {
                    EcranOuvriers(affiche: affiche, reference: reference)
                }
                Tab("Village", systemImage: "house", value: OngletApp.village) {
                    EcranVillage(affiche: affiche, reference: reference)
                }
            }
            .tint(Theme.Couleur.elixirTexte)
        } else {
            EcranPremierLancement()
        }
    }
}

#Preview {
    RacineView().environment(ModeleApp()).environment(ModeleConseil())
}
