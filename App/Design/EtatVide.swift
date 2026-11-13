import SwiftUI

/// Page sans contenu : une phrase pour dire pourquoi, et le geste qui la remplit.
struct EtatVide: View {
    let titre: String
    let message: String
    var symbole = "doc.on.clipboard"
    /// Un bâtiment du jeu à la place du symbole (sa fiche dans `Illustrations`).
    var illustration: Int? = nil
    var titreAction: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        // Défilante : à la plus grande police, le message passe sous l'écran au lieu d'être coupé.
        GeometryReader { geo in
            ScrollView {
                contenu.frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var contenu: some View {
        VStack(spacing: Theme.Espace.m) {
            if let illustration, let image = Illustrations.image(illustration, niveau: 1) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: 120, height: 120)
                    .shadow(color: Theme.Couleur.ombre, radius: 3, y: 3)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: symbole)
                    .font(Theme.Police.symbole)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                    .accessibilityHidden(true)
            }
            Text(titre)
                .font(Theme.Police.titre)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(Theme.Police.texte)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let titreAction, let action {
                Button(titreAction, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.Couleur.action)
                    .foregroundStyle(Theme.Couleur.surBois)
                    .padding(.top, Theme.Espace.s)
            }
        }
        .padding(Theme.Espace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("État vide") {
    EtatVide(titre: "Aucune photo du village",
             message: "Dans le jeu, copie l'export de ton village, puis reviens ici.",
             titreAction: "Coller l'export") {}
        .pageChantier()
}
