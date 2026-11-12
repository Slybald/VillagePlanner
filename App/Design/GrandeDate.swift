import SwiftUI

/// La date du cap, en très grand : ce qui sera fini, quand, et de combien elle a bougé.
struct GrandeDate: View {
    /// « HDV 16 terminé »
    let surtitre: String
    /// « le 14 mars »
    let date: String
    /// « 2 jours gagnés depuis mardi » ; rien avant le deuxième import.
    var mouvement: String? = nil
    /// « hors murs et équipements »
    var mention: String? = nil

    @ScaledMetric(relativeTo: .largeTitle) private var taille: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(surtitre)
                .font(Theme.Police.surtitre)
                .foregroundStyle(Theme.Couleur.encreDouce)
            Text(date)
                // Plafond : au-delà, « le 14 mars » se coupe en trois lignes.
                .font(Theme.Police.date(min(taille, 92)))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.bottom, Theme.Espace.xs)
            if let mouvement {
                Text(mouvement).font(Theme.Police.texte)
            }
            if let mention {
                Text(mention)
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.encreDouce)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Grande date") {
    GrandeDate(surtitre: "HDV 16 terminé", date: "le 14 mars",
               mouvement: "2 jours gagnés depuis mardi", mention: "hors murs et équipements")
        .padding(Theme.Espace.marge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageCarnet()
}
