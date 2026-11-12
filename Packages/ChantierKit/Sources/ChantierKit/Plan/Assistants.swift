import Foundation

// Les assistants dans la simulation (PLAN §5.4, règle S6).
//
// L'Apprenti ouvrier aide un poste d'ouvriers, l'Assistant de labo le labo (pas la Maison des familiers) ; l'Alchimiste
// ne change aucune date (multiplicateur 0 dans les données, et il n'est dans aucun poste). Un service dure une heure
// (`helperSeconds`) et retire `helperMultiplier` heures de travail à l'amélioration aidée, ce que dit le jeu
// (« le niveau 1 retire 1 heure, le niveau 2 en retire 2 »). Pendant le service l'amélioration avance donc
// `1 + multiplicateur` fois plus vite ; si elle finit avant la fin du service, elle finit plus tôt encore (fonction
// `helperRemaining`).
//
// Règles de ce fichier, reprises dans les noms de tests (AssistantsTests) :
//  S6a  la photo : `helper_timer` (secondes de service restantes sur une amélioration) raccourcit son minuteur
//       (qui est donné « avant assistant ») ; `helper_recurrent` : l'assistant reprend seul, sans geste, à chaque
//       fin de pause, tant que l'amélioration dure ; `helper_cooldown` : l'assistant ne sert plus avant la fin de
//       sa pause (la journée de 23 h que l'export partage entre assistants) ;
//  S6b  les améliorations futures : dès qu'un assistant est libre, il prend l'amélioration en cours la plus longue
//       de son poste (fin la plus tardive) et y reste jusqu'à sa fin, comme avec la case « garder affecté »
//       de l'export ; la pause est de 23 h entre deux services ;
//  S6c  l'affectation d'un assistant est un geste du joueur : jamais pendant les heures sans jeu (S4). Seuls les
//       services suivants d'une affectation « gardée » tombent la nuit ;
//  S6d  l'Alchimiste n'agit pas sur le temps ; un assistant absent de l'export n'aide personne ;
//  S6e  sans assistant, le plan est celui de T13, à l'identique.
// Décisions :
//  - la pause de 23 h n'est pas dans la source (le jeu la dit sur le portail d'aide) : constante `helperWorkday`,
//    comptée entre les débuts de deux services du même assistant ; le jeu partage une journée entre les assistants,
//    ici chacun a la sienne (écart de quelques heures sur les dates des services, pas sur leur nombre) ;
//  - un assistant sans affectation dans la photo ne sert pas avant la fin de `helper_cooldown` : l'export ne dit
//    pas s'il a travaillé ce jour-là ;
//  - le niveau d'un assistant reste celui de l'export (le plan ne monte pas les assistants : ils coûtent des gemmes).

/// Pause entre le début de deux services d'un même assistant, en secondes (« journée de travail » de 23 h).
let helperWorkday = 23 * 3600

/// Les assistants qui accélèrent un poste. L'Alchimiste (93000002) n'y est pas : il convertit des ressources.
let helperPosts: [Int: WorkerKind] = [93_000_000: .builder, 93_000_001: .laboratory]

/// Un service d'assistant : `savedSeconds` retirés à l'amélioration (itemID, niveau atteint, exemplaire) aidée.
public struct HelperService: Sendable, Equatable {
    public let helper: Int
    public let itemID: Int
    public let level: Int
    public let copy: Int
    /// Début du service ; pour celui que la photo montrait déjà en cours, la date de la photo.
    public let start: Date
    public let savedSeconds: Int
}

/// Ce que l'export dit des assistants : ceux du village et les améliorations qu'ils aident.
public struct Assistants: Sendable, Equatable {
    public struct Helper: Sendable, Equatable {
        public let itemID: Int
        public let level: Int
        /// `helper_cooldown` : secondes restantes de la pause, à la date de la photo ; nil : aucune.
        public let cooldown: Int?

        public init(itemID: Int, level: Int, cooldown: Int? = nil) {
            self.itemID = itemID
            self.level = level
            self.cooldown = cooldown
        }
    }

