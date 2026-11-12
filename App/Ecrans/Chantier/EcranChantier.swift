import ChantierKit
import SwiftUI

/// L'écran Chantier (PLAN §3.2) : ce qu'il faut réunir, puis un couloir par ouvrier, un pour le labo, un pour les familiers.
struct EcranChantier: View {
    let affiche: VillageAffiche
    let reference: ReferenceData

    @State private var ouverts: Set<String> = Self.ouvertsDeCapture()

    /// Débogage seulement : `-couloir <poste-numéro>` (par exemple `builder-0`) déroule ce couloir au lancement (captures).
    private static func ouvertsDeCapture() -> Set<String> {
        #if DEBUG
        if let id = UserDefaults.standard.string(forKey: "couloir") { return [id] }
        #endif
        return []
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = affiche.plan {
                    ScrollViewReader { proxy in
                        ScrollView { planning(plan) }
                        #if DEBUG
                        .task { if let id = ouverts.first { proxy.scrollTo(id, anchor: .top) } }   // captures
                        #endif
                    }
                } else {
                    VStack(spacing: 0) {
                        if affiche.estExemple { MarqueExemple() }
                        EtatVide(titre: "Pas de planning", message: "L'app ne connaît pas encore cet hôtel de ville. Le planning reviendra avec une mise à jour des données du jeu.",
                                 symbole: "calendar", illustration: 1000015)
                    }
                }
            }
            .pageChantier()
            .navigationTitle("Chantier")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func planning(_ plan: PlanAffiche) -> some View {
        let couloirs = Couloir.de(plan.plan, village: affiche.village)
        return VStack(alignment: .leading, spacing: 0) {
            if affiche.estExemple { MarqueExemple() }
            VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                BlocAReunir(plan: plan, village: affiche.village)
                VStack(alignment: .leading, spacing: Theme.Espace.s) {
                    Text("Couloirs").etiquetteChantier()
                    ForEach(couloirs) { couloir in
                        CarteCouloir(couloir: couloir, plan: plan, reference: reference, ouvert: Binding(
                            get: { ouverts.contains(couloir.id) },
                            set: { if $0 { ouverts.insert(couloir.id) } else { ouverts.remove(couloir.id) } }))
                            .id(couloir.id)
                    }
                }
            }
            .padding(.horizontal, Theme.Espace.marge)
            .padding(.vertical, Theme.Espace.l)
        }
    }
}
