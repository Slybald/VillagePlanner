import ChantierKit
import Foundation
import Synchronization

/// `swift run outils essais-conseiller [--simule]` : dix cas réels (le village de `reel-hdv16`, sans le moindre tag réel),
/// chacun envoyé à Haiku 5.5 avec les consignes de l'app, puis passé dans les garde-fous. Coût : environ un centime.
/// La clé se lit dans `ANTHROPIC_API_KEY` (jamais ailleurs) et n'est ni affichée ni écrite.
/// `--simule` : aucune requête, aucune clé ; le « modèle » recopie la consigne du moteur (pour vérifier la commande elle-même).
///
/// Seuil : au moins huit réponses justes sur dix acceptées par les garde-fous, et aucune réponse fausse acceptée.
///  - juste : acceptée par G1 et G2, et cite la première amélioration du plan ;
///  - fausse acceptée : acceptée par les garde-fous, mais nomme une amélioration de la liste qui n'est pas dans les trois premières
///    (le modèle n'a pas à choisir l'ordre). Les textes sont affichés : une lecture humaine reste nécessaire.
enum EssaisConseiller {
    struct Cas {
        let nom: String
        let apres: TimeInterval
        var profil = Profile()
        var changement = false
    }

    static let heure: TimeInterval = 3600, jour: TimeInterval = 86_400
    static let fuseau = TimeZone(identifier: "Europe/Paris")!

