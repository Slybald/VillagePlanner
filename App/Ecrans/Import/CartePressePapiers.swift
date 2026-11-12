import SwiftUI

/// Le bouton système de collage : seul moyen de lire le presse-papiers sans alerte d'iOS (PLAN §7.5).
/// L'accent est réservé à cette action.
struct BoutonColler: View {
    @Environment(ModeleApp.self) private var modele

    var body: some View {
        PasteButton(payloadType: String.self) { textes in
            let texte = textes.first ?? ""
            Task { @MainActor in modele.importer(texte) }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Theme.Couleur.action)
    }
}

/// « Un texte est dans le presse-papiers » : apparaît au retour au premier plan, avec le bouton de collage.
struct CartePressePapiers: View {
    @Environment(ModeleApp.self) private var modele

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            if let retour = modele.retour {
                CarteRetour(retour: retour)
            }
            if modele.presseTexteAColler {
                Text("Un texte est dans le presse-papiers").font(Theme.Police.texte.weight(.semibold))
                Text("Si c'est l'export de ton village, colle-le : l'app l'enregistre comme une nouvelle photo.")
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
                BoutonColler()
            }
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }
}

/// Ce qui s'est passé, ce que l'app a gardé, quoi faire.
struct CarteRetour: View {
    @Environment(ModeleApp.self) private var modele
    let retour: Retour

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
            Image(systemName: retour.estErreur ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(retour.estErreur ? Theme.Couleur.action : Theme.Couleur.texteDoux)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(retour.titre).font(Theme.Police.texte.weight(.semibold))
                Text(retour.detail)
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Fermer") { modele.fermerRetour() }
                    .font(Theme.Police.detail)
                    .padding(.top, Theme.Espace.xs)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
