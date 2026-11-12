import SwiftUI

/// Le thème « Carnet » : papier chaud en clair, encre profonde en sombre,
/// serif pour la date et la consigne, chiffres à chasse fixe.
/// Seul endroit de l'app où vivent couleurs, polices et espacements (PLAN §3.5).
enum Theme {

    /// Couleurs du catalogue `Assets.xcassets/Carnet`, chacune en clair et en sombre.
    /// Contrastes mesurés dans la PR de T06 (WCAG, au moins 4,5 pour 1 pour le texte).
    enum Couleur {
        /// Fond de toutes les pages.
        static let papier = Color(.papier)
        /// Fond des blocs posés sur la page (consigne, bandeau).
        static let surface = Color(.surface)
        /// Texte principal, jauges remplies.
        static let encre = Color(.encre)
        /// Texte secondaire.
        static let encreDouce = Color(.encreDouce)
        /// Filets, graduations, fond des jauges. Jamais pour du texte.
        static let trait = Color(.trait)
        /// La seule couleur d'accent : réservée à ce qui demande une action.
        static let accent = Color(.accent)
    }

    enum Police {
        /// La grande date du cap. La taille vient d'un `@ScaledMetric` du composant.
        static func date(_ taille: CGFloat) -> Font { .system(size: taille, weight: .regular, design: .serif) }
        /// La ligne au-dessus de la date (« HDV 16 terminé »).
        static let surtitre = Font.system(.title3, design: .serif)
        /// Le texte de la consigne.
        static let consigne = Font.system(.title3, design: .serif)
        /// Titre d'un état vide.
        static let titre = Font.system(.title2, design: .serif)
        static let texte = Font.body
        static let detail = Font.subheadline
        /// Grand symbole d'un état vide.
        static let symbole = Font.largeTitle
        /// Chiffres dans une ligne (pourcentages, niveaux, durées) : chiffres tabulaires, qui s'alignent en colonne.
        static let chiffre = Font.body.monospacedDigit()
        static let chiffreDetail = Font.subheadline.monospacedDigit()
        /// Chiffre seul et mis en avant (avancement total) : chasse fixe complète.
        static let chiffreGrand = Font.system(.title2, design: .monospaced).weight(.medium)
        /// Le « % » qui suit `chiffreGrand` : même taille et même graisse, mais proportionnel,
        /// pour que l'espace fine insécable reste fine.
        static let chiffreGrandSigne = Font.system(.title2).weight(.medium)
        /// Étiquette de rubrique, en capitales espacées, comme sur une fiche imprimée.
        static let etiquette = Font.system(.caption, design: .monospaced).weight(.medium)
    }

    enum Espace {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 20
        static let xl: CGFloat = 32
        /// Marge latérale des pages.
        static let marge: CGFloat = 20
    }

    /// Coins presque droits : un carnet, pas une pile de cartes.
    static let rayon: CGFloat = 3
    /// Épaisseur des filets et des graduations.
    static let filet: CGFloat = 1
}

extension View {
    /// Habille une page : fond papier, texte à l'encre, teinte encre pour les commandes.
    /// L'accent n'est jamais une teinte globale : chaque action le demande avec `.tint(Theme.Couleur.accent)`.
    func pageCarnet() -> some View {
        foregroundStyle(Theme.Couleur.encre)
            .tint(Theme.Couleur.encre)
            .background(Theme.Couleur.papier.ignoresSafeArea())
    }

    /// Étiquette de rubrique (« CONSIGNE », « CATÉGORIES »).
    func etiquetteCarnet() -> some View {
        font(Theme.Police.etiquette)
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(Theme.Couleur.encreDouce)
    }
}

/// Filet horizontal fin, comme une ligne de carnet.
struct Filet: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Couleur.trait)
            .frame(height: Theme.filet)
            .accessibilityHidden(true)
    }
}
