import SwiftUI

/// La consigne du chef de chantier : une phrase, et de quoi en demander une autre.
struct CarteConsigne: View {
    let texte: String
    /// Le texte vient du conseiller (et a passé les garde-fous) : l'app le dit, discrètement.
    var reformulee = false
    var titreAction = "Demander"
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Consigne").etiquetteChantier()
            Text(texte)
                .font(Theme.Police.consigne)
                .fixedSize(horizontal: false, vertical: true)
            if reformulee {
                Text("Reformulée par le conseiller, chiffres contrôlés par l'app")
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button(action: action) {
                    Label(titreAction, systemImage: "chevron.right")
                        .labelStyle(TitreAvantIcone())
                        .font(Theme.Police.texte.weight(.semibold))
                        .foregroundStyle(Theme.Couleur.action)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Couleur.surface, in: .rect(cornerRadius: Theme.rayon))
        // Le bord gauche épais rappelle une fiche agrafée dans le carnet.
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.Couleur.texte).frame(width: 3).accessibilityHidden(true)
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
        .pageChantier()
}
