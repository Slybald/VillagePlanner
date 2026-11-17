import Foundation

// Les améliorations restantes (PLAN §5.2) : tous les niveaux entre le niveau actuel et le maximum de l'HDV.
//
// Règles de ce fichier, reprises dans les noms de tests (RestantTests) :
//  Q1  un pas par niveau, de `niveau + 1` au maximum de l'HDV (de 1 pour un bâtiment à construire) ;
//  Q2  une amélioration en cours : le temps du minuteur, rien à payer ;
//  Q3  les réductions du profil, tant qu'elles ne sont pas finies à la date de départ ;
//  Q4  les sommes par catégorie et par ressource ;
//  Q5  le poste et les prérequis de chaque pas ;
//  Q6  une fusion pas encore faite ne double pas le compte de ses bâtiments d'origine (un exemplaire consommé
//      déjà en cours au-delà du plafond garde son pas « en cours » : le minuteur est réel) ;
//  Q7  rien hors avancement.

/// Un niveau à faire : coût, durée, poste, prérequis. Un pas décrit `count` exemplaires identiques ;
/// coût et durée sont ceux d'un exemplaire.
public struct UpgradeStep: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case todo
        /// En cours ; `ends` est nil quand le minuteur de l'export était illisible.
        case inProgress(ends: Date?)
    }

    public let itemID: Int
    public let category: Category
    public let worker: WorkerKind
    /// Le niveau que ce pas fait atteindre.
    public let level: Int
    public let count: Int
    public let status: Status
    /// Coût d'un exemplaire après réduction ; vide quand l'amélioration est en cours (déjà payée).
    public let costs: [ResourceAmount]
    /// Murs : l'autre ressource acceptée à la place de `costs`.
    public let alternativeResource: Resource?
    /// Durée d'un exemplaire après réduction, en secondes (la durée complète quand le pas est en cours).
    public let duration: Int
    /// Coût et durée de la référence, avant réduction (le plan les réduit à la date de chaque départ).
    public let baseCosts: [ResourceAmount]
    public let baseDuration: Int
    /// La réduction appliquée à `costs` et `duration`, en pourcentage.
    public let reductionPercent: Int
    /// Temps restant d'un exemplaire à la date du calcul : `duration` à faire, le minuteur en cours,
    /// nil quand le minuteur est illisible.
    public let remaining: Int?
    public let requires: [Requirement]
    /// Le groupe d'exemplaires d'où vient ce pas (dans un groupe scindé par Q6, la part concernée) :
    /// l'écran retrouve ainsi les pas d'un élément qu'il affiche.
    public let element: Element

    public var isInProgress: Bool { if case .inProgress = status { true } else { false } }
}

/// Coût et temps restants d'un ensemble de pas.
public struct RemainingTotals: Sendable, Equatable {
    /// Les six ressources, 0 quand rien n'est dû. Murs : la ressource principale de la référence.
    public var costs: [Resource: Int]
    /// Temps de travail restant, tous exemplaires additionnés (un exemplaire par ouvrier, ce n'est pas une date de fin).
    public var seconds: Int
    /// Exemplaires en cours dont la fin est inconnue : leur temps n'est pas dans `seconds`.
    public var unknownTimers: Int

    public init(costs: [Resource: Int] = Dictionary(uniqueKeysWithValues: Resource.allCases.map { ($0, 0) }),
                seconds: Int = 0, unknownTimers: Int = 0) {
        self.costs = costs
        self.seconds = seconds
        self.unknownTimers = unknownTimers
    }

    public init(_ steps: [UpgradeStep]) {
        self.init()
        for step in steps {
            for c in step.costs { costs[c.resource, default: 0] += c.amount * step.count }
            if let remaining = step.remaining { seconds += remaining * step.count } else { unknownTimers += step.count }
        }
    }
}

/// Les sommes de chaque catégorie (les huit, vides quand rien ne reste).
public func remainingTotals(by steps: [UpgradeStep]) -> [Category: RemainingTotals] {
    Dictionary(uniqueKeysWithValues: Category.allCases.map { category in
        (category, RemainingTotals(steps.filter { $0.category == category }))
    })
}

