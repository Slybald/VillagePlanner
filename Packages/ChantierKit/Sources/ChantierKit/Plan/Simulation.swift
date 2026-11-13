import Foundation

// La simulation et le cap (PLAN §5.4) : dérouler le temps et attribuer chaque amélioration à un poste,
// exemplaire par exemplaire, dans l'ordre des files de Priorites.swift.
//
// Règles de ce fichier, reprises dans les noms de tests (SimulationTests) :
//  S0  rien n'est lancé avant `now` ; un minuteur fini depuis la photo laisse son poste libre à `now` ;
//  S1  un poste occupé dans la photo le reste jusqu'à la fin de son minuteur, même au-delà d'une limite du profil ;
//  S2  à chaque événement (fin d'une amélioration, fin des heures sans jeu), chaque poste libre prend le premier pas
//      de sa file qui est lançable à cet instant : prérequis atteints, exemplaire libre, limite de héros respectée ;
//      un pas qui ne l'est pas garde sa place, et le poste prend le suivant ;
//  S3  un exemplaire, un niveau à la fois ; deux exemplaires du même type peuvent monter en même temps ;
//  S4  un lancement qui tomberait dans les heures sans jeu attend leur fin ;
//  S5  les réductions du profil s'appliquent aux pas lancés avant leur date de fin ;
//  S6  assistants (Assistants.swift) : ils raccourcissent des pas déjà lancés, leurs services sont appliqués
//      aux événements ; `finish(_:start:seconds:)` reste la fin « sans assistant » ;
//  S7  la simulation s'arrête quand plus rien ne tourne ; ce qui n'a jamais été lancé sort dans `blocked` ;
//  O7  (Occupation.swift) « à ton rythme » : un couloir qui vient de finir une amélioration reste indisponible
//      `(1 − ρ) / ρ` fois la durée de cette amélioration (sa durée complète pour un minuteur de la photo), puis
//      relance : le poste travaille alors une part `ρ` du temps entre deux lancements. Le pas est choisi quand le
//      couloir redevient disponible (priorités et prérequis de ce moment-là), jamais pendant les heures sans jeu (S4) ;
//      un minuteur de la photo déjà fini à `now` n'attend rien (S0) ; la dernière attente ne retarde pas le cap ;
//      sans rythme, rien de tout cela n'existe.
// Décisions :
//  - minuteur illisible (fin inconnue) : le poste est tenu occupé jusqu'à `photo + durée complète du niveau`,
//    la fin la plus tardive possible ; `Plan.unknownTimers` les compte ;
//  - un poste qui se construit pendant le plan (cabane, Maison des familiers) compte dès son niveau 1 ;
//  - la forge (équipements) n'a pas de durée : elle n'est pas simulée, comme les murs (P6).

/// Une amélioration datée, pour un exemplaire.
public struct ScheduledStep: Sendable, Equatable {
    /// Le pas (un niveau d'un groupe d'exemplaires) ; `copy` dit lequel des exemplaires du groupe.
    public let step: UpgradeStep
    public let copy: Int
    /// Le couloir : numéro de l'ouvrier (ou du labo, de la Maison des familiers) dans son poste, à partir de 0.
    public let lane: Int
    /// Lancement ; pour un minuteur de la photo, la date de la photo (le vrai départ n'est pas connu).
    public let start: Date
    /// Fin ; un assistant (S6) la rapproche après le lancement.
    public internal(set) var end: Date
    /// Coût d'un exemplaire, réduction de la date de lancement comprise ; vide pour un minuteur de la photo.
    public let costs: [ResourceAmount]
    public let reductionPercent: Int
    /// Déjà en cours dans la photo (S1).
    public let fromSnapshot: Bool
    /// La règle qui place ce pas dans sa file ; nil pour un minuteur de la photo.
    public let reason: PrioritizedStep.Reason?

    public var worker: WorkerKind { step.worker }
}