    static func lancer(simule: Bool) async -> Int32 {
        let environnement = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        if !simule, environnement?.isEmpty != false {
            print("ANTHROPIC_API_KEY absente : rien n'est envoyé. Exporte la variable (sans l'écrire dans un fichier), puis relance.")
            return 2
        }
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let texte = try? String(contentsOf: racine.appending(path: "Tests/ChantierKitTests/Fixtures/reel-hdv16.json"), encoding: .utf8),
              let export = try? VillageExport.parse(texte), let reference = try? ReferenceData.load() else {
            print("Lecture impossible de la photo d'essai ou des données de référence.")
            return 1
        }
        let advice = (try? AdviceData.load()) ?? AdviceData()
        let village = Village(export: export, reference: reference)
        func id(_ nom: String) -> Int { reference.items.first { $0.name == nom }?.id ?? 0 }
        let fin = village.date.addingTimeInterval(14 * jour)
        let cas = [
            Cas(nom: "Une heure après la photo, profil par défaut", apres: heure),
            Cas(nom: "Attaque, un héros à la fois", apres: heure, profil: Profile(orientation: .attack, heroLimit: 1)),
            Cas(nom: "Défense", apres: 2 * heure, profil: Profile(orientation: .defense)),
            Cas(nom: "Reine des archères épinglée", apres: heure, profil: Profile(pinned: [id("Reine des archères")])),
            Cas(nom: "Vingt heures après la photo (un poste libre)", apres: 20 * heure),
            Cas(nom: "Trois jours après la photo", apres: 3 * jour),
            Cas(nom: "Photo périmée (neuf jours)", apres: 9 * jour),
            Cas(nom: "Réduction de 20 % sur les ouvriers", apres: heure, profil: Profile(builderReduction: Reduction(percent: 20, endsAt: fin))),
            Cas(nom: "Réduction labo 10 %, sans heures sans jeu", apres: 5 * heure,
                profil: Profile(laboratoryReduction: Reduction(percent: 10, endsAt: fin), quietHours: nil)),
            Cas(nom: "Avec les changements depuis la photo précédente", apres: heure, changement: true),
        ]

        let reglages = UserDefaults(suiteName: "chantier-essais-conseiller")!
        reglages.removePersistentDomain(forName: "chantier-essais-conseiller")
        let budget = BudgetStore(defaults: reglages)
        let simulation = Simulation()
        let client = ClaudeClient(keys: MemorySecretStore(simule ? "cle-factice-essais-0000-1111-2222-3333-4444" : environnement),
                                  budget: budget, transport: simule ? simulation : nil, calendar: .current)
        var justes = 0, acceptees = 0, fausses = 0
        for (i, c) in cas.enumerated() {
            let now = village.date.addingTimeInterval(c.apres)
            let plan = makePlan(for: village, reference: reference, advice: advice, profile: c.profil, now: now, boosts: export.boosts,
                                assistants: Assistants(export: export, reference: reference))
            let pas = remainingSteps(of: village, reference: reference, profile: c.profil, now: now)
            let moteur = consigne(of: plan, photo: village.date, reference: reference, timeZone: fuseau)
            let canon = id("Canon")
            let changements = c.changement ? [ChangementPhoto(id: canon, depuis: 20, vers: 21)] : nil
            let resume = ResumeConseil.make(village: village, rapport: progress(of: village, reference: reference), plan: plan,
                                            besoins: resourceNeeds(of: plan, remaining: pas), profil: c.profil, reference: reference,
                                            photo: village.date, consigneMoteur: moteur, changements: changements, timeZone: fuseau)
            simulation.texte.withLock { $0 = moteur.split(separator: ".").prefix(3).joined(separator: ".") + "." }
            let etiquette = "\(i + 1)/\(cas.count) \(c.nom)"
            do throws(ClaudeError) {
                let reponse = try await client.ask(system: InstructionsConseiller.systeme, prompt: resume.texte, schema: ReponseConseil.schema,
                                                   as: ReponseConseil.self, now: Date())
                switch GardeFous.verifier(reponse, resume: resume, reference: reference) {
                case .acceptee(let texte):
                    acceptees += 1
                    let groupes = plan.steps.filter { !$0.fromSnapshot }.map { reference.name(of: $0.step.itemID) ?? "" }
                    var reste = replier(texte)
                    for nom in Set(groupes.prefix(3)).sorted(by: { $0.count > $1.count }) { reste = reste.replacingOccurrences(of: replier(nom), with: " ") }
                    // Photo périmée : le moteur ne propose aucune amélioration, la bonne réponse demande un nouvel export.
                    let premier = c.apres > 7 * jour ? replier(texte).contains("export")
                        : groupes.first.map { replier(texte).contains(replier($0)) } ?? true
                    let horsDesTrois = Set(groupes.dropFirst(3)).subtracting(groupes.prefix(3)).filter { reste.contains(replier($0)) }
                    if !horsDesTrois.isEmpty { fausses += 1 }
                    if premier && horsDesTrois.isEmpty { justes += 1 }
                    print("✔ \(etiquette) : acceptée" + (premier ? "" : ", mais ne cite pas la première amélioration")
                          + (horsDesTrois.isEmpty ? "" : ", FAUSSE : nomme \(horsDesTrois.sorted())"))
                    print("    « \(texte) »")
                case .refusee(let motif):
                    print("✘ \(etiquette) : rejetée par les garde-fous (\(motif))")
                    print("    « \(reponse.texte) »")
                }
            } catch {
                print("✘ \(etiquette) : pas de réponse (\(error))")
            }
        }
        print("")
        print("\(acceptees) acceptées sur \(cas.count), dont \(justes) justes ; \(fausses) fausse(s) acceptée(s).")
        print("Dépense comptée : \(budget.load().spentDollars.formatted(.number.precision(.fractionLength(4)))) $.")
        let reussi = justes >= 8 && fausses == 0
        print(reussi ? "Seuil atteint (huit justes sur dix, aucune fausse acceptée)." : "Seuil NON atteint (huit justes sur dix, aucune fausse acceptée).")
        return reussi ? 0 : 1
    }

    private static func replier(_ t: String) -> String { t.lowercased().folding(options: .diacriticInsensitive, locale: nil) }

    /// Le « service » de `--simule` : répond toujours par `texte`, au format d'une réponse de l'API Messages.
    final class Simulation: HTTPTransport {
        let texte = Mutex("")

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            let reponse = try JSONSerialization.data(withJSONObject: ["texte": texte.withLock { $0 }, "ids": [Int]()])
            let corps: [String: Any] = [
                "id": "msg_simule", "type": "message", "role": "assistant", "model": ClaudeClient.model,
                "content": [["type": "text", "text": String(decoding: reponse, as: UTF8.self)]], "stop_reason": "end_turn",
                "usage": ["input_tokens": 3_500, "output_tokens": 900],
            ]
            let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            return (try JSONSerialization.data(withJSONObject: corps), http)
        }
    }
}
