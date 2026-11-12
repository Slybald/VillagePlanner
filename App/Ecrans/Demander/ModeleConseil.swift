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
    /// Le conseil ne vaut plus quand le premier lancement a commencé.
    private(set) var jusqua: Date?
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
                               etatDuPlan: ResumeConseil.etatDuPlan(plan.plan, reference: reference, photo: plan.photo),
                               now: plan.maintenant, timeZone: plan.fuseau)
    }

    /// Le conseil s'il est celui de cette clé et que son premier lancement n'a pas commencé, sinon la consigne du moteur (G3) :
    /// un conseil périmé ne se montre jamais.
    func consigne(moteur: String, cle: String?, now: Date) -> String { texteGarde(cle: cle, now: now) ?? moteur }
    func estConseil(cle: String?, now: Date) -> Bool { texteGarde(cle: cle, now: now) != nil }

    private func texteGarde(cle: String?, now: Date) -> String? {
        guard cle != nil, cle == cleDuTexte, jusqua.map({ now < $0 }) ?? true else { return nil }
        return texte
    }

    /// Demande le conseil de cette clé si on ne l'a pas. La demande va jusqu'au bout même si l'écran disparaît
    /// (une requête annulée serait comptée au budget sans rien rapporter).
    func rafraichir(_ affiche: VillageAffiche, reference: ReferenceData, conseilsDate: String) {
        guard let plan = affiche.plan, let cle = cle(affiche, reference: reference, conseilsDate: conseilsDate),
              cleDuTexte != cle, enCours != cle else { return }
        if let garde = conseiller.garde(pour: cle, now: plan.maintenant) {      // rouvrir sans changement : rien ne part
            texte = garde.texte
            jusqua = garde.jusqua
            cleDuTexte = cle
            return
        }
        let resume = ResumeConseil.make(village: affiche.village, rapport: affiche.rapport, plan: plan.plan, besoins: plan.besoins,
                                        profil: plan.profil, reference: reference, photo: plan.photo, consigneMoteur: plan.consigne,
                                        changements: affiche.changements, timeZone: plan.fuseau)
        #if DEBUG
        fausseApi?.reponse.withLock { $0 = Self.reponseDeCapture(resume) }
        #endif
        enCours = cle
        Task {
            let issue = await conseiller.obtenir(resume: resume, cle: cle, reference: reference, now: Date())
            if enCours == cle { enCours = nil }
            // Seul un conseil accepté se garde à l'écran ; un échec laisse le moteur, et sera retenté plus tard (délai du conseiller).
            if case .conseil(let t, let jusqua) = issue { texte = t; self.jusqua = jusqua; cleDuTexte = cle }
        }
    }

    #if DEBUG
    /// La réponse de la fausse API : le premier lancement du plan, une raison toute prête, le second lancement.
    private static func reponseDeCapture(_ resume: ResumeConseil) -> String {
        let premier = resume.candidats.first?.id ?? 0
        let ensuite: Any = resume.candidats.dropFirst().first { $0.id != premier }.map { $0.id as Any } ?? NSNull()
        let json = try? JSONSerialization.data(withJSONObject: ["premier": premier, "raison": "elle débloque d'autres améliorations", "ensuite": ensuite])
        return String(decoding: json ?? Data(), as: UTF8.self)
    }
    #endif
}

#if DEBUG
/// Un « service » qui répond toujours par `reponse`, au format d'une réponse de l'API Messages. Captures seulement.
final class FausseApi: HTTPTransport {
    let reponse = Mutex("")

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let corps: [String: Any] = [
            "id": "msg_capture", "type": "message", "role": "assistant", "model": ClaudeClient.model,
            "content": [["type": "text", "text": reponse.withLock { $0 }]], "stop_reason": "end_turn",
            "usage": ["input_tokens": 3_500, "output_tokens": 900],
        ]
        let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (try JSONSerialization.data(withJSONObject: corps), http)
    }
}
#endif
