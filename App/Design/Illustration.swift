import VillagePlannerKit
import SwiftUI
import UIKit

/// Les images du jeu embarquées (ClashKingAssets, `outils maj-images`) : `<id>_<niveau>.webp` pour les bâtiments
/// et les pièges, `<id>.webp` pour les unités, héros, familiers et équipements.
enum Illustrations {
    /// L'icône du type, sinon l'image du niveau demandé, sinon celle du niveau le plus proche en dessous
    /// (la forge 10 manque à la source). Niveau 0 (pas encore construit) : le niveau 1.
    static func image(_ id: Int, niveau: Int) -> UIImage? {
        if let icone = UIImage(named: "\(id).webp") { return icone }
        for n in stride(from: max(niveau, 1), through: 1, by: -1) {
            if let image = UIImage(named: "\(id)_\(n).webp") { return image }
        }
        return nil
    }

    /// Une image différente par niveau : seuls ces types ont un fantôme distinct de leur niveau actuel.
    static func changeAvecLeNiveau(_ id: Int) -> Bool { UIImage(named: "\(id)_1.webp") != nil }

    /// Le terrain du Cap : la jungle au soleil le jour, le décor classique de nuit en thème sombre.
    static func decor(_ schema: ColorScheme) -> UIImage? {
        UIImage(named: schema == .dark ? "decor-nuit.webp" : "decor-jour.webp")
    }
}

/// Un élément dessiné à son niveau actuel, avec en fantôme son niveau maximum derrière lui.
/// Après un import, l'image part de l'ancien niveau et monte sous les yeux (fondu seul si « Réduire les animations »).
/// Décorative : le texte de la ligne dit déjà le nom et les niveaux.
struct Illustration: View {
    let id: Int
    let niveau: Int
    /// Niveau maximum à montrer en fantôme ; nil ou atteint : pas de fantôme.
    var maximum: Int? = nil
    var taille: CGFloat = 56
    /// Le niveau en pastille dans le coin, comme sur les icônes du jeu.
    var avecPastille = true
    /// Où l'image est montrée : la montée se joue une fois par endroit (Cap, lignes du Village).
    var lieu = "ligne"

    @Environment(ModeleApp.self) private var modele
    @Environment(\.accessibilityReduceMotion) private var reduire
    @State private var montre: Int?
    @State private var eclat = 0

    private var fantome: Int? {
        guard let maximum, maximum > niveau, Illustrations.changeAvecLeNiveau(id) else { return nil }
        return maximum
    }

    var body: some View {
        let actuel = montre ?? niveau
        // Avec un fantôme et un niveau actuel, chacun prend un peu moins de place :
        // l'actuel devant à gauche, le maximum derrière à droite. Rien de construit : le fantôme seul, au centre.
        let deux = fantome != nil && actuel > 0
        let cote = deux ? taille * 0.8 : taille
        ZStack {
            if let fantome, let image = Illustrations.image(id, niveau: fantome) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: cote, height: cote)
                    .saturation(0)
                    .brightness(0.15)
                    .opacity(deux ? 0.35 : 0.55)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: deux ? .topTrailing : .center)
            }
            if actuel > 0, let image = Illustrations.image(id, niveau: actuel) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(width: cote, height: cote)
                    .shadow(color: Theme.Couleur.ombre, radius: 2, y: 2)
                    .id(actuel)
                    .transition(reduire ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    .overlay(alignment: .bottomLeading) {
                        if avecPastille { Pastille(texte: "\(actuel)") }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: deux ? .bottomLeading : .center)
            }
            if !reduire {
                // Éclat d'or à la montée : invisible au repos (t = 1), joué de 0 à 1 à chaque montée.
                Image(systemName: "sparkles")
                    .font(Theme.Police.eclat(taille * 0.32))
                    .foregroundStyle(Theme.Couleur.or)
                    .shadow(color: Theme.Couleur.ombre, radius: 1, y: 1)
                    .keyframeAnimator(initialValue: 1.0, trigger: eclat) { vue, t in
                        vue.scaleEffect(0.6 + t * 0.8).opacity(t < 1 ? 1 - t * t : 0)
                    } keyframes: { _ in
                        LinearKeyframe(0.0, duration: 0)
                        LinearKeyframe(1.0, duration: 0.7)
                    }
                    .offset(x: taille * 0.25, y: -taille * 0.25)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
        .sensoryFeedback(.success, trigger: eclat)
        .task(id: niveau) {
            guard let ancien = modele.montee(id: id, niveau: niveau, lieu: lieu) else { montre = nil; return }
            montre = ancien
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(reduire ? .easeInOut(duration: 0.4) : .spring(duration: 0.5, bounce: 0.5)) {
                montre = nil
                eclat += 1
            }
        }
    }
}

