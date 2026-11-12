import SwiftUI

/// Une catégorie et son avancement, reliés par des points de conduite comme une table des matières.
struct LigneCategorie: View {
    let nom: String
    /// Entre 0 et 1.
    let valeur: Double
    /// Une jauge fine sous la ligne (écran Village) ; sans, sur le Cap.
    var avecJauge = false

    var body: some View {
        VStack(spacing: Theme.Espace.xs) {
            HStack(alignment: .lastTextBaseline, spacing: Theme.Espace.xs) {
                Text(nom).font(Theme.Police.texte).layoutPriority(1)
                PointsDeConduite()
                Text(valeur, format: .percent.precision(.fractionLength(0)))
                    .font(Theme.Police.chiffre)
                    .fixedSize()
                    .foregroundStyle(valeur >= 1 ? Theme.Couleur.encreDouce : Theme.Couleur.encre)
            }
            if avecJauge {
                Jauge(valeur: valeur, taille: .fine).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pointillés qui mènent l'œil du nom au chiffre.
private struct PointsDeConduite: View {
    var body: some View {
        Line()
            .stroke(Theme.Couleur.trait, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 4]))
            .frame(height: 1.5)
            .frame(minWidth: Theme.Espace.m)
            .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            .accessibilityHidden(true)
    }

    nonisolated private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

#Preview("Ligne de catégorie") {
    VStack(spacing: Theme.Espace.m) {
        LigneCategorie(nom: "Défenses", valeur: 0.71)
        LigneCategorie(nom: "Murs", valeur: 0.31, avecJauge: true)
        LigneCategorie(nom: "Pièges", valeur: 1)
    }
    .padding(Theme.Espace.marge)
    .pageCarnet()
}
