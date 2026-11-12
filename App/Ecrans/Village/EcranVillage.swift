import ChantierKit
import SwiftUI

/// L'écran Village (PLAN §3.3) : les catégories, puis le détail de chacune à la demande.
struct EcranVillage: View {
    let affiche: VillageAffiche
    let reference: ReferenceData

    @Environment(\.dynamicTypeSize) private var tailleTexte
    @ScaledMetric(relativeTo: .body) private var image: CGFloat = 52
    @State private var chemin: [ChantierKit.Category] = Self.cheminDeCapture()

    private var village: Village { affiche.village }
    private var restant: RestantAffiche { RestantAffiche(affiche: affiche, reference: reference) }

    /// Débogage seulement : `-categorie <défenses|…>` ouvre la catégorie au lancement (captures).
    private static func cheminDeCapture() -> [ChantierKit.Category] {
        #if DEBUG
        if let nom = UserDefaults.standard.string(forKey: "categorie"),
           let categorie = ChantierKit.Category(rawValue: nom) { return [categorie] }
        #endif
        return []
    }

    var body: some View {
        NavigationStack(path: $chemin) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if affiche.estExemple { MarqueExemple() }
                    VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                        categories
                        if !village.unknown.isEmpty { inconnus.id("inconnus") }
                        MentionLegale()
                    }
                    .padding(.horizontal, Theme.Espace.marge)
                    .padding(.vertical, Theme.Espace.l)
                }
            }
            #if DEBUG
            .task { if ProcessInfo.processInfo.arguments.contains("-inconnus") { proxy.scrollTo("inconnus", anchor: .top) } }   // captures
            #endif
            }
            .pageChantier()
            .navigationTitle("Village")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ChantierKit.Category.self) { categorie in
                EcranCategorie(categorie: categorie, affiche: affiche, reference: reference)
            }
        }
    }

    private var disposition: AnyLayout {
        tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Espace.s))
                                        : AnyLayout(HStackLayout(spacing: Theme.Espace.m))
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Catégories").etiquetteChantier().padding(.bottom, Theme.Espace.s)
            let restant = restant
            if let mention = restant.mentionReduction {
                Text(mention).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                    .padding(.bottom, Theme.Espace.s)
            }
            ForEach(ChantierKit.Category.ordreAffichage, id: \.self) { categorie in
                NavigationLink(value: categorie) {
                    HStack(spacing: Theme.Espace.m) {
                        // Aux tailles d'accessibilité, l'image passe au-dessus du texte.
                        disposition {
                            Illustration(id: categorie.representant, niveau: village.niveau(de: categorie.representant),
                                         taille: min(image, 72), avecPastille: false, lieu: "village")
                            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                                resume(categorie)
                                if let reste = restant.resume(categorie) {
                                    Text(reste).font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Image(systemName: "chevron.right")
                            .font(Theme.Police.detail)
                            .foregroundStyle(Theme.Couleur.texteDoux)
                            .accessibilityHidden(true)
                    }
                    .padding(Theme.Espace.m)
                    .contentShape(Rectangle())
                    .tuileChantier()
                }
                .buttonStyle(.plain)
                .padding(.bottom, Theme.Espace.s)
            }
        }
    }

    /// Pourcentage, ou texte quand il n'y en a pas (A4 : rien à faire ; V7 : HDV inconnu).
    @ViewBuilder private func resume(_ categorie: ChantierKit.Category) -> some View {
        if let progression = affiche.rapport.categories[categorie] {
            if progression.hasWork, tailleTexte.isAccessibilitySize {
                // Un nom comme « Défenses » ne tient pas à côté de son chiffre : l'un sous l'autre.
                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    Text(categorie.nom).font(Theme.Police.texte)
                    Text(progression.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(Theme.Police.chiffre).foregroundStyle(Theme.Couleur.texteDoux)
                    Jauge(valeur: progression.fraction, taille: .fine, couleur: categorie.couleur).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else if progression.hasWork {
                LigneCategorie(nom: categorie.nom, valeur: progression.fraction, avecJauge: true, couleur: categorie.couleur)
            } else {
                LigneTexte(nom: categorie.nom, valeur: "rien à faire")
            }
        } else {
            let n = Elements.de(categorie, village: village, reference: reference).reduce(0) { $0 + $1.element.count }
            LigneTexte(nom: categorie.nom, valeur: "\(n) élément\(n > 1 ? "s" : "")")
        }
    }

    /// V5 : identifiants absents de la référence, exclus des calculs.
    private var inconnus: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Éléments inconnus").etiquetteChantier().padding(.bottom, Theme.Espace.xs)
            Text("Absents des données de l'app, donc exclus des calculs.")
                .font(Theme.Police.detail)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .padding(.bottom, Theme.Espace.s)
            ForEach(Array(village.unknown.enumerated()), id: \.offset) { _, entree in
                LigneInconnu(entree: entree)
                Filet()
            }
        }
    }
}

private struct LigneInconnu: View {
    let entree: ExportEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text("Identifiant \(String(entree.id))" + (entree.count > 1 ? " × \(entree.count)" : ""))
                .font(Theme.Police.texte)
            if let niveau = entree.level {
                Text("niveau \(niveau)").font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Espace.s)
        .accessibilityElement(children: .combine)
    }
}

/// Mention exigée par la politique des contenus de fans de Supercell (PLAN §9), et crédits.
struct MentionLegale: View {
    var body: some View {
        VStack(spacing: Theme.Espace.s) {
            Text("This material is unofficial and is not endorsed by Supercell. For more information see Supercell's Fan Content Policy: www.supercell.com/fan-content-policy.")
            Text("Ce contenu n'est pas officiel et n'est pas approuvé par Supercell. Pour en savoir plus, voir la politique de contenu des fans de Supercell.")
            Text("Illustrations : ClashKingAssets (assets.clashk.ing). Polices Lilita One et Fredoka, licence SIL OFL.")
        }
        .font(Theme.Police.detail)
        .foregroundStyle(Theme.Couleur.texteDoux)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Espace.l)
        .accessibilityElement(children: .combine)
    }
}