/// Une amélioration jamais lancée (S7), avec sa raison.
public struct BlockedStep: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// Le niveau précédent du même exemplaire n'a jamais été lancé.
        case previousLevel
        /// Aucun poste de ce type dans le village.
        case noWorker
        /// Ce prérequis n'est jamais atteint.
        case requirement(Requirement)
        /// La limite de héros du profil est à zéro.
        case heroLimit
    }
    public let step: UpgradeStep
    public let copy: Int
    public let reason: Reason
}

/// Le plan : améliorations datées, fin de chaque poste, cap, améliorations bloquées avec leur raison (S7).
/// Les ressources à réunir arrivent avec T14.
public struct Plan: Sendable, Equatable {
    public let now: Date
    /// Les minuteurs de la photo, puis les lancements dans l'ordre du temps.
    public let steps: [ScheduledStep]
    /// Fin de la dernière amélioration de chaque poste qui a encore quelque chose à faire après `now`.
    public let workerEnds: [WorkerKind: Date]
    /// Le poste qui finit en dernier ; nil quand rien ne reste.
    public let lastWorker: WorkerKind?
    /// Fin de la dernière amélioration à durée, tous postes confondus, hors murs et équipements ; nil quand rien ne
    /// reste après `now` (tous les minuteurs de la photo sont finis et rien n'est à lancer).
    public let cap: Date?
    public let blocked: [BlockedStep]
    /// La limite de héros a joué : à un moment, elle a retenu un héros prêt alors qu'un ouvrier était libre. L'écran
    /// dit alors « avec ton profil », sinon « au plus tôt ».
    public let heroLimitApplied: Bool
    /// Potions actives dans la photo (clés de `boosts`) : les fins réelles sont plus proches que les minuteurs.
    public let activeBoosts: [String]
    /// Minuteurs illisibles de la photo, tenus jusqu'à leur fin la plus tardive possible.
    public let unknownTimers: Int
    /// Les services des assistants (S6), dans l'ordre du temps.
    public let helperServices: [HelperService]

    public var potionActive: Bool { !activeBoosts.isEmpty }

    public init(now: Date, steps: [ScheduledStep] = [], workerEnds: [WorkerKind: Date] = [:], lastWorker: WorkerKind? = nil,
                cap: Date? = nil, blocked: [BlockedStep] = [], heroLimitApplied: Bool = false,
                activeBoosts: [String] = [], unknownTimers: Int = 0, helperServices: [HelperService] = []) {
        self.now = now
        self.steps = steps
        self.workerEnds = workerEnds
        self.lastWorker = lastWorker
        self.cap = cap
        self.blocked = blocked
        self.heroLimitApplied = heroLimitApplied
        self.activeBoosts = activeBoosts
        self.unknownTimers = unknownTimers
        self.helperServices = helperServices
    }
}

/// Clés de `boosts` qui accélèrent le village principal (les `clocktower_*` sont la base des ouvriers).
let potionKeys = ["builder_boost", "builder_consumable", "lab_boost", "lab_consumable", "pet_boost"]

/// Hypothèse à confirmer en jeu (le PLAN n'en dit rien) : le labo et la Maison des familiers travaillent pendant
/// leur propre amélioration. À `false`, un poste en amélioration ne compte plus dans sa capacité.
let postsWorkWhileUpgrading = true

/// Postes simulés, dans l'ordre où ils sont examinés à chaque événement.
private let simulatedWorkers: [WorkerKind] = [.builder, .laboratory, .petHouse]

/// Un poste « presque jamais occupé » ferait des attentes sans fin : le taux n'est jamais pris sous ce plancher.
private let minimumRate = 0.05

/// La fin d'un pas lancé à `start` pour `seconds` secondes, sans assistant. S6 : un assistant n'est affecté qu'à un
/// pas déjà en cours (le plus long du poste à l'instant où il est libre) ; Assistants.swift rapproche donc la fin
/// après coup, pas ici.
func finish(_ step: UpgradeStep, start: Date, seconds: Int) -> Date {
    start.addingTimeInterval(TimeInterval(seconds))
}

