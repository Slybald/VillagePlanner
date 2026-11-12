import ChantierKit
import SwiftUI

/// Les éléments d'une catégorie : ce qui reste d'abord, les terminés repliés en une ligne.
struct EcranCategorie: View {
    let categorie: ChantierKit.Category
    let affiche: VillageAffiche
    let reference: ReferenceData

    #if DEBUG
    @State private var terminesOuverts = ProcessInfo.processInfo.arguments.contains("-termines")   // captures
    #else
    @State private var terminesOuverts = false
    #endif

    var body: some View {
        let tous = Elements.de(categorie, village: affiche.village, reference: reference)
        let restants = tous.filter { !$0.estTermine }
        let termines = tous.filter(\.estTermine)
        let restant = RestantAffiche(affiche: affiche, reference: reference)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if affiche.estExemple { MarqueExemple() }
                VStack(alignment: .leading, spacing: Theme.Espace.l) {
                    if let progression = affiche.rapport.categories[categorie], progression.hasWork {
                        LigneCategorie(nom: categorie.nom, valeur: progression.fraction, avecJauge: true, couleur: categorie.couleur)
                        if let reste = restant.resume(categorie) { Text(reste).font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux) }
                    }
                    if let mention = restant.mentionReduction {
                        Text(mention).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                    }
                    if tous.isEmpty {
                        Text("Rien dans cette catégorie à ton HDV.")
                            .font(Theme.Police.texte).foregroundStyle(Theme.Couleur.texteDoux)
                    }
                    if !restants.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Espace.s) {
                            Text("Reste à faire").etiquetteChantier()
                            ForEach(Array(restants.enumerated()), id: \.offset) { _, e in
                                LigneElement(element: e.element, nom: e.fiche.name, complement: restant.complement(e.element))
                            }
                        }
                    }
                    if !termines.isEmpty { repliees(termines).id("termines") }
                }
                .padding(.horizontal, Theme.Espace.marge)
                .padding(.vertical, Theme.Espace.l)
            }
        }
        #if DEBUG
        .task { if terminesOuverts { proxy.scrollTo("termines", anchor: .top) } }   // captures
        #endif
        }
        .pageChantier()
        .navigationTitle(categorie.nom)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// « 23 terminés » : une ligne, qui s'ouvre sur la liste.
    private func repliees(_ termines: [ElementAffiche]) -> some View {
        let n = termines.reduce(0) { $0 + $1.element.count }
        return DisclosureGroup(isExpanded: $terminesOuverts) {
            VStack(alignment: .leading, spacing: Theme.Espace.s) {
                ForEach(Array(termines.enumerated()), id: \.offset) { _, e in
                    LigneElement(element: e.element, nom: e.fiche.name)
                }
            }
            .padding(.top, Theme.Espace.s)
        } label: {
            Text("\(n) terminé\(n > 1 ? "s" : "")")
                .font(Theme.Police.texte)
                .padding(.vertical, Theme.Espace.s)
        }
        .tint(Theme.Couleur.elixirTexte)
    }
}
