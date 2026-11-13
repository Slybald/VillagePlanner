import ChantierKit
import SwiftUI

@main
struct ChantierApp: App {
    @State private var modele = ModeleApp()
    @State private var conseil = ModeleConseil()
    @Environment(\.scenePhase) private var phase

    init() {
        Theme.Police.enregistrer()
        ecrireEssaiConteneur()
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

/// Première étape de T25 : écrit dans le conteneur partagé un texte que le widget affiche.
/// Sans l'App Group (compte refusé, signature absente), `containerURL` rend nil et rien n'est écrit.
private func ecrireEssaiConteneur() {
    guard let id = Bundle.main.bundleIdentifier,
          let dossier = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + id) else { return }
    let texte = "Conteneur partagé : OK\nécrit par l'app à " + Date.now.formatted(date: .omitted, time: .shortened)
    try? texte.write(to: dossier.appending(path: "essai.txt"), atomically: true, encoding: .utf8)
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
                .pageChantier()
        } else if let affiche = modele.affiche, let reference = modele.reference {
            TabView(selection: $modele.onglet) {
                Tab("Cap", systemImage: "scope", value: OngletApp.cap) {
                    EcranCap(affiche: affiche, reference: reference)
                }
                Tab("Chantier", systemImage: "hammer", value: OngletApp.chantier) {
                    EcranChantier(affiche: affiche, reference: reference)
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