/// `now` est toujours un paramètre : aucun calcul ne lit l'horloge. `boosts` : ceux de l'export, pour dire si une
/// potion était active dans la photo. `assistants` : ceux de l'export (`Assistants(export:reference:)`) ; sans eux,
/// le plan ne change pas (S6). `rhythm` : le taux d'occupation mesuré (O7) ; nil, le plan « au plus tôt » de toujours.
public func makePlan(for village: Village, reference: ReferenceData, advice: AdviceData,
                     profile: Profile, now: Date, boosts: [String: Int] = [:],
                     assistants: Assistants = Assistants(), rhythm: Rhythm? = nil) -> Plan {
    let all = remainingSteps(of: village, reference: reference, profile: profile, now: now)
    let queues = priorities(of: all, in: village, reference: reference, advice: advice, profile: profile)
    var sim = Simulation(village: village, reference: reference, profile: profile, assistants: assistants, rhythm: rhythm)
    // Les minuteurs dans un ordre qui ne dépend pas de celui de l'export (couloirs reproductibles).
    func key(_ s: UpgradeStep) -> (Double, Int, Int, Int) {
        guard case .inProgress(let ends) = s.status else { return (0, 0, 0, 0) }
        return (ends?.timeIntervalSince1970 ?? .infinity, s.itemID, s.level, s.count)
    }
    sim.start(all.filter { $0.isInProgress && simulatedWorkers.contains($0.worker) }.sorted { key($0) < key($1) })
    for worker in simulatedWorkers { sim.enqueue(queues[worker] ?? [], for: worker) }
    sim.run(from: now)
    return sim.plan(now: now, activeBoosts: potionKeys.filter { (boosts[$0] ?? 0) > 0 })
}

// MARK: - Moteur

struct Simulation {
    /// Un exemplaire : son groupe (indice dans `groups`) et son rang dans le groupe.
    struct Copy: Hashable { let group: Int; let index: Int }
    /// `copy` : numéro de l'exemplaire dans `done` et `busy` (des tableaux : la boucle les lit à chaque événement).
    struct Job { let step: UpgradeStep; let copy: Int; let index: Int; let reason: PrioritizedStep.Reason? }
    /// `slot` : sa place dans `scheduled`, pour que S6 y reporte une fin rapprochée.
    struct Running { let job: Job; let lane: Int; var end: Date; let slot: Int }

    let reference: ReferenceData
    let profile: Profile
    let photo: Date
    var groups: [Element] = []
    var copies: [Copy: Int] = [:]
    /// Niveau terminé de chaque exemplaire qui a des pas, et s'il est en cours.
    var done: [Int] = []
    var busy: [Bool] = []
    /// Exemplaires de chaque type par niveau terminé, tout le village compris (prérequis, postes).
    var levels: [Int: [Int: Int]] = [:]
    var queues: [WorkerKind: [Job]] = [:]
    var running: [Running] = []
    var lanes: [WorkerKind: [Bool]] = [:]                 // couloir occupé
    var scheduled: [ScheduledStep] = []
    var heroLimitApplied = false
    var unknownTimers = 0
    /// S6 : les assistants (un par type, au plus), leurs affectations lues dans la photo, leurs services.
    var crew: [HelperRuntime] = []
    var photoAssignments: [Assistants.Assignment] = []
    var helperServices: [HelperService] = []
    /// Places (dans `scheduled`) des minuteurs illisibles : leur fin est inventée, un assistant ne la raccourcit pas.
    var unknownSlots: Set<Int> = []
    /// O7 : `(1 − ρ) / ρ` par poste (absent : pas d'attente), la date avant laquelle un couloir libre ne relance pas,
    /// et la date du calcul.
    var pauseFactor: [WorkerKind: Double] = [:]
    var laneFree: [WorkerKind: [Int: Date]] = [:]
    var now = Date.distantPast

