import Foundation

// « Lancé » (T28, PLAN §1.3) : le joueur dit à l'app qu'une amélioration est partie, pour qu'elle reste juste sans nouvel
// export. L'action est gardée à part ; le village affiché est la photo plus les actions. Aucune horloge : la date de début
// est donnée par l'app.
//
// Règles de ce fichier, reprises dans les noms de tests (ActionsLocalesTests) :
//  L1  une action ne touche jamais la photo : elle est gardée dans `actions-locales.json`, à côté des photos, écrit en
//      entier et en une fois ; un fichier abîmé est mis de côté, jamais effacé ;
//  L2  appliquée, elle fait passer un exemplaire au repos du niveau visé − 1 « en cours », fin = début + durée du niveau,
//      réduite par le profil en vigueur au début ;
//  L3  l'export fait foi : une action qui commence avant la photo ne s'applique pas, et un import efface celles qui ne
//      sont pas postérieures à sa date ; une action postérieure (import d'un export plus ancien qu'elle) reste ;
//  L4  poste occupé : refusée si, à son début, tous les postes de son type travaillent (minuteurs de la photo et actions
//      déjà acceptées, dans l'ordre des débuts). Deux actions sur le même poste : la seconde est refusée, pas mise en file ;
//  L5  sans exemplaire au repos au niveau visé − 1 (disparu dans une fusion, déjà en cours, déjà monté), ou au-delà du
//      maximum de l'HDV : refusée ;
//  L6  la fin suit le profil courant : changer une réduction après coup la recalcule (le profil décrit le jeu) ;
//  L7  le ticket signale les écarts entre les actions qu'un import efface et ce que montre l'export, par type et niveau :
//      marquée lancée mais ni en cours ni atteinte ; lancée dans l'export sans avoir été marquée. Rien sans action effacée.

/// Une amélioration marquée « Lancé » : le type, le niveau visé, la date de début. Les exemplaires d'un groupe sont
/// identiques : le type et le niveau visé suffisent à désigner l'exemplaire.
public struct LocalAction: Codable, Sendable, Hashable, Identifiable {
    public let itemID: Int
    /// Le niveau que l'amélioration fait atteindre.
    public let level: Int
    public let start: Date

    public init(itemID: Int, level: Int, start: Date) {
        self.itemID = itemID
        self.level = level
        self.start = start
    }

    public var id: String { "\(itemID)-\(level)-\(Int(start.timeIntervalSince1970))" }

    /// Pour la clé du conseil (`CleConseil.make(actionsLocales:)`) : stable d'un lancement à l'autre (pas de `hashValue`).
    public var adviceKey: Int { Int(start.timeIntervalSince1970) &* 1_000_003 &+ itemID &* 1_000 &+ level }
}

/// Une action appliquée au village, avec sa fin.
public struct LocalLaunch: Sendable, Equatable {
    public let action: LocalAction
    public let ends: Date
}

public enum LocalActionRefusal: Sendable, Equatable {
    /// L3 : elle commence avant la photo, qui fait foi.
    case beforeSnapshot
    /// L5 : aucun exemplaire au repos au niveau visé − 1, ou niveau au-delà du maximum.
    case noIdleCopy
    /// L4 : tous les postes de ce type travaillent à son début.
    case postBusy
}

/// Le village affiché : la photo plus les actions locales acceptées.
public struct LocalActionsResult: Sendable {
    public let village: Village
    public let applied: [LocalLaunch]
    public let refused: [Refused]

    public struct Refused: Sendable, Equatable {
        public let action: LocalAction
        public let reason: LocalActionRefusal
    }

    /// L'action qui a produit ce pas « en cours » ; nil pour un minuteur lu dans la photo.
    public func launch(of step: UpgradeStep) -> LocalLaunch? {
        guard step.isInProgress else { return nil }
        return applied.first {
            $0.action.itemID == step.itemID && $0.action.level == step.level && $0.ends == step.element.upgradeEnds
        }
    }
}