/// Les niveaux qui restent à chaque élément du village. `now` est la date du calcul : elle décide si une
/// réduction du profil court encore et ce qui reste de chaque minuteur.
public func remainingSteps(of village: Village, reference: ReferenceData, profile: Profile, now: Date) -> [UpgradeStep] {
    guard village.status != .unknownTownHall else { return [] }              // V7 : aucun plan
    var steps: [UpgradeStep] = []
    for (element, cap) in splitMergeConsumed(village, reference) {
        guard let item = reference.item(element.itemID), let category = item.category else { continue }   // Q7
        let percent = profile.reductionPercent(for: item.worker, at: now)
        func step(_ level: Int, _ status: UpgradeStep.Status) -> UpgradeStep {
            let ref = item.levels.first { $0.level == level }
            let baseCosts = ref?.costs ?? []                                  // niveau 1 d'une troupe : ni coût ni durée
            let baseDuration = ref?.duration ?? 0
            let todo = status == .todo
            let duration = todo ? Profile.reduced(baseDuration, byPercent: percent) : baseDuration
            let remaining: Int?
            switch status {
            case .todo: remaining = duration
            case .inProgress(let ends): remaining = ends.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) }
            }
            return UpgradeStep(itemID: item.id, category: category, worker: item.worker, level: level,
                               count: element.count, status: status,
                               costs: todo ? baseCosts.map { ResourceAmount(resource: $0.resource,
                                                                            amount: Profile.reduced($0.amount, byPercent: percent)) } : [],
                               alternativeResource: ref?.alternativeResource, duration: duration,
                               baseCosts: baseCosts, baseDuration: baseDuration,
                               reductionPercent: todo ? percent : 0, remaining: remaining,
                               requires: ref?.requires ?? [], element: element)
        }
        var next = element.level + 1
        if element.upgrading, next <= element.maxLevel {                      // Q2
            steps.append(step(next, .inProgress(ends: element.upgradeEnds)))
            next += 1
        }
        let last = min(element.maxLevel, cap ?? .max)                         // Q1, Q6
        if next <= last { steps += (next...last).map { step($0, .todo) } }    // Q3, Q5
    }
    return steps
}

/// Q6 : Village ajoute un bâtiment fusionné pas encore fait (niveau 0) sans retirer ses bâtiments d'origine.
/// Ceux-ci n'ont alors à monter que jusqu'au niveau que la fusion exige : au-delà, l'exemplaire sera consommé
/// et son niveau supérieur ferait double compte avec le niveau 1 du bâtiment fusionné. Les exemplaires
/// consommés sont les plus avancés. Le pas « en cours » d'un exemplaire consommé reste, même au-delà du plafond :
/// le minuteur est réel et occupe un ouvrier. Renvoie chaque élément (scindé si besoin) avec son plafond de niveau.
private func splitMergeConsumed(_ village: Village, _ reference: ReferenceData) -> [(Element, cap: Int?)] {
    // Un plafond par exemplaire consommé, par bâtiment d'origine.
    var caps: [Int: [Int]] = [:]
    for e in village.elements where e.level == 0 && !e.upgrading {
        guard let item = reference.item(e.itemID) else { continue }
        for r in item.mergedFrom { caps[r.itemID, default: []] += Array(repeating: r.level, count: e.count) }
    }
    var out: [(Element, cap: Int?)] = []
    var ids: [Int] = []
    for e in village.elements where !ids.contains(e.itemID) { ids.append(e.itemID) }
    for id in ids {
        var group = village.elements.filter { $0.itemID == id }
        guard var pending = caps[id]?.sorted(by: >), !pending.isEmpty else { out += group.map { ($0, nil) }; continue }
        // Les plus avancés d'abord ; à niveau égal, ceux qui ne s'améliorent pas.
        group.sort { $0.level != $1.level ? $0.level > $1.level : !$0.upgrading && $1.upgrading }
        for e in group {
            let taken = Array(pending.prefix(e.count))
            pending.removeFirst(taken.count)
            for cap in Set(taken).sorted() {
                out.append((e.with(count: taken.filter { $0 == cap }.count), cap))
            }
            if e.count > taken.count { out.append((e.with(count: e.count - taken.count), nil)) }
        }
    }
    return out
}

extension Element {
    fileprivate func with(count: Int) -> Element {
        Element(itemID: itemID, level: level, count: count, maxLevel: maxLevel, baseLevel: baseLevel,
                upgradeEnds: upgradeEnds, upgrading: upgrading)
    }
}