    init(village: Village, reference: ReferenceData, profile: Profile, assistants: Assistants = Assistants(),
         rhythm: Rhythm? = nil) {
        self.reference = reference
        if let rhythm {
            for worker in simulatedWorkers {
                let rho = min(max(rhythm.rate(for: worker), minimumRate), 1)
                if rho < 1 { pauseFactor[worker] = (1 - rho) / rho }
            }
        }
        self.profile = profile
        photo = village.date
        crew = HelperRuntime.crew(assistants, reference: reference, photo: village.date)
        photoAssignments = assistants.assignments
        for e in village.elements { levels[e.itemID, default: [:]][e.level, default: 0] += e.count }
    }

    mutating func group(_ e: Element) -> Int {
        if let i = groups.firstIndex(of: e) { return i }
        groups.append(e)
        return groups.count - 1
    }

    /// Un pas de `count` exemplaires devient `count` travaux. Deux groupes identiques partagent un `Element` :
    /// leurs exemplaires sont numérotés à la suite.
    mutating func jobs(_ step: UpgradeStep, _ reason: PrioritizedStep.Reason?, _ seen: inout [Copy: Int]) -> [Job] {
        let g = group(step.element)
        let key = Copy(group: g, index: step.level)
        let offset = seen[key, default: 0] * step.count
        seen[key, default: 0] += 1
        return (0..<step.count).map { k in
            let copy = Copy(group: g, index: offset + k)
            let id = copies[copy] ?? {
                copies[copy] = done.count
                done.append(step.element.level)
                busy.append(false)
                return done.count - 1
            }()
            return Job(step: step, copy: id, index: offset + k, reason: reason)
        }
    }

    /// S1 : les minuteurs de la photo occupent leur poste jusqu'à leur fin.
    mutating func start(_ inProgress: [UpgradeStep]) {
        var seen: [Copy: Int] = [:]
        for step in inProgress {
            for job in jobs(step, nil, &seen) {
                let end: Date
                if case .inProgress(let ends?) = step.status { end = ends } else {
                    end = photo.addingTimeInterval(TimeInterval(step.duration))      // minuteur illisible
                    unknownTimers += 1
                    unknownSlots.insert(scheduled.count)                         // S6 n'y touche pas
                }
                launch(job, at: photo, end: end, costs: [], percent: 0)
                if case .inProgress(let ends) = step.status { assistPhoto(step, ends: ends, running: running.count - 1) }
            }
        }
    }

    mutating func enqueue(_ queue: [PrioritizedStep], for worker: WorkerKind) {
        var seen: [Copy: Int] = [:]
        queues[worker] = queue.flatMap { jobs($0.step, $0.reason, &seen) }
    }

    func reached(_ id: Int) -> Int { levels[id]?.reduce(0) { $1.value > 0 ? max($0, $1.key) : $0 } ?? 0 }
    func count(_ id: Int, atLeast level: Int) -> Int { levels[id]?.reduce(0) { $0 + ($1.key >= level ? $1.value : 0) } ?? 0 }

    /// Postes de ce type existants : bâtiments au niveau 1 au moins (un poste construit pendant le plan compte).
    func capacity(_ worker: WorkerKind) -> Int {
        let posts = Village.posts.filter { $0.kind == worker }
        let upgrading = postsWorkWhileUpgrading || worker == .builder ? 0
            : running.filter { r in posts.contains { $0.id == r.job.step.itemID } }.count
        return posts.reduce(0) { $0 + count($1.id, atLeast: 1) } - upgrading
    }

    /// Bâtiments d'origine d'une fusion, regroupés : (type, niveau) → nombre d'exemplaires exigés.
    func merged(_ step: UpgradeStep) -> [(Requirement, Int)] {
        guard step.level == 1, let from = reference.item(step.itemID)?.mergedFrom, !from.isEmpty else { return [] }
        var out: [(Requirement, Int)] = []
        for r in from {
            if let i = out.firstIndex(where: { $0.0 == r }) { out[i].1 += 1 } else { out.append((r, 1)) }
        }
        return out
    }

