import Foundation

// Le taux d'occupation (PLAN §1.3, §5.4) : entre deux photos, le temps où chaque poste a travaillé et celui où il
// n'a rien fait, puis le rythme des 30 derniers jours que la simulation applique pour la date « à ton rythme ».
//
// Règles de ce fichier, reprises dans les noms de tests (OccupationTests) :
//  O1  par poste (ouvriers, labo, Maison des familiers), temps occupé et temps libre entre deux photos : les fins de
//      minuteur de la première photo, les débuts déduits de la seconde (fin − durée complète du niveau) ;
//  O2  une réduction qui a pu jouer (profil S5, assistant S6, potion) rend la durée incertaine : le résultat est un
//      intervalle, et l'écran dit « environ » ;
//  O3  une amélioration lancée puis finie entre les deux photos ne laisse aucune trace de minuteur : chaque niveau
//      gagné sans minuteur visible compte pour sa durée dans la référence (intervalle, O2) ;
//  O4  heures sans jeu (S4) : elles sortent du calcul, occupé comme libre. La simulation les gère déjà (un lancement
//      attend leur fin) : les compter ici aussi les ferait payer deux fois ;
//  O5  deux photos données à l'envers sont comparées dans l'ordre du temps ;
//  O6  le rythme : les photos des 30 jours qui précèdent la plus récente ; rien avant trois photos couvrant au moins
//      sept jours ;
//  O7  dans la simulation, un poste à `ρ` d'occupation attend `(1 − ρ) / ρ` fois la durée d'une amélioration avant de
//      lancer la suivante ; sans rythme, rien ne change (voir Simulation.swift).
//
// MÉTHODE (aussi dans la PR). Fenêtre = de la photo A à la photo B. Pour un poste de `n` ouvriers, le temps disponible
// est `n × (fenêtre − heures sans jeu)`. Le temps occupé est la somme de :
//  - les minuteurs de A qui ne sont plus en cours dans B : occupés de A jusqu'à leur fin ;
//  - les minuteurs de B qui n'étaient pas dans A : occupés depuis leur début déduit jusqu'à B ;
//  - les minuteurs présents dans A et dans B (même type, même niveau visé) : occupés toute la fenêtre ;
//  - les niveaux gagnés sans minuteur visible (O3) : leur durée, placée n'importe où (répartie sur la fenêtre).
// Deux bornes pour chaque durée : la durée de la référence (borne haute du temps occupé) et cette durée moins ce que
// la réduction qui a pu jouer aurait fait gagner (borne basse).
//
// LIMITES. Un minuteur est un seul poste occupé ; on ne sait pas lequel, on additionne des durées. Les réductions
// connues sont celles du profil d'aujourd'hui, les potions et les assistants vus dans A ou B : une potion finie entre
// les photos, un événement passé qui n'est plus dans le profil ne se voient pas. Une amélioration annulée, un minuteur
// illisible (fin inconnue) et un poste construit entre les photos faussent le chiffre ; le premier et le deuxième
// élargissent l'intervalle, le troisième n'est pas compté (les postes sont ceux de la première photo). Les temps de
// jeu où le joueur n'a pas pu lancer pour manque de ressources comptent comme du temps libre.

/// Un poste entre deux photos.
public struct PostOccupation: Sendable, Equatable {
    public let worker: WorkerKind
    /// Nombre d'ouvriers du poste dans la première photo.
    public let workers: Int
    /// `workers × (fenêtre − heures sans jeu)`, en secondes.
    public let available: Int
    /// Temps occupé, borne basse et borne haute (O2), en secondes.
    public let busy: ClosedRange<Int>
    /// Niveaux gagnés sans minuteur visible (O3).
    public let invisibleLevels: Int

    /// Temps libre, en secondes.
    public var free: ClosedRange<Int> { (available - busy.upperBound)...(available - busy.lowerBound) }
    /// Part du temps occupée, de 0 à 1.
    public var rate: ClosedRange<Double> {
        guard available > 0 else { return 0...0 }
        return Double(busy.lowerBound) / Double(available)...Double(busy.upperBound) / Double(available)
    }
    /// Le chiffre à afficher (au milieu de l'intervalle).
    public var midRate: Double { (rate.lowerBound + rate.upperBound) / 2 }
    /// Le chiffre est un intervalle : l'écran écrit « environ ».
    public var isApproximate: Bool { busy.lowerBound != busy.upperBound }
}

