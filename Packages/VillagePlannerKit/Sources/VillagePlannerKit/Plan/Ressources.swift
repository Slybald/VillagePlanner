import Foundation

// Les ressources à réunir (PLAN §5.5) : le plan donne, pour chaque lancement, sa date, son coût et sa ressource.
//
// Règles de ce fichier, reprises dans les noms de tests (RessourcesTests) :
//  R1  la prochaine échéance : par ressource, le montant à avoir à la date du prochain lancement, et aux deux suivantes ;
//  R2  le rythme : la somme des coûts lancés dans les sept prochains jours, divisée par 7 ;
//  R3  les murs : leur coût restant, divisé par le nombre de jours jusqu'au cap, donne le rythme en plus.
// Décisions :
//  - une échéance regroupe tous les lancements du même instant (plusieurs postes libres en même temps) ; son montant
//    n'est pas cumulé avec les précédentes ;
//  - les minuteurs de la photo sont déjà payés : seuls les lancements du plan comptent ; un lancement à `now` compte ;
//  - les sept jours sont [now, now + 7 j[ : un lancement pile à +7 j est dans la semaine suivante ;
//  - les rythmes sont arrondis à l'entier supérieur : un rythme arrondi vers le bas n'atteindrait pas la somme ;
//  - murs : coût en ressource principale (celle de la référence) ; moins d'un jour avant le cap, on compte un jour ;
//    sans cap (tout est fait), pas de rythme : il n'y a pas de date où finir ;
//  - rien ne dépend de la capacité des réserves (P7, abandonnée).

/// Ce qu'une ressource demande : les prochaines échéances, le rythme sur sept jours, les murs.
public struct ResourceNeed: Sendable, Equatable {
    /// Le montant à avoir à une date de lancement.
    public struct Due: Sendable, Equatable {
        public let date: Date
        public let amount: Int
    }

    public let resource: Resource
    /// R1 : au plus trois, dans l'ordre du temps.
    public let dues: [Due]
    /// R2 : somme des coûts lancés dans les sept prochains jours, et son rythme par jour.
    public let weekTotal: Int
    public let perDay: Int
    /// R3 : coût restant des murs dans cette ressource ; rythme par jour pour les finir au cap (`wallsEnd`),
    /// nil quand il n'y a rien à payer ou pas de cap.
    public let wallsRemaining: Int
    public let wallsPerDay: Int?
    public let wallsEnd: Date?
}

/// `remaining` : les pas de `remainingSteps` qui ont servi au plan (les murs n'y sont pas simulés, P6).
/// Une ressource sans échéance, sans lancement dans la semaine et sans mur n'apparaît pas. Ordre de `Resource.allCases`.
public func resourceNeeds(of plan: Plan, remaining: [UpgradeStep]) -> [ResourceNeed] {
    let weekEnd = plan.now.addingTimeInterval(7 * 86_400)
    let launches = plan.steps.filter { !$0.fromSnapshot && $0.start >= plan.now }
    let walls = RemainingTotals(remaining.filter { $0.category == .walls }).costs
    // Moins d'un jour avant le cap : un jour (le rythme ne dépasse pas le coût entier).
    let wallDays = plan.cap.map { max(Int($0.timeIntervalSince(plan.now).rounded(.up)), 86_400) }

    return Resource.allCases.compactMap { resource in
        var byDate: [Date: Int] = [:]
        var week = 0
        for s in launches {
            let amount = s.costs.filter { $0.resource == resource }.reduce(0) { $0 + $1.amount }
            guard amount > 0 else { continue }
            byDate[s.start, default: 0] += amount                             // R1
            if s.start < weekEnd { week += amount }                           // R2
        }
        let dues = byDate.sorted { $0.key < $1.key }.prefix(3).map { ResourceNeed.Due(date: $0.key, amount: $0.value) }
        let wall = walls[resource] ?? 0
        guard !dues.isEmpty || wall > 0 else { return nil }
        let wallsPerDay = wall > 0 ? wallDays.map { (wall * 86_400 + $0 - 1) / $0 } : nil     // R3
        return ResourceNeed(resource: resource, dues: dues, weekTotal: week, perDay: (week + 6) / 7,
                            wallsRemaining: wall, wallsPerDay: wallsPerDay, wallsEnd: wallsPerDay == nil ? nil : plan.cap)
    }
}