    func unmet(_ step: UpgradeStep) -> Requirement? {
        step.requires.first { reached($0.itemID) < $0.level }
            ?? merged(step).first { count($0.0.itemID, atLeast: $0.0.level) < $0.1 }?.0
    }

    /// S2, S3 : lançable à cet instant, limite de héros mise à part.
    var heroesRunning: Int { running.filter { $0.job.step.category == .heroes }.count }

    func ready(_ job: Job) -> Bool {
        done[job.copy] == job.step.level - 1 && !busy[job.copy] && unmet(job.step) == nil
    }

    mutating func launch(_ job: Job, at start: Date, end: Date, costs: [ResourceAmount], percent: Int, lane wanted: Int? = nil) {
        let worker = job.step.worker
        var taken = lanes[worker, default: []]
        let lane = wanted ?? taken.firstIndex(of: false) ?? { taken.append(false); return taken.count - 1 }()
        if lane == taken.count { taken.append(false) }
        taken[lane] = true
        lanes[worker] = taken
        running.append(Running(job: job, lane: lane, end: end, slot: scheduled.count))
        busy[job.copy] = true
        // Un bâtiment fusionné consomme ses bâtiments d'origine dès son lancement, les plus avancés d'abord
        // (la photo a déjà retiré ceux d'une fusion en cours).
        if job.reason != nil {
            for (req, n) in merged(job.step) {
                var left = n
                for l in (levels[req.itemID] ?? [:]).keys.sorted(by: >) where l >= req.level && left > 0 {
                    let take = min(left, levels[req.itemID]![l]!)
                    levels[req.itemID]![l]! -= take
                    left -= take
                }
            }
        }
        scheduled.append(ScheduledStep(step: job.step, copy: job.index, lane: lane, start: start, end: end,
                                       costs: costs, reductionPercent: percent, fromSnapshot: job.reason == nil,
                                       reason: job.reason))
    }

    mutating func complete(_ r: Running) {
        lanes[r.job.step.worker]?[r.lane] = false
        let id = r.job.step.itemID, level = r.job.step.level
        done[r.job.copy] = level
        busy[r.job.copy] = false
        // O7 : le couloir attend avant de relancer, proportionnellement à la durée complète de ce qu'il vient de faire ;
        // un minuteur de la photo fini avant `now` n'attend rien : son poste est déjà libre (S0).
        if let factor = pauseFactor[r.job.step.worker] {
            let s = scheduled[r.slot]
            if s.end > now {
                let full = s.fromSnapshot ? r.job.step.baseDuration : Int(s.end.timeIntervalSince(s.start).rounded())
                laneFree[r.job.step.worker, default: [:]][r.lane] = r.end.addingTimeInterval(Double(full) * factor)
            }
        }
        levels[id, default: [:]][level - 1, default: 0] -= 1
        levels[id, default: [:]][level, default: 0] += 1
    }

    /// Le déroulé : S0 (départ à `now`), S2 à chaque événement, S4, S7 (arrêt quand plus rien ne tourne).
    /// Chaque événement termine au moins un pas : la boucle finit toujours.
    mutating func run(from now: Date) {
        self.now = now
        func release(_ d: Date) -> Date { profile.quietHours?.release(d) ?? d }
        var t = release(now)                                                  // S0, S4
        while true {
            var again = true
            while again {                                                     // pas de durée nulle : même instant
                for r in running where r.end <= t { complete(r) }
                running.removeAll { $0.end <= t }
                noteHeroLimit()
                for worker in simulatedWorkers { assign(worker, at: t) }
                again = running.contains { $0.end <= t }
            }
            bindHelpers(at: t)                                                // S6
            let wakes = (crew.isEmpty ? [] : helperWakes(after: t)) + pauseEnds(after: t)
            guard let next = (running.map(\.end) + wakes).min() else { break }   // S7
            t = release(max(next, t))
        }
    }