/// Ce qu'on sait de l'occupation des postes entre deux photos.
public struct Occupation: Sendable, Equatable {
    public let from: Date
    public let to: Date
    /// La fenêtre moins les heures sans jeu, en secondes.
    public let awake: Int
    /// Les postes qui existent dans la première photo, dans l'ordre : ouvriers, labo, Maison des familiers.
    public let posts: [PostOccupation]

    public func post(_ worker: WorkerKind) -> PostOccupation? { posts.first { $0.worker == worker } }

    /// nil quand les deux photos ont la même date, quand l'HDV de l'une est inconnu (V7), ou quand la fenêtre ne
    /// contient que des heures sans jeu. Le profil donne les réductions (S5) et les heures sans jeu (S4).
    public init?(between a: VillageExport, and b: VillageExport, reference: ReferenceData, profile: Profile) {
        let (x, y) = a.date <= b.date ? (a, b) : (b, a)                                     // O5
        guard x.date < y.date else { return nil }
        let (before, after) = (Village(export: x, reference: reference), Village(export: y, reference: reference))
        guard before.status != .unknownTownHall, after.status != .unknownTownHall else { return nil }
        let clock = AwakeClock(profile.quietHours, from: x.date, to: y.date)
        guard clock.total > 0 else { return nil }
        from = x.date
        to = y.date
        awake = Int(clock.total.rounded())
        posts = Self.kinds.compactMap { kind in
            guard let n = before.workers[kind], n > 0 else { return nil }
            var estimate = Estimate(kind: kind, x: x, y: y, before: before, after: after, reference: reference,
                                    profile: profile, clock: clock)
            return estimate.run(workers: n)
        }
    }

    static let kinds: [WorkerKind] = [.builder, .laboratory, .petHouse]
}

// MARK: - Le calcul

/// Le temps hors heures sans jeu : `awake(t)` compte les secondes de `[début, t]` qui n'y tombent pas.
struct AwakeClock {
    let start: Date
    let end: Date
    private let quiet: [(Date, Date)]

    var total: Double { awake(end) }

    init(_ hours: QuietHours?, from start: Date, to end: Date) {
        self.start = start
        self.end = end
        var out: [(Date, Date)] = []
        if let h = hours, (h.start % 24 + 24) % 24 != (h.end % 24 + 24) % 24 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = h.timeZone
            let (s, e) = ((h.start % 24 + 24) % 24, (h.end % 24 + 24) % 24)
            var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: start)) ?? start
            let last = calendar.startOfDay(for: end)
            while day <= last {
                let next = calendar.date(byAdding: .day, value: 1, to: day) ?? last.addingTimeInterval(86_400)
                if let a = calendar.date(bySettingHour: s, minute: 0, second: 0, of: day),
                   let b = calendar.date(bySettingHour: e, minute: 0, second: 0, of: s < e ? day : next) {
                    let (lo, hi) = (max(a, start), min(b, end))
                    if lo < hi { out.append((lo, hi)) }
                }
                day = next
            }
        }
        quiet = out
    }

    func awake(_ date: Date) -> Double {
        let t = min(max(date, start), end)
        return t.timeIntervalSince(start) - quiet.reduce(0) { $0 + max(0, min($1.1, t).timeIntervalSince(max($1.0, start)) ) }
    }
}

/// Un minuteur lu dans une photo : ce qu'il améliore, jusqu'où, et sa fin (nil : minuteur illisible).
private struct Minuteur { let itemID: Int; let target: Int; let end: Date? }

private struct Estimate {
    let kind: WorkerKind
    let x: VillageExport, y: VillageExport
    let before: Village, after: Village
    let reference: ReferenceData
    let profile: Profile
    let clock: AwakeClock

    var low = 0.0, high = 0.0
    var invisible = 0