/// Le niveau en petite pastille de bois, chiffres du jeu.
struct Pastille: View {
    let texte: String

    var body: some View {
        Text(texte)
            .font(Theme.Police.badge)
            .foregroundStyle(Theme.Couleur.surBois)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.Couleur.bois, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.Couleur.surBois.opacity(0.5), lineWidth: 1))
            .fixedSize()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityHidden(true)      // le niveau est dans le texte de la ligne ou le libellé du terrain
    }
}

/// Un élément posé autour de l'hôtel de ville : à son niveau, son niveau maximum en fantôme.
struct Environ: Hashable {
    let id: Int
    let niveau: Int
    let maximum: Int
}

/// Le terrain du Cap : le décor du jeu dans un cadre de bois, l'hôtel de ville au milieu.
/// Sans HDV (premier lancement), l'HDV maximum en fantôme : le terrain attend le village.
/// `autour` : jusqu'à quatre éléments (deux de chaque côté), ceux dont dépend la date du cap.
struct Terrain: View {
    let hdv: Int
    var fantome: Int? = nil
    var autour: [Environ] = []
    /// Ce que VoiceOver dit du terrain : l'HDV et les éléments dont dépend la date (l'image seule ne dit rien).
    var libelle = ""

    @Environment(\.colorScheme) private var schema
    @ScaledMetric(relativeTo: .largeTitle) private var hauteur: CGFloat = 210

    var body: some View {
        let h = min(hauteur, 280)
        Rectangle().fill(.clear)
            .frame(height: h)
            .frame(maxWidth: .infinity)
            .background {
                if let decor = Illustrations.decor(schema) {
                    Image(uiImage: decor).resizable().interpolation(.high).scaledToFill()
                        .scaleEffect(1.25)
                }
            }
            .overlay {
                Illustration(id: Village.townHallID, niveau: hdv, maximum: fantome, taille: h * 0.78, avecPastille: false, lieu: "cap")
                    .offset(y: -h * 0.02)
            }
            .overlay { flancs(h) }
            .clipShape(.rect(cornerRadius: Theme.rayon))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.rayon).strokeBorder(Theme.Couleur.bois, lineWidth: Theme.bord * 2)
            }
            .accessibilityElement()
            .accessibilityLabel(libelle)
            .accessibilityHidden(libelle.isEmpty)
    }

    /// Deux colonnes de part et d'autre de l'hôtel de ville (la première à gauche, la deuxième à droite…).
    private func flancs(_ h: CGFloat) -> some View {
        let cote = h * 0.4
        func colonne(_ elements: [Environ]) -> some View {
            VStack(spacing: h * 0.06) {
                ForEach(elements, id: \.self) { e in
                    Illustration(id: e.id, niveau: e.niveau, maximum: e.maximum, taille: cote, lieu: "cap-autour")
                }
            }
        }
        let gauche = autour.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let droite = autour.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return HStack {
            colonne(gauche)
            Spacer()
            colonne(droite)
        }
        .padding(.horizontal, h * 0.05)
    }
}
