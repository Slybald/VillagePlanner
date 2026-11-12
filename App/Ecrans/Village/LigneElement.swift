import ChantierKit
import SwiftUI

/// Un groupe d'exemplaires identiques : nom, niveau actuel et maximum, minuteur.
/// `complement` reçoit plus tard le temps et le coût restants (T10) sans toucher au reste.
struct LigneElement: View {
    let element: Element
    let nom: String
    var complement: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(element.count > 1 ? "\(nom) × \(element.count)" : nom)
                .font(Theme.Police.texte)
            Text(niveau)
                .font(Theme.Police.chiffreDetail)
                .foregroundStyle(Theme.Couleur.encreDouce)
            if element.upgrading {
                Text(minuteur)
                    .font(Theme.Police.detail.weight(.semibold))
                    .foregroundStyle(Theme.Couleur.encre)
            }
            if let complement {
                Text(complement).font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.encreDouce)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Espace.s)
        .accessibilityElement(children: .combine)
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
