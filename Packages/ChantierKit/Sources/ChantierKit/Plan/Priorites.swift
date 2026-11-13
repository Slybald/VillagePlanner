import Foundation

// Les priorités (PLAN §5.3) : une file ordonnée par poste, sans planning ni horloge.
//
// Règles de ce fichier, reprises dans les noms de tests (PrioritesTests) :
//  File des ouvriers, rang (l'ordre des rangs dépend de l'orientation, table `Orientation.rankOrder`) :
//  P1  ce qui débloque (un bâtiment dont le niveau est le prérequis d'une autre amélioration restante),
//      puis le château de clan et les camps, puis les bâtiments à construire (V1) ;
//  P2  les héros ;  P3  les défenses clés, dans l'ordre de conseils.json ;  P4  les autres défenses et bâtiments ;
//  P5  les pièges ;  P6  les murs n'entrent jamais dans la file ;
//  P7  (réserves trop petites) n'est pas codée : reference.json ne donne pas la capacité des réserves (T04).
//  À égalité de rang :
//  E1  épinglé d'abord (les épingles passent même devant tout leur poste) ;
//  E2  la ressource la moins demandée par ce qui est déjà placé devant, en part de ce que la file en demande
//      au total (sinon l'élixir noir, cent fois moins cher en unités, passerait toujours avant l'or) ;
//  E3  la chaîne de niveaux restants la plus longue en durée ;  E4  l'identifiant.
//  Un pas n'entre qu'une fois ses prérequis dans la file des ouvriers atteints (village ou pas déjà placé) ;
//  sans quoi il attend, et passe en fin de file si rien ne les atteindra (la simulation le dira bloqué, S7).
//  Labo, familiers, forge : épinglés, puis (forge seulement, si l'API a été lue) les équipements équipés, puis l'ordre de conseils.json, puis le moins cher (`CostKey`), puis l'identifiant.
//  Les niveaux d'un même élément se suivent toujours dans l'ordre. Rien d'« en cours » n'est placé : c'est déjà lancé.

/// L'orientation du profil de jeu.
public enum Orientation: String, Sendable, Codable, CaseIterable {
    case balanced, attack, defense

    /// La table du PLAN §5.3, telle quelle.
    public var rankOrder: [BuilderRank] {
        switch self {
        case .balanced: [.p1, .p2, .p3, .p4, .p5]
        case .attack:   [.p2, .p1, .p3, .p4, .p5]
        case .defense:  [.p1, .p3, .p4, .p2, .p5]
        }
    }
}

/// Les rangs de la file des ouvriers (P6, les murs, n'y entrent pas).
public enum BuilderRank: Int, Sendable, CaseIterable { case p1 = 1, p2, p3, p4, p5 }

/// Quand conseiller de passer à l'HDV suivant.
public enum TownHallThreshold: String, Sendable, Codable, CaseIterable {
    /// Avancement total à 100 % (par défaut).
    case complete
    /// Dès que héros et labo sont terminés.
    case heroesAndLab
}

public enum NextTownHallAdvice: Sendable, Equatable { case notYet, advised }

/// Une amélioration placée dans une file, avec la règle qui lui donne son rang.
public struct PrioritizedStep: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        // File des ouvriers.
        case unlocks                    // P1 : prérequis d'une autre amélioration restante
        case armyAndCastle              // P1 : château de clan, camps
        case build                      // P1 : bâtiment à construire
        case hero                       // P2
        case keyDefense(position: Int)  // P3 : position dans la liste `defenses`
        case otherBuilding              // P4
        case trap                       // P5
        // Labo, familiers, forge.
        case advice(position: Int)      // position dans la liste du poste
        case cheapest                   // absent de la liste

        public var rank: BuilderRank? {
            switch self {
            case .unlocks, .armyAndCastle, .build: .p1
            case .hero: .p2
            case .keyDefense: .p3
            case .otherBuilding: .p4
            case .trap: .p5
            case .advice, .cheapest: nil
            }
        }

        /// Ordre à l'intérieur du rang : les trois parties de P1, la position dans la liste.
        var within: Int {
            switch self {
            case .unlocks: 0
            case .armyAndCastle: 1
            case .build: 2
            case .keyDefense(let p), .advice(let p): p
            case .cheapest: .max
            case .hero, .otherBuilding, .trap: 0
            }
        }
    }

    public let step: UpgradeStep
    public let reason: Reason
    public let pinned: Bool
}

