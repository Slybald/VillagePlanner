import ChantierKit
import SwiftUI
import UIKit

/// La DA « Chantier vivant » pour le widget : la palette du jeu (catalogue copié de l'app, mêmes valeurs en clair et en
/// sombre), Lilita One pour les chiffres et les titres, Fredoka pour le texte (déclarées dans Widget-Info.plist).
enum Teinte {
    static let fond = Color(.fond)
    static let surface = Color(.surface)
    static let trait = Color(.trait)
    static let texte = Color(.texte)
    static let texteDoux = Color(.texteDoux)
    static let elixirTexte = Color(.elixirTexte)
    static let bois = Color(.bois)

    static func titre(_ taille: CGFloat) -> Font { .custom("Lilita One", fixedSize: taille) }
    static func texte(_ taille: CGFloat) -> Font { .custom("Fredoka", fixedSize: taille).weight(.medium) }
}

/// Une image écrite par l'app dans le conteneur partagé ; rien quand elle manque.
struct ImageChantier: View {
    let nom: String?
    let racine: URL?
    let cote: CGFloat

    var body: some View {
        if let nom, let racine, let image = UIImage(contentsOfFile: WidgetEtat.dossierImages(dans: racine).appending(path: nom).path) {
            Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: cote, height: cote)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                .accessibilityHidden(true)
        }
    }
}

/// Le compte à rebours : un texte que le système anime seul, en heures, minutes, secondes sous un jour (il s'arrête à
/// zéro), en jours et heures au-delà. Le minuteur suivant est une autre entrée : rien ne dépasse jamais zéro.
struct CompteARebours: View {
    let fin: Date
    let depuis: Date

    var body: some View {
        if WidgetChronologie.compteAReboursExact(fin: fin, depuis: depuis) {
            Text(timerInterval: depuis...fin, pauseTime: fin, countsDown: true, showsHours: true)
        } else {
            Text(fin, style: .relative)
        }
    }
}
