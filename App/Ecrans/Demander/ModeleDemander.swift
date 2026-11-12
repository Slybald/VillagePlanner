import ChantierKit
import Foundation
import Observation
import Synchronization

/// Les deux zones de saisie de l'écran Demander : le profil en une phrase et les questions (T21, PLAN §6.1).
/// Il vit dans la feuille (`@State`) : fermée, tout disparaît (phrase, profil proposé, questions et réponses). Rien n'est écrit,
/// rien n'est journalisé ; chaque envoi est un appel compté au budget (T19). Un échec ne montre qu'un message court.
@MainActor @Observable
final class ModeleDemander {
    var phrase = ""
    var question = ""
    private(set) var propose: ProfilPropose?
    private(set) var profilEnCours = false
    private(set) var messageProfil: String?
    private(set) var questionEnCours = false
    private(set) var echanges: [EchangeQuestion] = []
    @ObservationIgnored private let conversation = ConversationQuestions()
    @ObservationIgnored private let client: ClaudeClient
    #if DEBUG
    @ObservationIgnored private let fausseApi: FausseApi?
    @ObservationIgnored private var automatique = true
    #endif

    init(conseil: ModeleConseil) {
        client = conseil.client
        #if DEBUG
        fausseApi = conseil.fausseApi
        // Captures : `-demander-phrase` et `-demander-question` remplissent la zone et l'envoient (fausse API, jamais le réseau).
        phrase = UserDefaults.standard.string(forKey: "demander-phrase") ?? ""
        question = UserDefaults.standard.string(forKey: "demander-question") ?? ""
        #endif
    }

    // MARK: Profil

    /// La phrase devient un profil proposé (rien n'est appliqué).
    func proposer(affiche: VillageAffiche, reference: ReferenceData, actuel: Profile) {
        let texte = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty, !profilEnCours, let plan = affiche.plan else { return }
        profilEnCours = true
        messageProfil = nil
        propose = nil
        #if DEBUG
        fausseApi?.reponse.withLock { $0 = Self.profilDeCapture(village: affiche.village, reference: reference) }
        #endif
        let client = client
        Task {
            let r = await GardeProfil.proposer(phrase: texte, village: affiche.village, reference: reference, actuel: actuel, client: client,
                                               now: plan.maintenant, fuseau: plan.fuseau, appel: Date())
            profilEnCours = false
            switch r {
            case .success(let p):
                if p.estVide { messageProfil = "Rien à changer : cette phrase ne modifie aucun réglage." } else { propose = p }
            case .failure(.rejet): messageProfil = "Je n'ai pas compris cette phrase de façon sûre. Reformule-la, ou règle ton profil dans les Réglages."
            case .failure(.service(let e)): messageProfil = Self.message(e)
            }
        }
    }

    func annulerProfil() {
        propose = nil
        messageProfil = nil
    }

    /// Le joueur a confirmé : le profil proposé devient son profil.
    func appliquer(_ modele: ModeleApp) {
        guard let propose else { return }
        modele.profil = propose.profil
        self.propose = nil
        phrase = ""
        messageProfil = "Profil appliqué."
    }

    // MARK: Questions

    func poser(affiche: VillageAffiche, reference: ReferenceData, modele: ModeleApp) {
        let texte = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty, !questionEnCours, let plan = affiche.plan, let contexte = modele.contexteQuestion(affiche, reference: reference) else { return }
        questionEnCours = true
        question = ""
        let resume = ResumeConseil.make(village: affiche.village, rapport: affiche.rapport, plan: plan.plan, besoins: plan.besoins,
                                        profil: plan.profil, reference: reference, photo: plan.photo, consigneMoteur: plan.consigne,
                                        changements: affiche.changements, timeZone: plan.fuseau)
        #if DEBUG
        fausseApi?.reponse.withLock { $0 = Self.questionDeCapture(texte) }
        #endif
        let client = client
        Task {
            let e = await Questions.poser(texte, contexte: contexte, resume: resume, client: client, fuseau: plan.fuseau, appel: Date())
            conversation.ajouter(e)
            echanges = conversation.echanges
            questionEnCours = false
        }
    }

    /// Captures : envoie la phrase et la question passées en arguments de lancement, une fois.
    func lancerCaptures(affiche: VillageAffiche, reference: ReferenceData, modele: ModeleApp) {
        #if DEBUG
        guard automatique else { return }
        automatique = false
        // L'un après l'autre : la fausse API n'a qu'une réponse à la fois.
        Task {
            if !phrase.isEmpty {
                proposer(affiche: affiche, reference: reference, actuel: modele.profil)
                while profilEnCours { try? await Task.sleep(for: .milliseconds(50)) }
            }
            if !question.isEmpty { poser(affiche: affiche, reference: reference, modele: modele) }
        }
        #endif
    }

    static func message(_ e: ClaudeError) -> String {
        switch e {
        case .noKey: "Ajoute ta clé d'API dans les Réglages pour utiliser cette fonction."
        case .budgetReached: "Le plafond d'appels est atteint pour aujourd'hui."
        default: "Le conseiller ne répond pas pour le moment. Réessaie plus tard."
        }
    }

    #if DEBUG
    private static func profilDeCapture(village: Village, reference: ReferenceData) -> String {
        let permis = GardeProfil.epinglables(village: village, reference: reference)
        let reine = permis.first { reference.name(of: $0) == "Reine des archères" } ?? permis.first ?? 0
        return json(["orientation": "attaque", "limiteHeros": 1, "epingles": [reine], "heuresSansJeu": "plage", "debut": 22, "fin": 6,
                     "pourcentOuvriers": 20, "joursOuvriers": 7, "pourcentLabo": nil, "joursLabo": nil])
    }

    private static func questionDeCapture(_ question: String) -> String {
        let q = question.lowercased()
        let (variante, phrase) = q.contains("pourquoi") ? ("aucune", "elle débloque d'autres améliorations du village")
            : q.contains("heures") ? ("sans_heures_sans_jeu", "chaque poste se relance dès qu'il est prêt")
            : ("ouvrier_en_plus", "un poste de plus permet de lancer d'autres améliorations en parallèle")
        return json(["variante": variante, "pourcent": nil, "phrase": phrase])
    }

    private static func json(_ o: [String: Any?]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: o.mapValues { $0 ?? NSNull() })) ?? Data(), as: UTF8.self)
    }
    #endif
}
