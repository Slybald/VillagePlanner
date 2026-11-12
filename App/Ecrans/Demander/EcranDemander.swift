import ChantierKit
import SwiftUI

/// L'écran « Demander » (PLAN §3.4) : la consigne en entier, ce que dit le moteur quand le conseiller l'a reformulée,
/// et le profil de jeu en clair. Les questions arrivent avec T21.
struct EcranDemander: View {
    let affiche: VillageAffiche
    let reference: ReferenceData
    let modifierProfil: () -> Void
    @Environment(ModeleApp.self) private var modele
    @Environment(ModeleConseil.self) private var conseil
    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                    if let plan = affiche.plan {
                        let cle = conseil.cle(affiche, reference: reference, conseilsDate: modele.dateConseils)
                        let reformulee = conseil.estConseil(cle: cle, now: plan.maintenant)
                        CarteConsigne(texte: conseil.consigne(moteur: plan.consigne, cle: cle, now: plan.maintenant), reformulee: reformulee)
                        if reformulee { moteur(plan) }
                        profil(plan)
                    }
                }
                .padding(.horizontal, Theme.Espace.marge)
                .padding(.vertical, Theme.Espace.l)
            }
            .pageChantier()
            .navigationTitle("Demander")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
        }
    }

    /// La consigne que le moteur écrit, telle quelle : ce que le conseiller a reformulé.
    private func moteur(_ plan: PlanAffiche) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            Text("Ce que dit le moteur").etiquetteChantier()
            Text(plan.consigne).font(Theme.Police.texte).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }

    private func profil(_ plan: PlanAffiche) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Ton profil de jeu").etiquetteChantier()
            Text(Self.phrase(plan.profil, reference: reference, maintenant: plan.maintenant))
                .font(Theme.Police.texte)
                .fixedSize(horizontal: false, vertical: true)
            Button("Modifier dans les Réglages", action: modifierProfil)
                .font(Theme.Police.texte.weight(.semibold))
                .foregroundStyle(Theme.Couleur.action)
        }
        .padding(Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }

    /// « Priorité à l'attaque, un héros à la fois, Reine des archères épinglée, pas de jeu de 23 h à 7 h. »
    static func phrase(_ profil: Profile, reference: ReferenceData, maintenant: Date) -> String {
        let mots = ["un", "deux", "trois", "quatre", "cinq"]
        let orientation: String = switch profil.orientation {
        case .attack: "Priorité à l'attaque"
        case .defense: "Priorité à la défense"
        case .balanced: "Jeu équilibré"
        }
        var parts = [orientation]
        if let n = profil.heroLimit { parts.append((n >= 1 && n <= mots.count ? mots[n - 1] : "\(n)") + " héros à la fois") }
        let epingles = profil.pinned.compactMap { reference.name(of: $0) }.sorted()
        if !epingles.isEmpty { parts.append(epingles.joined(separator: ", ") + (epingles.count > 1 ? " épinglés" : " épinglé")) }
        if let h = profil.quietHours { parts.append("pas de jeu de \(h.start)\u{00A0}h à \(h.end)\u{00A0}h") }
        var texte = parts.joined(separator: ", ") + "."
        if let r = Lisible.reductions(profil, at: maintenant) { texte += " " + r }
        return texte
    }
}