/// Les files des quatre postes. `steps` vient de `remainingSteps` : les pas en cours y comptent pour les postes
/// occupés et la longueur des chaînes, mais ne sont pas placés.
public func priorities(of steps: [UpgradeStep], in village: Village, reference: ReferenceData,
                       advice: AdviceData, profile: Profile) -> [WorkerKind: [PrioritizedStep]] {
    Dictionary(uniqueKeysWithValues: WorkerKind.allCases.map { worker in
        (worker, worker == .builder ? builderQueue(steps, village, reference, advice, profile)
                                    : queue(for: worker, steps.filter { $0.worker == worker }, advice, profile, equipped: village.equipped))
    })
}

/// Passer à l'HDV suivant : selon le seuil du profil. Jamais au plus haut HDV connu de la référence.
public func nextTownHallAdvice(for village: Village, reference: ReferenceData, profile: Profile) -> NextTownHallAdvice {
    guard village.status != .unknownTownHall, village.townHall < reference.maxTownHall else { return .notYet }
    let categories = progress(of: village, reference: reference).categories
    let watched: [Category] = switch profile.nextTownHallThreshold {
    case .complete: Category.allCases
    case .heroesAndLab: [.heroes, .laboratory]
    }
    return watched.allSatisfy { c in categories[c].map { $0.done >= $0.total } ?? true } ? .advised : .notYet
}

// MARK: - Chaînes

/// Les pas à faire d'un même groupe d'exemplaires, du plus bas niveau au plus haut.
private struct Chain {
    let element: Element
    var steps: [UpgradeStep]
    /// Durée restante d'un exemplaire, en cours compris (E3) ; diminue à chaque pas placé.
    var left: Int
}

private func chains(_ steps: [UpgradeStep]) -> [Chain] {
    var out: [Chain] = []
    for s in steps {
        let i = out.firstIndex { $0.element == s.element } ?? { out.append(Chain(element: s.element, steps: [], left: 0)); return out.count - 1 }()
        out[i].left += s.remaining ?? 0
        if !s.isInProgress { out[i].steps.append(s) }
    }
    for i in out.indices { out[i].steps.sort { $0.level < $1.level } }
    return out.filter { !$0.steps.isEmpty }
}

/// E4 : un ordre total, pour qu'un mélange de l'entrée ne change rien.
private func identity(_ s: UpgradeStep) -> (Int, Int, Int, Int, Double) {
    (s.itemID, s.level, s.element.level, s.element.count, s.element.upgradeEnds?.timeIntervalSince1970 ?? -.infinity)
}

// MARK: - Labo, familiers, forge

private func queue(for worker: WorkerKind, _ steps: [UpgradeStep], _ advice: AdviceData,
                   _ profile: Profile, equipped: Set<Int>) -> [PrioritizedStep] {
    let list: AdviceList.Name? = switch worker {
    case .laboratory: .laboratory
    case .petHouse: .pets
    case .blacksmith: .equipment
    case .builder: nil
    }
    var pending = chains(steps)
    var out: [PrioritizedStep] = []
    func reason(_ s: UpgradeStep) -> PrioritizedStep.Reason {
        list.flatMap { advice.rank(of: s.itemID, in: $0) }.map { .advice(position: $0) } ?? .cheapest
    }
    while !pending.isEmpty {
        let best = pending.indices.min { a, b in
            let (x, y) = (pending[a].steps[0], pending[b].steps[0])
            let (px, py) = (profile.pinned.contains(x.itemID), profile.pinned.contains(y.itemID))
            if px != py { return px }
            // Forge (T30) : les équipements équipés d'abord, après les épingles ; le reste de l'ordre ne change pas.
            let (qx, qy) = (equipped.contains(x.itemID), equipped.contains(y.itemID))
            if worker == .blacksmith, qx != qy { return qx }
            let (rx, ry) = (reason(x).within, reason(y).within)
            if rx != ry { return rx < ry }
            let (cx, cy) = (CostKey(x.costs), CostKey(y.costs))
            if cx != cy { return cx < cy }
            return identity(x) < identity(y)
        }!
        let s = pending[best].steps.removeFirst()
        if pending[best].steps.isEmpty { pending.remove(at: best) }
        out.append(PrioritizedStep(step: s, reason: reason(s), pinned: profile.pinned.contains(s.itemID)))
    }
    return out
}

// MARK: - Ouvriers

private let clanCastleID = 1000014, armyCampID = 1000000

