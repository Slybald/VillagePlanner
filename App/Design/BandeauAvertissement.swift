import SwiftUI

/// Bandeau pleine largeur, entre deux filets : quelque chose empêche un calcul juste.
struct BandeauAvertissement: View {
    let titre: String
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Couleur.action)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(titre).font(Theme.Police.texte.weight(.semibold))
                Text(message)
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Espace.marge)
        .padding(.vertical, Theme.Espace.m)
        .background(Theme.Couleur.surface)
        .overlay(alignment: .top) { Filet() }
        .overlay(alignment: .bottom) { Filet() }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Bandeau d'avertissement") {
    VStack {
        BandeauAvertissement(titre: "Données du jeu à mettre à jour",
                             message: "Ton village contient des niveaux que l'app ne connaît pas encore. Les pourcentages peuvent être faux.")
        Spacer()
    }
    .pageChantier()
}
