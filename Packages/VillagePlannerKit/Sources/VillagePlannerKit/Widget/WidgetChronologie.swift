import Foundation

/// Une ligne du widget : un couloir à une date donnée.
public struct WidgetLigne: Equatable, Sendable {
    public let genre: WorkerKind
    public let numero: Int
    public let titre: String
    /// Libre : l'image du poste ; occupé : celle de l'élément en cours.
    public let image: String?
    /// Ce qui tourne ; nil quand le poste est libre.
    public let travail: WidgetEtat.Travail?

    public var estLibre: Bool { travail == nil }
}

/// Ce que le widget montre à partir d'une date.
public enum WidgetContenu: Equatable, Sendable {
    /// Aucune photo : le widget invite à ouvrir l'app.
    case ouvrirApp
    /// Les couloirs à cette date.
    case postes([WidgetLigne])
    /// Tous les minuteurs connus sont finis : la photo ne dit plus rien.
    case photoARefaire
}

public struct WidgetEntree: Equatable, Sendable {
    public let date: Date
    public let contenu: WidgetContenu
}

extension [WidgetLigne] {
    public var libres: [WidgetLigne] { filter(\.estLibre) }
    /// Le poste occupé qui se libère le premier.
    public var prochain: WidgetLigne? { filter { !$0.estLibre }.min { $0.travail!.fin < $1.travail!.fin } }
}

/// La chronologie du widget (PLAN §7.3) : une fonction pure, sans horloge ni lecture de fichier.
/// Une entrée à `maintenant`, une à la fin de chaque minuteur, et « photo à refaire » à la fin du dernier.
/// WidgetKit change d'entrée à l'heure juste, hors du budget de rafraîchissements d'iOS.
public enum WidgetChronologie {
    /// Une photo sans aucun minuteur dit « tout est libre » pendant ce délai, puis elle est à refaire.
    public static let delaiSansMinuteur: TimeInterval = 24 * 3600
    /// En dessous de ce temps restant, le compte à rebours s'affiche en heures, minutes et secondes ; au-dessus, en jours et heures.
    public static let seuilCompteAReboursExact: TimeInterval = 24 * 3600

    public static func entrees(etat: WidgetEtat?, maintenant: Date) -> [WidgetEntree] {
        guard let etat else { return [WidgetEntree(date: maintenant, contenu: .ouvrirApp)] }
        let fins = Set(etat.postes.compactMap { $0.travail?.fin }).sorted()
        let derniere = fins.last ?? etat.photo.addingTimeInterval(delaiSansMinuteur)
        guard maintenant < derniere else { return [WidgetEntree(date: maintenant, contenu: .photoARefaire)] }

        func lignes(a date: Date) -> [WidgetLigne] {
            etat.postes.map { poste in
                let travail = poste.travail.flatMap { $0.fin > date ? $0 : nil }
                return WidgetLigne(genre: poste.genre, numero: poste.numero, titre: poste.titre,
                                   image: travail?.image ?? poste.imageLibre, travail: travail)
            }
        }
        // Une entrée par date où quelque chose change, la fin du dernier minuteur exceptée : elle dit « photo à refaire ».
        let dates = [maintenant] + fins.filter { $0 > maintenant && $0 < derniere }
        return dates.map { WidgetEntree(date: $0, contenu: .postes(lignes(a: $0))) }
            + [WidgetEntree(date: derniere, contenu: .photoARefaire)]
    }

    /// Le compte à rebours est-il en heures, minutes et secondes (texte `timerInterval`) plutôt qu'en jours et heures ?
    public static func compteAReboursExact(fin: Date, depuis date: Date) -> Bool {
        fin.timeIntervalSince(date) < seuilCompteAReboursExact
    }
}
