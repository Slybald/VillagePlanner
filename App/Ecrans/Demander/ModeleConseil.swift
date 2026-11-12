import ChantierKit
import Foundation
import Observation
import Synchronization

/// Le conseil du modèle, gardé sous sa clé (T20, PLAN §6.3). Il est demandé à l'import et quand la clé du conseil change
/// (photo, profil, versions des données, jour), à la prochaine ouverture de l'écran Cap ; rouvrir l'app sans changement
/// n'appelle rien. Tout échec laisse la consigne du moteur à l'écran (G3) : ce modèle ne montre jamais une erreur.
@MainActor @Observable
final class ModeleConseil {
    /// Le dernier conseil accepté, et la clé sous laquelle il a été obtenu.
    private(set) var texte: String?
    private(set) var cleDuTexte: String?
    @ObservationIgnored private var enCours: String?
    @ObservationIgnored private let conseiller: Conseiller
    @ObservationIgnored private var exempleAutorise = false
    #if DEBUG
    @ObservationIgnored private var fausseApi: FausseApi?
    #endif

    init() {
        #if DEBUG
        // Captures : `-conseil-exemple conseiller|repli` joue le conseiller avec une fausse API (jamais le réseau, jamais une vraie clé).
        if let exemple = UserDefaults.standard.string(forKey: "conseil-exemple") {
            let nom = "chantier-conseil-capture"
            UserDefaults.standard.removePersistentDomain(forName: nom)
            let defaults = UserDefaults(suiteName: nom) ?? .standard
            let fausse = exemple == "conseiller" ? FausseApi() : nil
            fausseApi = fausse
            exempleAutorise = true
            let client = ClaudeClient(keys: MemorySecretStore(fausse == nil ? nil : "factice-capture-0000-0000-0000-4F2A"),
                                      budget: BudgetStore(defaults: defaults), transport: fausse, calendar: .current)
            conseiller = Conseiller(client: client, store: PreferencesConseil(defaults: defaults))
            return
        }
        #endif
        conseiller = Conseiller(client: ClaudeClient(keys: KeychainStore(), budget: BudgetStore(), calendar: .current),
                                store: PreferencesConseil())
    }

    /// La clé du conseil pour ce village ; nil quand il n'y a rien à demander (pas de plan, village d'exemple).
    func cle(_ affiche: VillageAffiche, reference: ReferenceData, conseilsDate: String) -> String? {
        guard let plan = affiche.plan, let photo = affiche.photo?.date ?? (exempleAutorise ? affiche.village.date : nil) else { return nil }
        return CleConseil.make(photo: photo, profil: plan.profil, referenceCommit: reference.source.commit, conseilsDate: conseilsDate,
                               now: plan.maintenant, timeZone: plan.fuseau)
    }

    /// Le conseil s'il est celui de cette clé, sinon la consigne du moteur (G3) : un conseil périmé ne se montre jamais.
    func consigne(moteur: String, cle: String?) -> String { texteGarde(cle: cle) ?? moteur }
    func estConseil(cle: String?) -> Bool { texteGarde(cle: cle) != nil }

    private func texteGarde(cle: String?) -> String? { cle != nil && cle == cleDuTexte ? texte : nil }

    /// Demande le conseil de cette clé si on ne l'a pas. La demande va jusqu'au bout même si l'écran disparaît
    /// (une requête annulée serait comptée au budget sans rien rapporter).
    func rafraichir(_ affiche: VillageAffiche, reference: ReferenceData, conseilsDate: String) {
        guard let plan = affiche.plan, let cle = cle(affiche, reference: reference, conseilsDate: conseilsDate),
              cleDuTexte != cle, enCours != cle else { return }
        if let garde = conseiller.garde(pour: cle) {                    // rouvrir sans changement : rien ne part
            texte = garde
            cleDuTexte = cle
            return
        }
        let resume = ResumeConseil.make(village: affiche.village, rapport: affiche.rapport, plan: plan.plan, besoins: plan.besoins,
                                        profil: plan.profil, reference: reference, photo: plan.photo, consigneMoteur: plan.consigne,
                                        changements: affiche.changements, timeZone: plan.fuseau)
        #if DEBUG
        fausseApi?.texte.withLock { $0 = Self.texteDeCapture(resume, plan, reference) }
        #endif
        enCours = cle
        Task {
            let issue = await conseiller.obtenir(resume: resume, cle: cle, reference: reference, now: Date())
            if enCours == cle { enCours = nil }
            // Seul un conseil accepté se garde à l'écran ; un échec laisse le moteur, et sera retenté plus tard (délai du conseiller).
            if case .conseil(let t) = issue { texte = t; cleDuTexte = cle }
        }
    }

    #if DEBUG
    /// La réponse de la fausse API : les premières phrases de la consigne du moteur, puis la raison de la première amélioration.
    private static func texteDeCapture(_ resume: ResumeConseil, _ plan: PlanAffiche, _ reference: ReferenceData) -> String {
        let phrases = plan.consigne.split(separator: ".").prefix(2).joined(separator: ".") + "."
        guard let id = plan.plan.steps.first(where: { !$0.fromSnapshot })?.step.itemID, let nom = reference.name(of: id),
              let raison = resume.texte.components(separatedBy: "Raison : ").dropFirst().first?.split(separator: ".").first else { return phrases }
        return phrases + " \(nom) d'abord : \(raison)."
    }
    #endif
}

#if DEBUG
/// Un « service » qui répond toujours par `texte`, au format d'une réponse de l'API Messages. Captures seulement.
final class FausseApi: HTTPTransport {
    let texte = Mutex("")

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let reponse = try JSONSerialization.data(withJSONObject: ["texte": texte.withLock { $0 }, "ids": [Int]()])
        let corps: [String: Any] = [
            "id": "msg_capture", "type": "message", "role": "assistant", "model": ClaudeClient.model,
            "content": [["type": "text", "text": String(decoding: reponse, as: UTF8.self)]], "stop_reason": "end_turn",
            "usage": ["input_tokens": 3_500, "output_tokens": 900],
        ]
        let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (try JSONSerialization.data(withJSONObject: corps), http)
    }
}
#endif
