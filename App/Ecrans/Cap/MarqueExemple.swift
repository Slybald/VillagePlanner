import SwiftUI

/// Bandeau « exemple » en haut de chaque écran tant que le village d'exemple est affiché.
struct MarqueExemple: View {
    var body: some View {
        // Aux grandes tailles de texte, « EXEMPLE » et la phrase passent l'un sous l'autre.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Espace.s) { contenu; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: Theme.Espace.xs) { contenu }
        }
        .padding(.horizontal, Theme.Espace.marge)
        .padding(.vertical, Theme.Espace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Couleur.surface)
        .overlay(alignment: .bottom) { Filet() }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var contenu: some View {
        Text("Exemple").etiquetteCarnet().foregroundStyle(Theme.Couleur.encre).fixedSize()
        Text("village inventé, pas le tien")
            .font(Theme.Police.detail)
            .foregroundStyle(Theme.Couleur.encreDouce)
    }
}

/// Chantier et Village : provisoires jusqu'aux jalons suivants.
struct PageProvisoire: View {
    let titre: String
    let message: String
    let symbole: String
    let estExemple: Bool

    var body: some View {
        VStack(spacing: 0) {
            if estExemple { MarqueExemple() }
            EtatVide(titre: titre, message: message, symbole: symbole)
        }
        .pageCarnet()
    }
}

/// Une ligne « nom ... valeur » en texte libre : inventaire d'un HDV inconnu, catégorie sans travail.
struct LigneTexte: View {
    let nom: String
    let valeur: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.xs) {
            Text(nom).font(Theme.Police.texte).layoutPriority(1)
            Spacer(minLength: Theme.Espace.m)
            Text(valeur)
                .font(Theme.Police.chiffre)
                .foregroundStyle(Theme.Couleur.encreDouce)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