private func builderQueue(_ all: [UpgradeStep], _ village: Village, _ reference: ReferenceData,
                          _ advice: AdviceData, _ profile: Profile) -> [PrioritizedStep] {
    let steps = all.filter { $0.worker == .builder && $0.category != .walls }       // P6
    func requirements(_ s: UpgradeStep) -> [Requirement] {
        // Un bâtiment fusionné se construit sur ses bâtiments d'origine : ils sont ses prérequis.
        s.requires + (s.level == 1 ? reference.item(s.itemID)?.mergedFrom ?? [] : [])
    }
    // P1 : le niveau le plus haut que chaque type doit atteindre pour une autre amélioration restante (tous postes).
    var needed: [Int: Int] = [:]
    for s in all where !s.isInProgress {
        for r in requirements(s) where r.itemID != s.itemID { needed[r.itemID] = max(needed[r.itemID] ?? 0, r.level) }
    }
    func reason(_ s: UpgradeStep) -> PrioritizedStep.Reason {
        if s.category != .heroes, s.level <= needed[s.itemID] ?? 0 { return .unlocks }
        if s.itemID == clanCastleID || s.itemID == armyCampID { return .armyAndCastle }
        if s.element.level == 0, s.level == 1, s.category != .heroes { return .build }
        switch s.category {
        case .heroes: return .hero
        case .traps: return .trap
        case .defenses: if let p = advice.rank(of: s.itemID, in: .defenses) { return .keyDefense(position: p) }
        default: break
        }
        return .otherBuilding
    }
    let order = profile.orientation.rankOrder
    func rankIndex(_ r: PrioritizedStep.Reason) -> Int { r.rank.flatMap { order.firstIndex(of: $0) } ?? order.count }

    // Niveau atteint par type (le plus avancé des exemplaires ; une amélioration en cours compte comme faite).
    var reached: [Int: Int] = [:]
    for e in village.elements { reached[e.itemID] = max(reached[e.itemID] ?? 0, e.level + (e.upgrading ? 1 : 0)) }
    // E2 : demande placée et demande totale de la file, par ressource.
    var placed: [Resource: Int] = [:], total: [Resource: Int] = [:]
    for s in steps where !s.isInProgress { for c in s.costs { total[c.resource, default: 0] += c.amount * s.count } }
    func share(_ s: UpgradeStep) -> Double {
        s.costs.map { Double(placed[$0.resource] ?? 0) / Double(max(total[$0.resource] ?? 1, 1)) }.max() ?? 0
    }
    // Limite de héros : parmi les lancements possibles maintenant (ouvriers libres), pas plus de héros que la limite,
    // héros déjà en amélioration compris. Au-delà de ces lancements, c'est la simulation qui l'applique (S2).
    let busy = all.filter { $0.worker == .builder && $0.isInProgress && $0.remaining != 0 }
    var freeNow = max(0, (village.workers[.builder] ?? 0) - busy.reduce(0) { $0 + $1.count })
    var heroSlots = profile.heroLimit.map { max(0, $0 - busy.filter { $0.category == .heroes }.count) }

    var pending = chains(steps)
    var out: [PrioritizedStep] = []
    while !pending.isEmpty {
        var pool = pending.indices.filter { i in
            requirements(pending[i].steps[0]).allSatisfy { (reached[$0.itemID] ?? 0) >= $0.level }
        }
        if pool.isEmpty { pool = Array(pending.indices) }                            // prérequis jamais atteints
        if freeNow > 0, heroSlots == 0 {
            let others = pool.filter { pending[$0].steps[0].category != .heroes }
            if others.isEmpty { freeNow = 0 } else { pool = others }
        }
        let best = pool.min { a, b in
            let (x, y) = (pending[a].steps[0], pending[b].steps[0])
            let (px, py) = (profile.pinned.contains(x.itemID), profile.pinned.contains(y.itemID))
            if px != py { return px }                                                // E1
            let (rx, ry) = (reason(x), reason(y))
            if rankIndex(rx) != rankIndex(ry) { return rankIndex(rx) < rankIndex(ry) }
            if rx.within != ry.within { return rx.within < ry.within }
            let (sx, sy) = (share(x), share(y))
            if sx != sy { return sx < sy }                                           // E2
            if pending[a].left != pending[b].left { return pending[a].left > pending[b].left }   // E3
            return identity(x) < identity(y)                                         // E4
        }!
        let s = pending[best].steps.removeFirst()
        pending[best].left -= s.remaining ?? 0
        if pending[best].steps.isEmpty { pending.remove(at: best) }
        reached[s.itemID] = max(reached[s.itemID] ?? 0, s.level)
        for c in s.costs { placed[c.resource, default: 0] += c.amount * s.count }
        if freeNow > 0 {
            freeNow = max(0, freeNow - s.count)
            if s.category == .heroes { heroSlots = heroSlots.map { $0 - 1 } }
        }
        out.append(PrioritizedStep(step: s, reason: reason(s), pinned: profile.pinned.contains(s.itemID)))
    }
    return out
}
