import SwiftUI

/// Jauge en mètre de chantier : une barre d'encre sur un ruban gradué tous les dix pour cent.
/// `.grande` pour l'avancement total, `.fine` pour une catégorie.
struct Jauge: View {
    enum Taille { case grande, fine }

    /// Entre 0 et 1.
    let valeur: Double
    var taille: Taille = .grande

    @ScaledMetric(relativeTo: .body) private var hauteurBarre: CGFloat = 8

    var body: some View {
        let barre = taille == .grande ? hauteurBarre : 3
        let graduation = taille == .grande ? barre * 0.75 : 0
        Canvas { contexte, dimension in
            let largeur = dimension.width
            let rempli = largeur * min(max(valeur, 0), 1)
            contexte.fill(Path(CGRect(x: 0, y: 0, width: largeur, height: barre)), with: .color(Theme.Couleur.trait))
            contexte.fill(Path(CGRect(x: 0, y: 0, width: rempli, height: barre)), with: .color(Theme.Couleur.encre))
            guard graduation > 0 else { return }
            // Graduations sous le ruban : une tous les 10 %, plus longue à 0, 50 et 100 %.
            for pas in 0...10 {
                let x = min(max(largeur * Double(pas) / 10, Theme.filet / 2), largeur - Theme.filet / 2)
                let longueur = pas % 5 == 0 ? graduation * 1.6 : graduation
                var trait = Path()
                trait.move(to: CGPoint(x: x, y: barre))
                trait.addLine(to: CGPoint(x: x, y: barre + longueur))
                contexte.stroke(trait, with: .color(x <= rempli ? Theme.Couleur.encre : Theme.Couleur.trait), lineWidth: Theme.filet)
            }
        }
        .frame(height: barre + graduation * 1.6)
        .accessibilityElement()
        .accessibilityLabel("Avancement")
        .accessibilityValue(Text(valeur, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview("Jauge") {
    VStack(alignment: .leading, spacing: Theme.Espace.l) {
        Jauge(valeur: 0)
        Jauge(valeur: 0.64)
        Jauge(valeur: 1)
        Jauge(valeur: 0.31, taille: .fine)
    }
    .padding(Theme.Espace.marge)
    .pageCarnet()
}