    init(kind: WorkerKind, x: VillageExport, y: VillageExport, before: Village, after: Village,
         reference: ReferenceData, profile: Profile, clock: AwakeClock) {
        self.kind = kind; self.x = x; self.y = y; self.before = before; self.after = after
        self.reference = reference; self.profile = profile; self.clock = clock
    }

    // MARK: Ce qui peut raccourcir une amélioration (O2)

    /// Clés de `boosts` d'une potion qui accélère ce poste.
    private var potionKeys: [String] {
        switch kind {
        case .builder: ["builder_boost", "builder_consumable"]
        case .laboratory: ["lab_boost", "lab_consumable"]
        case .petHouse: ["pet_boost"]
        case .blacksmith: []
        }
    }
    private func potion(in e: VillageExport) -> Bool { potionKeys.contains { (e.boosts[$0] ?? 0) > 0 } }

    /// Hypothèse à confirmer en jeu : une potion (dix fois le rythme pendant une heure) fait gagner au plus neuf
    /// heures sur une amélioration.
    static let potionSaving = 9 * 3600

    /// Ce que l'assistant du poste fait gagner au plus par service (H1 d'Assistants.swift), 0 sans assistant.
    private func helperPerService(_ e: VillageExport) -> Int {
        let crew = HelperRuntime.crew(Assistants(export: e, reference: reference), reference: reference, photo: e.date)
        guard let h = crew.first(where: { $0.post == kind }) else { return 0 }
        return h.service * helperExtraSpeed(multiplier: h.multiplier)
    }

    /// Le plus qu'une amélioration de `duration` secondes ait pu gagner, bornée par sa durée.
    private func saving(duration: Int, profilePercent: Int, helper: Int, potion: Bool) -> Int {
        let services = duration / helperWorkday + 1
        let total = duration * profilePercent / 100 + (helper > 0 ? min(duration, services * helper) : 0)
            + (potion ? min(duration, Self.potionSaving) : 0)
        return min(duration, total)
    }

    private func duration(_ itemID: Int, level: Int) -> Int? {
        reference.item(itemID)?.levels.first { $0.level == level }?.duration
    }

    private func counts(_ item: ReferenceItem?) -> Bool {
        guard let item, let category = item.category, category != .walls else { return false }    // P6 : pas de durée
        return item.worker == kind
    }

    // MARK: Les minuteurs

    private func timers(_ village: Village) -> [Minuteur] {
        village.elements.filter { $0.upgrading && counts(reference.item($0.itemID)) }.flatMap { e in
            Array(repeating: Minuteur(itemID: e.itemID, target: e.level + 1, end: e.upgradeEnds), count: e.count)
        }
    }

    /// Les paires (minuteur de A, minuteur de B) qui sont la même amélioration : même type, même niveau visé, les
    /// fins les plus proches d'abord (une amélioration qui continue garde sa fin d'une photo à l'autre).
    private func matches(_ a: [Minuteur], _ b: [Minuteur]) -> [(Int, Int)] {
        var pairs: [(Int, Int, Double)] = []
        for i in a.indices {
            for j in b.indices where a[i].itemID == b[j].itemID && a[i].target == b[j].target {
                let gap = a[i].end.flatMap { e in b[j].end.map { abs(e.timeIntervalSince($0)) } } ?? 0
                pairs.append((i, j, gap))
            }
        }
        var usedA = Set<Int>(), usedB = Set<Int>(), out: [(Int, Int)] = []
        for p in pairs.sorted(by: { ($0.2, $0.0, $0.1) < ($1.2, $1.0, $1.1) }) where !usedA.contains(p.0) && !usedB.contains(p.1) {
            usedA.insert(p.0); usedB.insert(p.1); out.append((p.0, p.1))
        }
        return out
    }

