import ChantierKit
import SwiftUI

/// L'écran Village (PLAN §3.3) : les catégories, puis le détail de chacune à la demande.
struct EcranVillage: View {
    let affiche: VillageAffiche
    let reference: ReferenceData

    @Environment(\.dynamicTypeSize) private var tailleTexte
    @State private var chemin: [ChantierKit.Category] = Self.cheminDeCapture()

    private var village: Village { affiche.village }
    private var restant: RestantAffiche { RestantAffiche(affiche: affiche, reference: reference) }

    /// Débogage seulement : `-categorie <défenses|…>` ouvre la catégorie au lancement (captures).
    private static func cheminDeCapture() -> [ChantierKit.Category] {
        #if DEBUG
        if let nom = UserDefaults.standard.string(forKey: "categorie"),
           let categorie = ChantierKit.Category(rawValue: nom) { return [categorie] }
        #endif
        return []
    }

    var body: some View {
        NavigationStack(path: $chemin) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if affiche.estExemple { MarqueExemple() }
                    VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                        categories
                        if !village.unknown.isEmpty { inconnus.id("inconnus") }
                    }
                    .padding(.horizontal, Theme.Espace.marge)
                    .padding(.vertical, Theme.Espace.l)
                }
            }
            #if DEBUG
            .task { if ProcessInfo.processInfo.arguments.contains("-inconnus") { proxy.scrollTo("inconnus", anchor: .top) } }   // captures
            #endif
            }
            .pageCarnet()
            .navigationTitle("Village")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ChantierKit.Category.self) { categorie in
                EcranCategorie(categorie: categorie, affiche: affiche, reference: reference)
            }
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Catégories").etiquetteCarnet().padding(.bottom, Theme.Espace.s)
            let restant = restant
            if let mention = restant.mentionReduction {
                Text(mention).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.encreDouce)
                    .padding(.bottom, Theme.Espace.s)
            }
            ForEach(ChantierKit.Category.ordreAffichage, id: \.self) { categorie in
                NavigationLink(value: categorie) {
                    HStack(spacing: Theme.Espace.m) {
                        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                            resume(categorie)
                            if let reste = restant.resume(categorie) {
                                Text(reste).font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.encreDouce)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(Theme.Police.detail)
                            .foregroundStyle(Theme.Couleur.encreDouce)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, Theme.Espace.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Filet()
            }
        }
    }

    /// Pourcentage, ou texte quand il n'y en a pas (A4 : rien à faire ; V7 : HDV inconnu).
    @ViewBuilder private func resume(_ categorie: ChantierKit.Category) -> some View {
        if let progression = affiche.rapport.categories[categorie] {
            if progression.hasWork, tailleTexte.isAccessibilitySize {
                // Un nom comme « Défenses » ne tient pas à côté de son chiffre : l'un sous l'autre.
                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    Text(categorie.nom).font(Theme.Police.texte)
                    Text(progression.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(Theme.Police.chiffre).foregroundStyle(Theme.Couleur.encreDouce)
                    Jauge(valeur: progression.fraction, taille: .fine).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else if progression.hasWork {
                LigneCategorie(nom: categorie.nom, valeur: progression.fraction, avecJauge: true)
            } else {
                LigneTexte(nom: categorie.nom, valeur: "rien à faire")
            }
        } else {
            let n = Elements.de(categorie, village: village, reference: reference).reduce(0) { $0 + $1.element.count }
            LigneTexte(nom: categorie.nom, valeur: "\(n) élément\(n > 1 ? "s" : "")")
        }
    }

    /// V5 : identifiants absents de la référence, exclus des calculs.
    private var inconnus: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Éléments inconnus").etiquetteCarnet().padding(.bottom, Theme.Espace.xs)
            Text("Absents des données de l'app, donc exclus des calculs.")
                .font(Theme.Police.detail)
                .foregroundStyle(Theme.Couleur.encreDouce)
                .padding(.bottom, Theme.Espace.s)
            ForEach(Array(village.unknown.enumerated()), id: \.offset) { _, entree in
                LigneInconnu(entree: entree)
                Filet()
            }
        }
    }
}

private struct LigneInconnu: View {
    let entree: ExportEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text("Identifiant \(String(entree.id))" + (entree.count > 1 ? " × \(entree.count)" : ""))
                .font(Theme.Police.texte)
            if let niveau = entree.level {
                Text("niveau \(niveau)").font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.encreDouce)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Espace.s)
        .accessibilityElement(children: .combine)
    }
}