    /// La limite joue quand, à cet instant, plus de héros sont prêts qu'elle n'en laisse partir et qu'un ouvrier libre
    /// aurait pu en prendre un de plus. Un héros qui n'attend qu'un ouvrier ne compte pas.
    mutating func noteHeroLimit() {
        guard !heroLimitApplied, let limit = profile.heroLimit else { return }
        let slots = max(0, limit - heroesRunning)
        let free = capacity(.builder) - running.filter { $0.job.step.worker == .builder }.count
        let ready = queues[.builder]?.filter { $0.step.category == .heroes && self.ready($0) }.count ?? 0
        if ready > slots, free > slots { heroLimitApplied = true }
    }

    /// O7 : les dates où un couloir libre redevient disponible, pour un poste dont la file n'est pas vide : un événement.
    func pauseEnds(after t: Date) -> [Date] {
        laneFree.flatMap { worker, dates in
            (queues[worker]?.isEmpty ?? true) ? [] : dates.filter { !(lanes[worker]?[$0.key] ?? false) }.values.filter { $0 > t }
        }
    }

    /// O7 : le couloir libre et disponible à `t` (le plus bas), nil quand tous les couloirs libres attendent encore.
    func availableLane(_ worker: WorkerKind, at t: Date) -> Int? {
        let taken = lanes[worker, default: []]
        let free = taken.indices.filter { !taken[$0] } + (taken.count < capacity(worker) ? [taken.count] : [])
        return free.first { (laneFree[worker]?[$0] ?? .distantPast) <= t }
    }

    /// S2 : tant que le poste a un couloir libre, il prend le premier pas lançable de sa file.
    mutating func assign(_ worker: WorkerKind, at t: Date) {
        while running.filter({ $0.job.step.worker == worker }).count < capacity(worker) {
            var lane: Int?
            if !laneFree.isEmpty {                                            // O7 : le couloir attend encore
                guard let free = availableLane(worker, at: t) else { return }
                lane = free
            }
            let heroes = heroesRunning
            guard let i = queues[worker]?.firstIndex(where: { job in
                ready(job) && (job.step.category != .heroes || heroes < profile.heroLimit ?? .max)
            }) else { return }
            let job = queues[worker]!.remove(at: i)
            if let lane { laneFree[worker]?[lane] = nil }
            let percent = profile.reductionPercent(for: worker, at: t)        // S5
            let seconds = Profile.reduced(job.step.baseDuration, byPercent: percent)
            let costs = job.step.baseCosts.map {
                ResourceAmount(resource: $0.resource, amount: Profile.reduced($0.amount, byPercent: percent))
            }
            launch(job, at: t, end: finish(job.step, start: t, seconds: seconds), costs: costs, percent: percent, lane: lane)
        }
    }

    func plan(now: Date, activeBoosts: [String]) -> Plan {
        // Un minuteur fini avant `now` n'est plus « à venir » : quand rien d'autre ne reste, pas de cap (tout est fait).
        var ends: [WorkerKind: Date] = [:]
        for s in scheduled where !s.fromSnapshot || s.end > now { ends[s.worker] = max(ends[s.worker] ?? s.end, s.end) }
        let last = simulatedWorkers.filter { ends[$0] != nil }.max { ends[$0]! < ends[$1]! }   // à égalité : le premier
        let blocked = simulatedWorkers.flatMap { worker in
            (queues[worker] ?? []).map { job -> BlockedStep in
                let reason: BlockedStep.Reason
                if capacity(worker) == 0 { reason = .noWorker }
                else if done[job.copy] < job.step.level - 1 { reason = .previousLevel }
                else if let r = unmet(job.step) { reason = .requirement(r) }
                else { reason = .heroLimit }
                return BlockedStep(step: job.step, copy: job.index, reason: reason)
            }
        }
        return Plan(now: now, steps: scheduled, workerEnds: ends, lastWorker: last, cap: last.flatMap { ends[$0] },
                    blocked: blocked, heroLimitApplied: heroLimitApplied, activeBoosts: activeBoosts,
                    unknownTimers: unknownTimers, helperServices: helperServices)
    }
}
