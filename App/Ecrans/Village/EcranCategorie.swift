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
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if affiche.estExemple { MarqueExemple() }
                VStack(alignment: .leading, spacing: Theme.Espace.l) {
                    if let progression = affiche.rapport.categories[categorie], progression.hasWork {
                        LigneCategorie(nom: categorie.nom, valeur: progression.fraction, avecJauge: true)
                    }
                    if tous.isEmpty {
                        Text("Rien dans cette catégorie à ton HDV.")
                            .font(Theme.Police.texte).foregroundStyle(Theme.Couleur.encreDouce)
                    }
                    if !restants.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Reste à faire").etiquetteCarnet().padding(.bottom, Theme.Espace.xs)
                            Filet()
                            ForEach(Array(restants.enumerated()), id: \.offset) { _, e in
                                LigneElement(element: e.element, nom: e.fiche.name)
                                Filet()
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
        .pageCarnet()
        .navigationTitle(categorie.nom)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// « 23 terminés » : une ligne, qui s'ouvre sur la liste.
    private func repliees(_ termines: [ElementAffiche]) -> some View {
        let n = termines.reduce(0) { $0 + $1.element.count }
        return DisclosureGroup(isExpanded: $terminesOuverts) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(termines.enumerated()), id: \.offset) { _, e in
                    Filet()
                    LigneElement(element: e.element, nom: e.fiche.name)
                }
            }
        } label: {
            Text("\(n) terminé\(n > 1 ? "s" : "")")
                .font(Theme.Police.texte)
                .padding(.vertical, Theme.Espace.s)
        }
        .tint(Theme.Couleur.encreDouce)
    }
}
