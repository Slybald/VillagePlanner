import ChantierKit
import SwiftUI

/// Les mots du taux d'occupation : le même chiffre dans l'Historique et sur l'écran Cap.
enum TexteOccupation {
    static func poste(_ poste: WorkerKind) -> String {
        switch poste {
        case .builder: "Ouvriers"
        case .laboratory: "Labo"
        case .petHouse, .blacksmith: "Familiers"
        }
    }

    /// « 91 % », ou « environ 91 % » quand une réduction a pu jouer : le chiffre est le milieu d'un intervalle.
    static func taux(_ milieu: Double, approximatif: Bool) -> String {
        (approximatif ? "environ\u{00A0}" : "") + pourcent(milieu)
    }

    static func pourcent(_ valeur: Double) -> String { "\(Int((valeur * 100).rounded()))\u{202F}%" }

    /// « entre 88 et 94 % » quand on connaît l'intervalle ; nil quand il est étroit.
    static func intervalle(_ bas: Double, _ haut: Double) -> String? {
        let (a, b) = (Int((bas * 100).rounded()), Int((haut * 100).rounded()))
        return a == b ? nil : "entre \(a) et \(b)\u{202F}%"
    }

    static func taux(_ poste: PostOccupation) -> String { taux(poste.midRate, approximatif: poste.isApproximate) }
    static func taux(_ taux: Rhythm.Rate) -> String { Self.taux(taux.mid, approximatif: taux.isApproximate) }
}

/// Le taux d'occupation de l'Historique : les ouvriers en grand, puis le labo et les familiers, avec ce qui le fonde.
struct CarteOccupation: View {
    struct Ligne: Identifiable {
        let poste: WorkerKind
        let texte: String
        let intervalle: String?
        var id: WorkerKind { poste }
    }

    let titre: String
    let lignes: [Ligne]
    let fondement: String
    var note: String? = nil

    @Environment(\.dynamicTypeSize) private var tailleTexte

    /// Sur les 30 derniers jours (le rythme du cap).
    init(rythme: Rhythm) {
        titre = "Postes au travail"
        lignes = Occupation.kinds.compactMap { poste in
            rythme.rates[poste].map { Ligne(poste: poste, texte: TexteOccupation.taux($0),
                                            intervalle: TexteOccupation.intervalle($0.low, $0.high)) }
        }
        fondement = "Sur les 30 derniers jours, d'après \(rythme.photos) photos."
        note = nil
    }

    /// Avant que le rythme existe : la dernière paire de photos, et ce qu'il manque.
    init(derniere o: Occupation) {
        titre = "Postes au travail"
        lignes = o.posts.map {
            Ligne(poste: $0.worker, texte: TexteOccupation.taux($0),
                  intervalle: $0.isApproximate ? TexteOccupation.intervalle($0.rate.lowerBound, $0.rate.upperBound) : nil)
        }
        fondement = "Entre tes deux dernières photos."
        note = "La date « à ton rythme » apparaîtra avec trois photos couvrant au moins sept jours."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text(titre).etiquetteChantier()
            if let premiere = lignes.first {
                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    Text(TexteOccupation.poste(premiere.poste) + " au travail")
                        .font(Theme.Police.texte)
                    Text(premiere.texte)
                        .font(Theme.Police.grandeDate)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let i = premiere.intervalle {
                        Text(i).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(lignes.dropFirst()) { l in
                VStack(alignment: .leading, spacing: 0) {
                    Filet()
                    HStack(alignment: .firstTextBaseline) {
                        Text(TexteOccupation.poste(l.poste)).font(Theme.Police.texte)
                        Spacer(minLength: Theme.Espace.s)
                        Text(l.texte).font(Theme.Police.chiffre)
                    }
                    .padding(.top, Theme.Espace.s)
                }
                .accessibilityElement(children: .combine)
            }
            Text(fondement + " Estimé d'après les minuteurs de tes photos ; la nuit déclarée dans ton profil ne compte pas.")
                .font(Theme.Police.detail)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }
}