    mutating func run(workers n: Int) -> PostOccupation {
        let (t0, t1) = (x.date, y.date)
        let window = clock.total
        let a = timers(before), b = timers(after)
        let paired = matches(a, b)
        let pairedA = Set(paired.map(\.0)), pairedB = Set(paired.map(\.1))
        let helperA = helperPerService(x), helperB = helperPerService(y)
        let assignedA = Assistants(export: x, reference: reference).assignments
        let assignedB = Assistants(export: y, reference: reference).assignments
        let potionA = potion(in: x), potionB = potion(in: y)

        // O1 : un minuteur qui court d'une photo à l'autre a occupé son poste toute la fenêtre.
        low += Double(paired.count) * window
        high += Double(paired.count) * window

        // O1 : fin dans la fenêtre, d'après la première photo. La fin lue est « avant assistant » (H2) et avant potion.
        for (i, t) in a.enumerated() where !pairedA.contains(i) {
            guard let end = t.end else { high += window; continue }                         // fin inconnue : de 0 à toute la fenêtre
            let helped = assignedA.contains { $0.itemID == t.itemID && $0.level + 1 == t.target && $0.ends == end }
            let d = duration(t.itemID, level: t.target) ?? Int(end.timeIntervalSince(t0))
            let remaining = Int(max(0, end.timeIntervalSince(t0)))
            let sv = min(remaining, saving(duration: min(d, remaining), profilePercent: 0,
                                           helper: helped ? helperA : 0, potion: potionA))
            high += clock.awake(min(end, t1))
            low += clock.awake(min(end.addingTimeInterval(-TimeInterval(sv)), t1))
        }

        // O1 : début déduit, d'après la seconde photo (fin − durée complète).
        for (j, t) in b.enumerated() where !pairedB.contains(j) {
            guard let end = t.end, let d = duration(t.itemID, level: t.target) else { high += window; continue }
            let helped = assignedB.contains { $0.itemID == t.itemID && $0.level + 1 == t.target && $0.ends == end }
            let earliest = end.addingTimeInterval(-TimeInterval(d))
            let sv = saving(duration: d, profilePercent: profile.reductionPercent(for: kind, at: earliest),
                            helper: helped ? helperB : 0, potion: potionB)
            let latest = earliest.addingTimeInterval(TimeInterval(sv))
            high += clock.total - clock.awake(earliest)
            low += clock.total - clock.awake(latest)
        }

        // O3 : les niveaux gagnés sans minuteur visible.
        let phi = window / t1.timeIntervalSince(t0)                                          // part de la fenêtre où l'on joue
        let helper = max(helperA, helperB), anyPotion = potionA || potionB
        for id in Set(before.elements.map(\.itemID)).union(after.elements.map(\.itemID)).sorted()
        where counts(reference.item(id)) {
            for level in invisibleLevels(of: id) {
                guard let d = duration(id, level: level), d > 0 else { continue }
                invisible += 1
                let sv = saving(duration: d, profilePercent: profile.reductionPercent(for: kind, at: t0),
                                helper: helper, potion: anyPotion)
                high += Double(d) * phi
                low += Double(d - sv) * phi
            }
        }

        let available = Double(n) * window
        let lo = Int(min(low, available).rounded()), hi = Int(min(high, available).rounded())
        return PostOccupation(worker: kind, workers: n, available: Int(available.rounded()),
                              busy: min(lo, hi)...hi, invisibleLevels: invisible)
    }

    /// Les niveaux gagnés entre les deux photos sans qu'un minuteur de la première les ait annoncés : on compare les
    /// exemplaires de chaque type par rang, du plus haut au plus bas, comme `PhotoDiff` ; une perte (fusion) est ignorée.
    private func invisibleLevels(of id: Int) -> [Int] {
        func units(_ v: Village) -> [(level: Int, upgrading: Bool)] {
            v.elements.filter { $0.itemID == id }
                .flatMap { Array(repeating: (level: $0.level, upgrading: $0.upgrading), count: $0.count) }
                .sorted { ($0.level, $0.upgrading ? 1 : 0) > ($1.level, $1.upgrading ? 1 : 0) }
        }
        let (u, v) = (units(before), units(after))
        var out: [Int] = []
        for (rank, now) in v.enumerated() {
            let was = rank < u.count ? u[rank] : (level: 0, upgrading: false)
            let first = was.level + 1 + (was.upgrading ? 1 : 0)       // le niveau du minuteur de la première photo est visible
            if now.level >= first { out += Array(first...now.level) }
        }
        return out
    }
}

