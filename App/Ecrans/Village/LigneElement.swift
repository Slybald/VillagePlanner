import VillagePlannerKit
import SwiftUI

/// Un groupe d'exemplaires identiques : nom, niveau actuel et maximum, minuteur.
/// `complement` : le temps et le coût restants (T10).
struct LigneElement: View {
    let element: Element
    let nom: String
    var complement: String? = nil
    /// nil : pas de bouton ; sinon l'élément est-il épinglé, et ce que fait le bouton (T17).
    var epingle: Bool? = nil
    var basculerEpingle: () -> Void = {}

    @ScaledMetric(relativeTo: .body) private var image: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        // Aux tailles d'accessibilité, l'image passe au-dessus du texte pour lui laisser toute la largeur.
        let disposition = tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Espace.s))
                                                          : AnyLayout(HStackLayout(spacing: Theme.Espace.m))
        disposition {
            Illustration(id: element.itemID, niveau: element.level, maximum: element.maxLevel, taille: min(image, 110))
            texte
        }
        .accessibilityElement(children: .combine)
        .padding(Theme.Espace.s)
        .overlay(alignment: .topTrailing) {
            if let epingle {
                Button(action: basculerEpingle) {
                    Image(systemName: epingle ? "pin.fill" : "pin")
                        .font(Theme.Police.texte)
                        .foregroundStyle(epingle ? Theme.Couleur.elixirTexte : Theme.Couleur.texteDoux)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(epingle ? "Désépingler \(nom)" : "Épingler \(nom)")
            }
        }
        .tuilePlanner()
    }

    private var texte: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(element.count > 1 ? "\(nom) × \(element.count)" : nom)
                .font(Theme.Police.texte)
            Text(niveau)
                .font(Theme.Police.chiffreDetail)
                .foregroundStyle(Theme.Couleur.texteDoux)
            if element.upgrading {
                Text(minuteur)
                    .font(Theme.Police.detail.weight(.semibold))
                    .foregroundStyle(Theme.Couleur.elixirTexte)
            }
            if let complement {
                Text(complement).font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, epingle == nil ? 0 : 36)
    }

    private var niveau: String {
        element.level == 0 ? "à construire · niveau max \(element.maxLevel)"
                           : "niveau \(element.level) sur \(element.maxLevel)"
    }

    /// Minuteur illisible : « en cours » sans date.
    private var minuteur: String {
        guard let fin = element.upgradeEnds else { return "en cours" }
        let date = fin.formatted(Date.FormatStyle(locale: Locale(identifier: "fr_FR")).day().month(.abbreviated).hour().minute())
        return "en cours · fin le \(date)"
    }
}
