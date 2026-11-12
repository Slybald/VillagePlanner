import ChantierKit
import SwiftUI

/// « À réunir » : pour chaque ressource, ce qu'il faut avoir pour le prochain lancement et quand, le rythme par jour,
/// et une ligne pour les murs (qui n'occupent aucun ouvrier : ils ne sont pas dans les couloirs).
struct BlocAReunir: View {
    let plan: PlanAffiche
    let village: Village

    @Environment(\.dynamicTypeSize) private var tailleTexte
    @ScaledMetric(relativeTo: .body) private var icone: CGFloat = 34

    private var besoins: [ResourceNeed] { plan.besoins.filter { !$0.dues.isEmpty } }
    private var murs: [ResourceNeed] { plan.besoins.filter { $0.wallsRemaining > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            Text("À réunir").etiquetteChantier()
            VStack(alignment: .leading, spacing: Theme.Espace.m) {
                if besoins.isEmpty {
                    Text("Rien à payer dans les prochains lancements.")
                        .font(Theme.Police.texte).foregroundStyle(Theme.Couleur.texteDoux)
                }
                ForEach(besoins, id: \.resource) { ligne($0) }
                if !murs.isEmpty {
                    if !besoins.isEmpty { Filet() }
                    ligneMurs
                }
            }
            .padding(Theme.Espace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tuileChantier()
        }
    }

    private func quand(_ date: Date) -> String {
        date <= plan.maintenant ? "maintenant" : Lisible.moment(date, now: plan.maintenant, timeZone: plan.fuseau)
    }

    private func ligne(_ besoin: ResourceNeed) -> some View {
        let disposition = tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Espace.s))
                                                          : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Espace.m))
        let premiere = besoin.dues[0]
        return disposition {
            IconeRessource(ressource: besoin.resource, taille: min(icone, 56))
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                // Aux tailles d'accessibilité, le montant et l'échéance passent l'un sous l'autre.
                let ligne = tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Espace.xs))
                                                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Espace.s))
                ligne {
                    Text(Lisible.montant(premiere.amount)).font(Theme.Police.chiffreGrand).fixedSize()
                    Text("pour " + quand(premiere.date)).font(Theme.Police.texte)
                }
                if besoin.dues.count > 1 {
                    // Les deux échéances suivantes existent (R1) ; une seule tient sur la ligne sans la noyer.
                    Text("puis \(Lisible.montant(besoin.dues[1].amount)) \(quand(besoin.dues[1].date))")
                        .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                }
                if besoin.perDay > 0 {
                    Text("Rythme : \(Lisible.montant(besoin.perDay)) par jour")
                        .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Lisible.cout(premiere.amount, besoin.resource) + " pour " + quand(premiere.date)
                            + (besoin.perDay > 0 ? ". Rythme : \(Lisible.montant(besoin.perDay)) par jour." : "."))
    }

    /// « Murs : 225 à améliorer, 1,2 Md d'or » ; le rythme pour les finir au cap, quand il y en a un.
    private var ligneMurs: some View {
        let pieces = plan.pas.filter { $0.category == .walls && $0.level == $0.element.level + 1 }.reduce(0) { $0 + $1.count }
        let couts = murs.map { Lisible.cout($0.wallsRemaining, $0.resource) }.joined(separator: " · ")
        let disposition = tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Espace.s))
                                                          : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Espace.m))
        return disposition {
            Illustration(id: 1_000_010, niveau: max(village.niveau(de: 1_000_010), 1), taille: min(icone, 56),
                         avecPastille: false, lieu: "chantier")
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text("Murs : \(pieces) à améliorer, \(couts)").font(Theme.Police.texte)
                if let rythme = murs.first(where: { $0.wallsPerDay != nil }), let jour = rythme.wallsPerDay, let fin = rythme.wallsEnd {
                    Text("Pour les finir le \(Lisible.jour(fin, now: plan.maintenant, timeZone: plan.fuseau)) : "
                         + "\(Lisible.cout(jour, rythme.resource)) par jour")
                        .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