// MARK: - Le rythme (O6)

/// Le taux d'occupation de chaque poste sur les 30 derniers jours, et de quoi décider qu'il est assez solide.
public struct Rhythm: Sendable, Equatable {
    public struct Rate: Sendable, Equatable {
        public let low: Double
        public let high: Double
        public var mid: Double { (low + high) / 2 }
        public var isApproximate: Bool { high - low > 0.005 }
        public init(low: Double, high: Double) {
            self.low = low
            self.high = high
        }
    }

    public static let days = 30
    public static let minimumPhotos = 3
    public static let minimumSpan: TimeInterval = 7 * 86_400

    public let from: Date
    public let to: Date
    public let photos: Int
    public let rates: [WorkerKind: Rate]

    public init(from: Date, to: Date, photos: Int, rates: [WorkerKind: Rate]) {
        self.from = from
        self.to = to
        self.photos = photos
        self.rates = rates
    }

    /// Un rythme réglé à la main (tests, variantes) : le même `rate` pour chaque poste.
    public init(rate: Double) {
        self.init(from: .distantPast, to: .distantPast, photos: 0,
                  rates: Dictionary(uniqueKeysWithValues: Occupation.kinds.map { ($0, Rate(low: rate, high: rate)) }))
    }

    /// Le taux appliqué par la simulation : le milieu de l'intervalle, ou 1 (jamais à l'arrêt) pour un poste sans mesure.
    public func rate(for worker: WorkerKind) -> Double { rates[worker]?.mid ?? 1 }

    /// O6 : les occupations (de photos consécutives) qui tiennent dans les 30 jours avant la photo la plus récente ;
    /// nil avant trois photos couvrant au moins sept jours, ou quand aucun poste n'a de mesure.
    public static func measure(_ occupations: [Occupation]) -> Rhythm? {
        guard let last = occupations.map(\.to).max() else { return nil }
        let start = last.addingTimeInterval(-TimeInterval(days) * 86_400)
        let kept = occupations.filter { $0.from >= start }
        let dates = Set(kept.flatMap { [$0.from, $0.to] })
        guard dates.count >= minimumPhotos, let first = dates.min(), last.timeIntervalSince(first) >= minimumSpan else { return nil }
        var rates: [WorkerKind: Rate] = [:]
        for kind in Occupation.kinds {
            let posts = kept.compactMap { $0.post(kind) }
            let available = Double(posts.reduce(0) { $0 + $1.available })
            guard available > 0 else { continue }
            rates[kind] = Rate(low: Double(posts.reduce(0) { $0 + $1.busy.lowerBound }) / available,
                               high: Double(posts.reduce(0) { $0 + $1.busy.upperBound }) / available)
        }
        return rates.isEmpty ? nil : Rhythm(from: first, to: last, photos: dates.count, rates: rates)
    }
}

// MARK: - Depuis les photos

extension HistoryStore {
    /// L'occupation entre chaque paire de photos lisibles consécutives (les photos qui ne se relisent pas sont
    /// sautées), de la plus ancienne paire à la plus récente. `since` : ignore les photos plus anciennes.
    public func occupations(context: HistoryContext, since: Date? = nil) -> [Occupation] {
        let store = photos
        let exports = store.list().filter { since == nil || $0.date >= since! }
            .compactMap { store.text(of: $0).flatMap { try? VillageExport.parse($0) } }
        return zip(exports, exports.dropFirst()).compactMap {
            Occupation(between: $0, and: $1, reference: context.reference, profile: context.profile)
        }
    }

    /// Le rythme des 30 derniers jours (O6) ; nil tant qu'il n'est pas assez solide.
    public func rhythm(context: HistoryContext) -> Rhythm? {
        guard let latest = photos.latest()?.snapshot.date else { return nil }
        return Rhythm.measure(occupations(context: context,
                                          since: latest.addingTimeInterval(-TimeInterval(Rhythm.days) * 86_400)))
    }
}
