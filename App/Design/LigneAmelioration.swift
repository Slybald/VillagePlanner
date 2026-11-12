import SwiftUI

/// Une amélioration : quoi, de quel niveau à quel niveau, combien de temps.
struct LigneAmelioration: View {
    let nom: String
    let deNiveau: Int
    let aNiveau: Int
    /// « 4 j 12 h »
    let duree: String
    /// « 18 M d'or »
    var cout: String? = nil
    /// Un ouvrier est libre pour la lancer : c'est une action, donc l'accent.
    var aLancer = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(nom).font(Theme.Police.texte)
                Text("\(deNiveau) → \(aNiveau)")
                    .font(Theme.Police.chiffreDetail)
                    .foregroundStyle(Theme.Couleur.encreDouce)
                    .accessibilityLabel("du niveau \(deNiveau) au niveau \(aNiveau)")
                if aLancer {
                    Text("À lancer")
                        .font(Theme.Police.detail.weight(.semibold))
                        .foregroundStyle(Theme.Couleur.accent)
                }
            }
            Spacer(minLength: Theme.Espace.s)
            VStack(alignment: .trailing, spacing: Theme.Espace.xs) {
                Text(duree).font(Theme.Police.chiffre)
                if let cout {
                    Text(cout)
                        .font(Theme.Police.chiffreDetail)
                        .foregroundStyle(Theme.Couleur.encreDouce)
                }
            }
        }
        .padding(.vertical, Theme.Espace.s)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Ligne d'amélioration") {
    VStack(spacing: 0) {
        LigneAmelioration(nom: "Arc-X", deNiveau: 10, aNiveau: 11, duree: "4 j 12 h", cout: "18 M d'or", aLancer: true)
        Filet()
        LigneAmelioration(nom: "Tour de sorts", deNiveau: 3, aNiveau: 4, duree: "3 j", cout: "9,5 M d'or")
        Filet()
    }
    .padding(Theme.Espace.marge)
    .pageCarnet()
}