public extension Village {
    /// La photo plus les actions (L2 à L6). Les actions sont examinées dans l'ordre de leurs débuts.
    func applying(_ actions: [LocalAction], reference: ReferenceData, profile: Profile) -> LocalActionsResult {
        var elements = self.elements
        var applied: [LocalLaunch] = []
        var refused: [LocalActionsResult.Refused] = []
        func refuse(_ a: LocalAction, _ r: LocalActionRefusal) { refused.append(.init(action: a, reason: r)) }

        let ordered = actions.sorted { ($0.start, $0.itemID, $0.level) < ($1.start, $1.itemID, $1.level) }
        for action in ordered {
            guard action.start >= date else { refuse(action, .beforeSnapshot); continue }               // L3
            guard let item = reference.item(action.itemID),
                  let index = elements.firstIndex(where: { $0.itemID == action.itemID && $0.level == action.level - 1
                                                           && !$0.upgrading }),
                  action.level <= elements[index].maxLevel else { refuse(action, .noIdleCopy); continue }   // L5
            // L4 : les postes de ce type qui travaillent encore au début de l'action.
            let busy = elements.filter { e in
                guard e.upgrading, reference.item(e.itemID)?.worker == item.worker else { return false }
                return ends(of: e, reference) > action.start
            }.reduce(0) { $0 + $1.count }
            guard busy < workers[item.worker] ?? 0 else { refuse(action, .postBusy); continue }

            // L2, L6 : la durée du niveau, réduite par le profil en vigueur au début.
            let base = item.levels.first { $0.level == action.level }?.duration ?? 0
            let percent = profile.reductionPercent(for: item.worker, at: action.start)
            let end = action.start.addingTimeInterval(TimeInterval(Profile.reduced(base, byPercent: percent)))
            let e = elements[index]
            let launched = Element(itemID: e.itemID, level: e.level, count: 1, maxLevel: e.maxLevel, baseLevel: e.baseLevel,
                                   upgradeEnds: end, upgrading: true)
            if e.count > 1 {
                elements[index] = Element(itemID: e.itemID, level: e.level, count: e.count - 1, maxLevel: e.maxLevel,
                                          baseLevel: e.baseLevel, upgradeEnds: nil, upgrading: false)
                elements.insert(launched, at: index + 1)
            } else {
                elements[index] = launched
            }
            applied.append(LocalLaunch(action: action, ends: end))
        }
        return LocalActionsResult(village: Village(self, elements: elements), applied: applied, refused: refused)
    }

    /// Fin d'un minuteur ; illisible, la plus tardive possible (photo + durée complète), comme la simulation.
    private func ends(of e: Element, _ reference: ReferenceData) -> Date {
        e.upgradeEnds ?? date.addingTimeInterval(TimeInterval(
            reference.item(e.itemID)?.levels.first { $0.level == e.level + 1 }?.duration ?? 0))
    }

    /// Le même village, d'autres éléments.
    private init(_ v: Village, elements: [Element]) {
        townHall = v.townHall
        date = v.date
        self.elements = elements
        workers = v.workers
        unknown = v.unknown
        status = v.status
        equipped = v.equipped
    }
}

// MARK: - L3 : ce qu'un import efface

public extension LocalAction {
    /// Partage les actions à l'import d'un export daté `date` : celles qu'il efface (pas postérieures), celles qui restent.
    static func split(_ actions: [LocalAction], importedAt date: Date) -> (erased: [LocalAction], kept: [LocalAction]) {
        (actions.filter { $0.start <= date }, actions.filter { $0.start > date })
    }
}

// MARK: - L7 : les écarts du ticket

/// Un écart entre ce qui avait été marqué et ce que montre l'export, pour `count` exemplaires d'un type à un niveau visé.
public struct LaunchGap: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Marquée lancée, mais l'export ne la montre ni en cours ni terminée.
        case markedNotRunning
        /// Lancée d'après l'export, sans avoir été marquée.
        case runningNotMarked
    }
    public let kind: Kind
    public let itemID: Int
    public let level: Int
    public let count: Int
}

