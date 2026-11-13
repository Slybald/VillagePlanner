import ChantierKit
import SwiftUI

/// Les deux dates du cap côte à côte : au plus tôt (postes jamais à l'arrêt) et à ton rythme (taux d'occupation des
/// 30 derniers jours). N'existe qu'à partir de trois photos couvrant sept jours (T24).
struct CarteRythme: View {
    let auPlusTot: Date
    let aTonRythme: Date
    let maintenant: Date
    let fuseau: TimeZone
    let rythme: Rhythm

    private var ecart: Int { Int(aTonRythme.timeIntervalSince(auPlusTot).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            colonne("Au plus tôt", date: "le\u{00A0}" + Lisible.jour(auPlusTot, now: maintenant, timeZone: fuseau),
                    detail: "postes jamais à l'arrêt")
            Filet()
            colonne("À ton rythme", date: "environ le\u{00A0}" + Lisible.jour(aTonRythme, now: maintenant, timeZone: fuseau),
                    detail: ecart >= 3600 ? Lisible.duree(ecart) + " de plus" : "le même jour")
            Filet()
            Text(phrase)
                .font(Theme.Police.detail)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
        .accessibilityElement(children: .contain)
    }

    private func colonne(_ titre: String, date: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(titre).etiquetteChantier()
            Text(date)
                .font(Theme.Police.chiffreGrand)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(detail).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// « Ouvriers au travail : environ 91 % sur les 30 derniers jours. »
    private var phrase: String {
        let poste = rythme.rates[.builder].map { "Ouvriers au travail : " + TexteOccupation.taux($0) } ?? "Rythme mesuré"
        return poste + " sur les 30 derniers jours, d'après \(rythme.photos) photos. La date suppose que ce rythme continue."
    }
}
