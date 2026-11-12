import SwiftUI

/// Page sans contenu : une phrase pour dire pourquoi, et le geste qui la remplit.
struct EtatVide: View {
    let titre: String
    let message: String
    var symbole = "doc.on.clipboard"
    var titreAction: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Espace.m) {
            Image(systemName: symbole)
                .font(Theme.Police.symbole)
                .foregroundStyle(Theme.Couleur.encreDouce)
                .accessibilityHidden(true)
            Text(titre)
                .font(Theme.Police.titre)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Theme.Police.texte)
                .foregroundStyle(Theme.Couleur.encreDouce)
                .multilineTextAlignment(.center)
            if let titreAction, let action {
                Button(titreAction, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: Theme.rayon))
                    .tint(Theme.Couleur.accent)
                    .foregroundStyle(Theme.Couleur.papier)
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
        .pageCarnet()
}