    /// Une amélioration en cours que l'export dit aidée (`helper_timer`) ou gardée aidée (`helper_recurrent`).
    public struct Assignment: Sendable, Equatable {
        public let helperID: Int
        public let itemID: Int
        /// Niveau de l'élément dans l'export : le pas aidé atteint `level + 1`.
        public let level: Int
        /// Fin du minuteur de l'export ; nil quand il est illisible.
        public let ends: Date?
        public let recurrent: Bool
        /// `helper_timer` : secondes de service restantes à la date de la photo.
        public let timer: Int?

        public init(helperID: Int, itemID: Int, level: Int, ends: Date?, recurrent: Bool, timer: Int? = nil) {
            self.helperID = helperID
            self.itemID = itemID
            self.level = level
            self.ends = ends
            self.recurrent = recurrent
            self.timer = timer
        }
    }

    public let helpers: [Helper]
    public let assignments: [Assignment]

    public init(helpers: [Helper] = [], assignments: [Assignment] = []) {
        self.helpers = helpers
        self.assignments = assignments
    }

    /// Lit la section `helpers` et les champs `helper_*` des lignes du village principal. L'assistant d'une
    /// amélioration est celui de son poste (la référence dit le poste de chaque type).
    public init(export: VillageExport, reference: ReferenceData) {
        func seconds(_ v: JSONValue?) -> Int? {
            guard case .number(let x)? = v, x.isFinite, x >= 0, x < 1e9 else { return nil }
            return Int(x)
        }
        helpers = (export.sections["helpers"] ?? []).compactMap { e in
            e.level.map { Helper(itemID: e.id, level: $0, cooldown: seconds(e.extras["helper_cooldown"])) }
        }
        var found: [Assignment] = []
        for section in Village.sections where section != "helpers" {
            for e in export.sections[section] ?? [] {
                let recurrent: Bool
                switch e.extras["helper_recurrent"] {
                case .bool(let b)?: recurrent = b
                case .number(let x)?: recurrent = x != 0
                default: recurrent = false
                }
                let timer = seconds(e.extras["helper_timer"])
                let upgrading = e.timer != nil || e.extras["timer"] != nil
                guard recurrent || timer != nil, upgrading, let item = reference.item(e.id),
                      let helper = helperPosts.first(where: { $0.value == item.worker })?.key else { continue }
                found.append(Assignment(helperID: helper, itemID: e.id, level: e.level ?? 0,
                                        ends: e.timer.map { export.date.addingTimeInterval(TimeInterval($0)) },
                                        recurrent: recurrent, timer: timer))
            }
        }
        assignments = found
    }
}

/// Temps restant d'une amélioration `remaining` secondes avant le début d'un service de `service` secondes : pendant
/// le service elle avance `1 + multiplier` fois plus vite, et finit plus tôt encore si elle finit pendant le service.
func helperRemaining(_ remaining: Int, service: Int, multiplier: Int) -> Int {
    guard multiplier > 0, service > 0, remaining > 0 else { return max(0, remaining) }
    if remaining <= service * (1 + multiplier) { return (remaining + multiplier) / (1 + multiplier) }
    return remaining - service * multiplier
}

/// Un assistant pendant la simulation : son poste, ce que ses données disent de son niveau, et quand il peut
/// recommencer un service.
struct HelperRuntime {
    let id: Int
    let post: WorkerKind
    let multiplier: Int
    let service: Int
    var availableAt: Date

