import Foundation

/// Une notification à planifier (T26) : quand, et ce qu'elle dit.
public struct Echeance: Sendable, Equatable {
    public let date: Date
    public let titre: String
    public let corps: String

    public init(date: Date, titre: String, corps: String) {
        self.date = date
        self.titre = titre
        self.corps = corps
    }
}

/// Les notifications du plan (PLAN §7.4) : une par fin de minuteur de la photo, regroupées, reportées hors des
/// heures sans jeu, au plus `plafond`. Fonction pure : la date courante est un paramètre.
public enum Echeances {
    /// iOS garde 64 notifications en attente ; l'app n'en demande jamais plus de vingt.
    public static let plafond = 20
    /// Deux fins séparées de moins que cela (secondes) tiennent dans une seule notification.
    public static let fenetre: TimeInterval = 300

    /// `nom` : le nom français d'un type (identifiant → nom). Ne passent que les minuteurs lisibles de la photo qui
    /// finissent après `now` ; un minuteur illisible n'a pas de date, aucune notification n'est inventée.
    public static func liste(plan: Plan, nom: (Int) -> String, quietHours: QuietHours?, now: Date) -> [Echeance] {
        let fins = plan.steps
            .filter { $0.fromSnapshot && $0.end > now && $0.step.status != .inProgress(ends: nil) }
            .map { (pas: $0, quand: quietHours?.release($0.end) ?? $0.end) }
            .sorted { ($0.quand, $0.pas.lane) < ($1.quand, $1.pas.lane) }

        var groupes: [[(pas: ScheduledStep, quand: Date)]] = []
        for fin in fins {
            if let debut = groupes.last?.first?.quand, fin.quand.timeIntervalSince(debut) < fenetre {
                groupes[groupes.count - 1].append(fin)
            } else {
                groupes.append([fin])
            }
        }
        return groupes.prefix(plafond).map { groupe in
            let lignes = groupe.map { ligne($0.pas, plan: plan, nom: nom) }
            // La notification part quand le dernier du groupe est libre : tous le sont alors.
            return Echeance(date: groupe.map(\.quand).max()!,
                            titre: groupe.count == 1 ? "\(poste(groupe[0].pas)) libre" : "\(groupe.count) postes libres",
                            corps: lignes.joined(separator: "\n"))
        }
    }

    private static func poste(_ pas: ScheduledStep) -> String {
        switch pas.worker {
        case .builder: "Ouvrier \(pas.lane + 1)"
        case .laboratory: "Laboratoire"
        case .petHouse: "Maison des familiers"
        case .blacksmith: "Forge"
        }
    }

    /// « Canon niveau 12 terminé. Ensuite : Mortier niveau 8. »
    private static func ligne(_ pas: ScheduledStep, plan: Plan, nom: (Int) -> String) -> String {
        let fini = "\(nom(pas.step.itemID)) niveau \(pas.step.level) terminé."
        let suivant = plan.steps.filter { !$0.fromSnapshot && $0.worker == pas.worker && $0.lane == pas.lane && $0.start >= pas.end }
            .min { $0.start < $1.start }
        guard let suivant else { return fini }
        return fini + " Ensuite : \(nom(suivant.step.itemID)) niveau \(suivant.step.level)."
    }
}
