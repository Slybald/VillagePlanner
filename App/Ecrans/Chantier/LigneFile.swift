import ChantierKit
import SwiftUI

/// Une amélioration d'un couloir : son image au niveau actuel (le niveau maximum en fantôme), son nom, de quel niveau
/// à quel niveau, et soit ce qu'il reste (en cours), soit quand la lancer (conseillée, jamais « lancée »).
struct LigneFile: View {
    let pas: ScheduledStep
    let reference: ReferenceData
    let plan: PlanAffiche
    /// L'amélioration que le joueur peut lancer dès maintenant : l'accent est pour elle.
    var alancer = false
    var taille: CGFloat = 48

    @ScaledMetric(relativeTo: .body) private var image: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var tailleTexte

    private var nom: String { reference.item(pas.step.itemID)?.name ?? "#\(pas.step.itemID)" }
    private var enCours: Bool { pas.fromSnapshot && pas.end > plan.maintenant }

    var body: some View {
        let disposition = tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Espace.s))
                                                          : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Espace.m))
        disposition {
            Illustration(id: pas.step.itemID, niveau: pas.step.level - 1, maximum: pas.step.element.maxLevel,
                         taille: min(taille * max(image, 1), taille * 1.6), lieu: "chantier")
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(nom).font(Theme.Police.texte)
                Text(niveaux)
                    .font(Theme.Police.chiffreDetail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                    .accessibilityLabel("du niveau \(pas.step.level - 1) au niveau \(pas.step.level)")
                if let cout { Text(cout).font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux) }
                Text(quand)
                    .font(Theme.Police.detail.weight(.semibold))
                    .foregroundStyle(alancer ? Theme.Couleur.elixirTexte : enCours ? Theme.Couleur.elixirTexte : Theme.Couleur.texteDoux)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// « 10 → 11 », et la durée d'un lancement conseillé : « 10 → 11 · 6 j ».
    private var niveaux: String {
        let base = "\(pas.step.level - 1) → \(pas.step.level)"
        return pas.fromSnapshot ? base : base + " · " + Lisible.duree(Int(pas.end.timeIntervalSince(pas.start)))
    }

    private var cout: String? {
        let c = pas.costs.filter { $0.amount > 0 }.map { Lisible.cout($0.amount, $0.resource) }
        return c.isEmpty ? nil : c.joined(separator: " · ")
    }

    private var quand: String {
        if pas.fromSnapshot {
            // Fin du minuteur illisible : on ne l'invente pas.
            guard case .inProgress(let fin?) = pas.step.status else { return "en cours · fin inconnue" }
            let reste = Lisible.duree(Int(fin.timeIntervalSince(plan.maintenant).rounded(.up)))
            return "encore \(reste) · fin " + Lisible.moment(fin, now: plan.maintenant, timeZone: plan.fuseau)
        }
        return pas.start <= plan.maintenant ? "À lancer maintenant"
                                             : "À lancer dès " + Lisible.moment(pas.start, now: plan.maintenant, timeZone: plan.fuseau)
    }
}