    /// Les assistants du village qui accélèrent un poste, par identifiant. Niveau inconnu de la référence ou
    /// multiplicateur nul : ils ne changent aucune date, on ne les garde pas.
    static func crew(_ assistants: Assistants, reference: ReferenceData, photo: Date) -> [HelperRuntime] {
        var out: [HelperRuntime] = []
        for h in assistants.helpers.sorted(by: { $0.itemID < $1.itemID }) where !out.contains(where: { $0.id == h.itemID }) {
            guard let post = helperPosts[h.itemID],
                  let level = reference.item(h.itemID)?.levels.first(where: { $0.level == h.level }),
                  let m = level.helperMultiplier, m > 0, let s = level.helperSeconds, s > 0 else { continue }
            out.append(HelperRuntime(id: h.itemID, post: post, multiplier: m, service: s,
                                     availableAt: photo.addingTimeInterval(TimeInterval(h.cooldown ?? 0))))
        }
        return out
    }
}

extension Simulation {
    /// Suite de services d'un assistant sur l'amélioration `running[i]`, le premier à `start` (`first` secondes),
    /// les suivants toutes les `helperWorkday` si l'affectation est gardée. La fin de l'amélioration est rapprochée
    /// service après service ; l'assistant n'est libre qu'une pause après son dernier début.
    mutating func serve(_ h: Int, on i: Int, from start: Date, first: Int, keep: Bool) {
        var s = start, service = first, end = running[i].end
        while s < end, service > 0 {
            let was = Int(end.timeIntervalSince(s).rounded(.up))
            let left = helperRemaining(was, service: service, multiplier: crew[h].multiplier)
            end = s.addingTimeInterval(TimeInterval(left))
            let job = running[i].job
            helperServices.append(HelperService(helper: crew[h].id, itemID: job.step.itemID, level: job.step.level,
                                                copy: job.index, start: s, savedSeconds: was - left))
            crew[h].availableAt = s.addingTimeInterval(TimeInterval(helperWorkday))
            guard keep else { break }
            s = crew[h].availableAt
            service = crew[h].service
        }
        running[i].end = end
        scheduled[running[i].slot].end = end
    }

    /// S6a : l'affectation lue dans la photo pour le pas `step` (minuteur `ends`), lancé comme `running[i]`.
    mutating func assistPhoto(_ step: UpgradeStep, ends: Date?, running i: Int) {
        guard let k = photoAssignments.firstIndex(where: {
            $0.itemID == step.itemID && $0.level + 1 == step.level && $0.ends == ends
        }) else { return }
        let a = photoAssignments.remove(at: k)
        guard let h = crew.firstIndex(where: { $0.id == a.helperID && $0.post == step.worker }) else { return }
        let cooldown = crew[h].availableAt                                    // photo + helper_cooldown, ou photo
        if let left = a.timer, left > 0 {
            serve(h, on: i, from: photo, first: left, keep: false)            // le service de la photo, déjà commencé
            // Sans `helper_cooldown`, la pause court depuis le début de ce service (il a déjà duré service - left).
            crew[h].availableAt = cooldown > photo ? cooldown
                : photo.addingTimeInterval(TimeInterval(helperWorkday - (crew[h].service - left)))
        }
        if a.recurrent { serve(h, on: i, from: crew[h].availableAt, first: crew[h].service, keep: true) }
    }

    /// S6b, S6c : à l'instant `t` (jamais dans les heures sans jeu), chaque assistant libre prend l'amélioration en
    /// cours la plus longue de son poste, à égalité le couloir le plus bas.
    mutating func bindHelpers(at t: Date) {
        for h in crew.indices where crew[h].availableAt <= t {
            let candidates = running.indices.filter { running[$0].job.step.worker == crew[h].post }
            guard let i = candidates.max(by: { a, b in
                running[a].end != running[b].end ? running[a].end < running[b].end : running[a].lane > running[b].lane
            }) else { continue }
            serve(h, on: i, from: t, first: crew[h].service, keep: true)
        }
    }

    /// Les dates où un assistant en pause redevient libre alors qu'une amélioration de son poste tourne : un
    /// événement, repoussé hors des heures sans jeu (S6c) pour que le geste d'affectation soit possible.
    func helperWakes(after t: Date, _ release: (Date) -> Date) -> [Date] {
        crew.filter { h in h.availableAt > t && running.contains { $0.job.step.worker == h.post } }
            .map { release($0.availableAt) }
    }
}
