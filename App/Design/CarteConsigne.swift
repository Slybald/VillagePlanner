import SwiftUI

/// La consigne du chef de chantier : une phrase, et de quoi en demander une autre.
struct CarteConsigne: View {
    let texte: String
    var titreAction = "Demander"
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Consigne").etiquetteCarnet()
            Text(texte)
                .font(Theme.Police.consigne)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: action) {
                    Label(titreAction, systemImage: "chevron.right")
                        .labelStyle(TitreAvantIcone())
                        .font(Theme.Police.texte.weight(.semibold))
                        .foregroundStyle(Theme.Couleur.accent)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Couleur.surface, in: .rect(cornerRadius: Theme.rayon))
        // Le bord gauche épais rappelle une fiche agrafée dans le carnet.
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.Couleur.encre).frame(width: 3).accessibilityHidden(true)
        }
    }
}

/// « Demander › » : le texte d'abord, la flèche ensuite.
private struct TitreAvantIcone: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Espace.xs) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

#Preview("Carte de consigne") {
    CarteConsigne(texte: "Demain 14 h, deux ouvriers se libèrent. Lance l'Arc-X 11 et la Tour de sorts 4 : prépare 18 M d'or.") {}
        .padding(Theme.Espace.marge)
        .pageCarnet()
}