/// L7. `erased` : les actions que l'import vient d'effacer ; `old` : la photo précédente ; `new` : celle importée.
/// Les écarts, rangés par type, niveau, puis sorte.
public func launchGaps(erased: [LocalAction], old: Village, new: Village) -> [LaunchGap] {
    guard !erased.isEmpty else { return [] }
    struct Key: Hashable, Comparable {
        let id: Int, level: Int
        static func < (a: Key, b: Key) -> Bool { (a.id, a.level) < (b.id, b.level) }
    }
    /// Exemplaires en cours vers chaque niveau, et exemplaires qui ont atteint ou visent chaque niveau.
    func counts(_ v: Village) -> (running: [Key: Int], reached: (Key) -> Int) {
        var running: [Key: Int] = [:]
        for e in v.elements where e.upgrading { running[Key(id: e.itemID, level: e.level + 1), default: 0] += e.count }
        return (running, { k in
            v.elements.filter { $0.itemID == k.id && ($0.level >= k.level || ($0.upgrading && $0.level + 1 == k.level)) }
                .reduce(0) { $0 + $1.count }
        })
    }
    let (a, b) = (counts(old), counts(new))
    var marked: [Key: Int] = [:]
    for action in erased { marked[Key(id: action.itemID, level: action.level), default: 0] += 1 }

    var gaps: [LaunchGap] = []
    for k in Set(marked.keys).union(b.running.keys).sorted() {
        let need = marked[k] ?? 0
        let missing = need - (b.reached(k) - a.reached(k))
        if missing > 0 { gaps.append(LaunchGap(kind: .markedNotRunning, itemID: k.id, level: k.level, count: min(missing, need))) }
        let unmarked = (b.running[k] ?? 0) - (a.running[k] ?? 0) - need
        if unmarked > 0 { gaps.append(LaunchGap(kind: .runningNotMarked, itemID: k.id, level: k.level, count: unmarked)) }
    }
    return gaps
}

// MARK: - L1 : le fichier

/// Les actions locales, dans `root/actions-locales.json` (la racine de `HistoryStore`, à côté des photos).
public struct LocalActionStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    static let format = 1
    var url: URL { root.appending(path: "actions-locales.json") }

    private struct Fichier: Codable {
        var format = LocalActionStore.format
        var actions: [LocalAction]
    }

    private enum Etat { case absent, lu([LocalAction]), abime, illisible }

    /// `illisible` : le fichier est là mais le système refuse de le lire (appareil verrouillé) : on n'y touche pas.
    private func lire() -> Etat {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url) else { return .illisible }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        guard let f = try? d.decode(Fichier.self, from: data), f.format == Self.format else { return .abime }
        return .lu(f.actions)
    }

    /// Les actions gardées ; vide si le fichier manque, est abîmé (mis de côté) ou illisible.
    public func load() -> [LocalAction] {
        switch lire() {
        case .lu(let actions): return actions
        case .abime: _ = mettreDeCote(); return []
        case .absent, .illisible: return []
        }
    }

    /// Remplace les actions gardées. Faux si le fichier ne s'écrit pas, ou s'il existe sans se laisser lire.
    @discardableResult
    public func save(_ actions: [LocalAction]) -> Bool {
        switch lire() {
        case .illisible: return false
        case .abime: guard mettreDeCote() else { return false }
        case .absent, .lu: break
        }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try e.encode(Fichier(actions: actions)).write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    /// L3 : efface les actions que l'import d'un export daté `date` rend caduques ; les rend.
    @discardableResult
    public func purge(importedAt date: Date) -> [LocalAction] {
        let (erased, kept) = LocalAction.split(load(), importedAt: date)
        if !erased.isEmpty { save(kept) }
        return erased
    }

    /// Un fichier abîmé garde son contenu sous `actions-locales-abime.json` (puis `-2`, `-3`…), sans horloge.
    private func mettreDeCote() -> Bool {
        var cible = root.appending(path: "actions-locales-abime.json")
        var n = 2
        while FileManager.default.fileExists(atPath: cible.path) { cible = root.appending(path: "actions-locales-abime-\(n).json"); n += 1 }
        return (try? FileManager.default.moveItem(at: url, to: cible)) != nil
    }
}
