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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(surtitre)
                .font(Theme.Police.surtitre)
                .foregroundStyle(Theme.Couleur.texteDoux)
            Text(date)
                // Suit la taille du texte, plafonnée à accessibility1 ; une seule ligne, réduite si besoin :
                // « le 10 novembre » ne se coupe jamais en deux.
                .font(Theme.Police.grandeDate)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .padding(.bottom, Theme.Espace.xs)
            if let mouvement {
                Text(mouvement).font(Theme.Police.texte)
            }
            if let mention {
                Text(mention)
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
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
        .pagePlanner()
}
