import CoreText
import SwiftUI

/// Le thème « Chantier vivant » : la palette du jeu (or, élixir, élixir noir, bois, pierre, ciel), Lilita One pour
/// les titres et les grands chiffres, Fredoka pour le texte. Seul endroit de l'app où vivent couleurs, polices et
/// espacements (PLAN §3.5). Contrastes mesurés dans la PR « DA Chantier vivant » (WCAG, au moins 4,5 pour 1 pour le texte).
enum Theme {

    /// Couleurs du catalogue `Assets.xcassets/Palette`, chacune en clair et en sombre.
    enum Couleur {
        /// Fond de toutes les pages : ciel pâle le jour, nuit d'élixir noir.
        static let fond = Color(.fond)
        /// Tuiles et bandeaux posés sur la page.
        static let surface = Color(.surface)
        /// Texte principal : brun de bois très foncé, crème la nuit.
        static let texte = Color(.texte)
        /// Texte secondaire.
        static let texteDoux = Color(.texteDoux)
        /// Filets et bords des tuiles. Jamais pour du texte.
        static let trait = Color(.trait)
        /// Fond des jauges, et leur contour.
        static let creux = Color(.creux)
        static let contour = Color(.contour)
        /// L'or du jeu : remplissage des jauges, jamais pour du texte sur fond clair.
        static let or = Color(.or)
        /// Texte posé sur l'or.
        static let surOr = Color(.surOr)
        static let elixir = Color(.elixir)
        static let elixirNoir = Color(.elixirNoir)
        /// Élixir lisible en texte (liens, onglet choisi).
        static let elixirTexte = Color(.elixirTexte)
        /// Le bois des cadres et des panneaux, et le texte posé dessus.
        static let bois = Color(.bois)
        static let surBois = Color(.surBois)
        static let ciel = Color(.ciel)
        /// « Au maximum » : le vert de l'herbe.
        static let herbe = Color(.herbe)
        /// Ce qui demande un geste (bouton de collage, alerte) : un élixir assez sombre pour porter du blanc.
        static let action = Color(.action)
        /// Ombre portée des illustrations, et reflet du haut des jauges.
        static let ombre = Color.black.opacity(0.3)
        static let reflet = Color.white.opacity(0.35)
    }

    enum Police {
        static let titres = "Lilita One"
        static let texteCourant = "Fredoka"

        /// Grand chiffre ou grand titre. La taille vient d'un `@ScaledMetric` du composant.
        static func date(_ taille: CGFloat) -> Font { .custom(titres, fixedSize: taille) }
        /// La ligne au-dessus du grand chiffre, le nom d'un écran.
        static let surtitre = Font.custom(titres, size: 20, relativeTo: .title3)
        static let consigne = Font.custom(texteCourant, size: 20, relativeTo: .title3).weight(.medium)
        /// Titre d'un état vide.
        static let titre = Font.custom(titres, size: 26, relativeTo: .title2)
        static let texte = Font.custom(texteCourant, size: 17, relativeTo: .body).weight(.medium)
        static let detail = Font.custom(texteCourant, size: 15, relativeTo: .subheadline)
        /// Grand symbole d'un état vide.
        static let symbole = Font.largeTitle
        /// Chiffres dans une ligne (pourcentages, niveaux) : Lilita, comme les compteurs du jeu.
        static let chiffre = Font.custom(titres, size: 18, relativeTo: .body)
        /// Durées et coûts : Fredoka, plus lisible en petit, chiffres alignés.
        static let chiffreDetail = Font.custom(texteCourant, size: 15, relativeTo: .subheadline).weight(.medium).monospacedDigit()
        static let chiffreGrand = Font.custom(titres, size: 28, relativeTo: .title)
        static let chiffreGrandSigne = Font.custom(titres, size: 28, relativeTo: .title)
        /// Étiquette de rubrique, en capitales espacées.
        static let etiquette = Font.custom(titres, size: 14, relativeTo: .caption)
        /// L'éclat (symbole) d'une montée de niveau, à la taille de l'illustration.
        static func eclat(_ taille: CGFloat) -> Font { .system(size: taille, weight: .bold) }
        /// Le niveau posé sur une illustration.
        static let badge = Font.custom(titres, size: 13, relativeTo: .caption)

        /// Lilita One et Fredoka sont embarquées (licence OFL, à côté des fichiers) : enregistrées au lancement.
        static func enregistrer() {
            for nom in ["LilitaOne-Regular", "Fredoka"] {
                guard let url = Bundle.main.url(forResource: nom, withExtension: "ttf") else { continue }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
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

    /// Coins ronds et épais, comme les panneaux du jeu.
    static let rayon: CGFloat = 14
    /// Épaisseur des filets.
    static let filet: CGFloat = 1
    /// Bord du cadre en bois et des tuiles.
    static let bord: CGFloat = 2
    /// Épaisseur du « socle » sous une tuile, comme un bouton du jeu.
    static let socle: CGFloat = 4
}

extension View {
    /// Habille une page : fond ciel (ou nuit), texte brun, commandes en élixir.
    func pageChantier() -> some View {
        foregroundStyle(Theme.Couleur.texte)
            .tint(Theme.Couleur.elixirTexte)
            .background(Theme.Couleur.fond.ignoresSafeArea())
    }

    /// Étiquette de rubrique (« CATÉGORIES »).
    func etiquetteChantier() -> some View {
        font(Theme.Police.etiquette)
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Theme.Couleur.texteDoux)
    }

    /// Tuile du jeu : fond clair, bord net, et un socle plus sombre dessous qui lui donne de l'épaisseur.
    func tuileChantier() -> some View {
        background {
            RoundedRectangle(cornerRadius: Theme.rayon)
                .fill(Theme.Couleur.trait)
                .offset(y: Theme.socle)
            RoundedRectangle(cornerRadius: Theme.rayon)
                .fill(Theme.Couleur.surface)
                .strokeBorder(Theme.Couleur.trait, lineWidth: Theme.bord)
        }
        .padding(.bottom, Theme.socle)
    }
}

/// Filet horizontal fin.
struct Filet: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Couleur.trait)
            .frame(height: Theme.filet)
            .accessibilityHidden(true)
    }
}
