import SwiftUI

extension Text {
    /// « 64 % » en chiffres à chasse fixe, avec une espace fine insécable (U+202F) avant le « % ».
    /// En chasse fixe, l'espace ordinaire d'un pourcentage formaté paraît pleine largeur : le signe est
    /// donc composé à part, dans la police proportionnelle de même taille.
    static func pourcentageGrand(_ valeur: Double) -> Text {
        let nombre = Text("\(Int((valeur * 100).rounded()))").font(Theme.Police.chiffreGrand)
        let signe = Text("\u{202F}%").font(Theme.Police.chiffreGrandSigne)
        return Text("\(nombre)\(signe)")
    }
}

#Preview("Pourcentage") {
    VStack(alignment: .leading, spacing: Theme.Espace.m) {
        Text.pourcentageGrand(0.64)
        Text.pourcentageGrand(1)
        Text.pourcentageGrand(0)
    }
    .padding(Theme.Espace.marge)
    .pageChantier()
}
