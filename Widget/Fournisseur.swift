import ChantierKit
import SwiftUI
import WidgetKit

/// Une entrée de la chronologie : la date, ce qu'il faut montrer, et où sont les images.
struct EntreeChantier: TimelineEntry {
    let date: Date
    let contenu: WidgetContenu
    /// Le conteneur partagé ; nil sans lui (les images manquent, le reste s'affiche).
    let racine: URL?
}

/// La chronologie vient de `WidgetChronologie` (ChantierKit, fonction pure testée). Le fournisseur lit l'état écrit par
/// l'app, c'est tout : pas de réseau, pas de calcul de plan. Politique `.never` : le système change d'entrée à l'heure
/// de chacune, et l'app recharge la chronologie à chaque import.
struct Fournisseur: TimelineProvider {
    private var racine: URL? { Stockage.conteneurPartage(bundleID: Bundle.main.bundleIdentifier) }

    func placeholder(in context: Context) -> EntreeChantier {
        EntreeChantier(date: .now, contenu: .postes(Exemple.lignes(depuis: .now)), racine: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (EntreeChantier) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entrees().first!)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeChantier>) -> Void) {
        completion(Timeline(entries: entrees(), policy: .never))
    }

    private func entrees() -> [EntreeChantier] {
        let racine = racine
        let etat = racine.flatMap { WidgetEtat.lire(dans: $0) }
        return WidgetChronologie.entrees(etat: etat, maintenant: .now).map {
            EntreeChantier(date: $0.date, contenu: $0.contenu, racine: racine)
        }
    }
}

/// Des couloirs inventés pour la galerie des widgets.
enum Exemple {
    static func lignes(depuis date: Date) -> [WidgetLigne] {
        let etat = WidgetEtat(photo: date, postes: [
            .init(genre: .builder, numero: 0, imageLibre: nil, travail: .init(nom: "Canon", niveau: 12, fin: date.addingTimeInterval(2 * 3600 + 14 * 60), image: nil)),
            .init(genre: .builder, numero: 1, imageLibre: nil, travail: nil),
            .init(genre: .builder, numero: 2, imageLibre: nil, travail: .init(nom: "Mortier", niveau: 9, fin: date.addingTimeInterval(30 * 3600), image: nil)),
            .init(genre: .laboratory, numero: 0, imageLibre: nil, travail: .init(nom: "Barbare", niveau: 8, fin: date.addingTimeInterval(5 * 3600), image: nil)),
        ])
        guard case .postes(let lignes) = WidgetChronologie.entrees(etat: etat, maintenant: date).first?.contenu else { return [] }
        return lignes
    }
}
