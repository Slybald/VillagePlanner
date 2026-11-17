import VillagePlannerKit
import Foundation

/// Un couloir du planning : un ouvrier, le labo ou la Maison des familiers, avec ce qu'il fait et sa file.
struct Couloir: Identifiable {
    let poste: WorkerKind
    /// Numéro dans son poste, à partir de 0.
    let numero: Int
    /// Un bâtiment qui représente le poste (image du couloir libre) et son niveau dans le village.
    let emblem: Int
    let niveauEmblem: Int
    /// Une amélioration de la photo dont le minuteur court encore à `maintenant`.
    let enCours: ScheduledStep?
    /// Une amélioration de la photo dont le minuteur est passé : le poste est libre depuis sa fin.
    let fini: ScheduledStep?
    /// Les lancements conseillés, dans l'ordre. Rien n'est lancé tant que le joueur ne l'a pas fait (une nouvelle photo).
    let file: [ScheduledStep]

    var id: String { "\(poste.rawValue)-\(numero)" }
    /// Le poste est libre à la date du calcul : rien n'y tourne.
    var estLibre: Bool { enCours == nil }

    static let cabane = 1_000_015, labo = 1_000_007, maisonDesFamiliers = 1_000_068

    /// Les couloirs du plan : tous les ouvriers (même sans rien à faire), le labo et les familiers s'ils existent.
    /// `lancees` : une amélioration marquée « Lancé » reste dans le couloir où on l'a marquée (`displayLanes`, règle L8).
    static func de(_ plan: Plan, village: Village, lancees: LocalActionsResult? = nil) -> [Couloir] {
        func couloirs(_ poste: WorkerKind, emblem: Int) -> [Couloir] {
            let niveau = max(village.niveau(de: emblem), 1)
            // Sans marque, les couloirs de la simulation ; avec, chaque marque dans le couloir touché (L8).
            return displayLanes(of: plan, worker: poste, posts: village.workers[poste] ?? 0, launches: lancees)
                .enumerated().map { numero, siens in
                    let photo = siens.filter(\.fromSnapshot)
                    return Couloir(poste: poste, numero: numero, emblem: emblem, niveauEmblem: niveau,
                                   enCours: photo.first { $0.end > plan.now },
                                   fini: photo.filter { $0.end <= plan.now }.max { $0.end < $1.end },
                                   file: siens.filter { !$0.fromSnapshot }.sorted { $0.start < $1.start })
                }
        }
        return couloirs(.builder, emblem: cabane) + couloirs(.laboratory, emblem: labo)
            + couloirs(.petHouse, emblem: maisonDesFamiliers)
    }
}

/// Le poste qui finit en dernier, dit en une phrase : « Le labo finit 40 j après les ouvriers. »
func phraseDernierPoste(_ plan: Plan) -> String? {
    guard let dernier = plan.lastWorker, let fin = plan.workerEnds[dernier] else { return nil }
    let (sujet, verbe): (String, String) = switch dernier {
    case .builder: ("Les ouvriers", "finissent")
    case .laboratory: ("Le labo", "finit")
    case .petHouse: ("Les familiers", "finissent")
    case .blacksmith: ("La forge", "finit")
    }
    func nom(_ w: WorkerKind) -> String { w == .builder ? "les ouvriers" : w == .laboratory ? "le labo" : "les familiers" }
    guard let (autre, finAutre) = plan.workerEnds.filter({ $0.key != dernier }).max(by: { $0.value < $1.value }) else {
        return "\(sujet) \(verbe) en dernier."
    }
    let ecart = Int(fin.timeIntervalSince(finAutre))
    guard ecart >= 3600 else { return "\(sujet) \(verbe) en même temps que \(nom(autre))." }
    return "\(sujet) \(verbe) \(Lisible.duree(ecart)) après \(nom(autre))."
}
