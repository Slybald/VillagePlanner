import Foundation
import Testing
@testable import ChantierKit

// Le résumé, le cache et la clé du conseil (T20). Le village est l'export réel anonymisé `reel-hdv16` (tag factice #2PP).
// Aucun test n'appelle le vrai service : le transport est simulé et compte les appels.

private let reference = Réel.reference
private let fuseau = TimeZone(identifier: "Europe/Paris")!
private let advice = (try? AdviceData.load()) ?? AdviceData()
private let maintenant = Réel.village.date.addingTimeInterval(3600)

/// Un plan, sa consigne et son résumé, calculés comme l'app le fait.
private struct Complet {
    let resume: ResumeConseil
    let plan: Plan
    let consigne: String

    init(village: Village = Réel.village, export: VillageExport = Réel.export, profil: Profile = Profile(), now: Date = maintenant,
         changements: [ChangementPhoto]? = nil) {
        plan = makePlan(for: village, reference: reference, advice: advice, profile: profil, now: now, boosts: export.boosts,
                        assistants: Assistants(export: export, reference: reference))
        let pas = remainingSteps(of: village, reference: reference, profile: profil, now: now)
        consigne = ChantierKit.consigne(of: plan, photo: village.date, reference: reference, timeZone: fuseau)
        resume = ResumeConseil.make(village: village, rapport: progress(of: village, reference: reference), plan: plan,
                                    besoins: resourceNeeds(of: plan, remaining: pas), profil: profil, reference: reference,
                                    photo: village.date, consigneMoteur: consigne, changements: changements, timeZone: fuseau)
    }
}

private func cle(photo: Date = Réel.village.date, profil: Profile = Profile(), actions: [Int] = [], commit: String = "abc", conseils: String = "2026-11-09",
                 now: Date = maintenant, tz: TimeZone = fuseau) -> String {
    CleConseil.make(photo: photo, profil: profil, actionsLocales: actions, referenceCommit: commit, conseilsDate: conseils, now: now, timeZone: tz)
}

/// Une réponse que les garde-fous acceptent : les trois premières phrases de la consigne du moteur, que le résumé contient.
private func bonneReponse(_ c: Complet) -> Reponse {
    .ok(GardeFousTests.json(c.consigne.split(separator: ".").prefix(3).joined(separator: ".") + ".", []))
}

@Suite struct ConseillerTests {
    // MARK: Le résumé

    @Test func resume_contientLesDixProchainesAmeliorations_ressources_cap_avancement_profil_changements() {
        var profil = Profile(orientation: .attack, heroLimit: 1)
        profil.pinned = [reference.items.first { $0.name == "Arc-X" }!.id]
        let changements = [ChangementPhoto(id: reference.items.first { $0.name == "Canon" }!.id, depuis: 20, vers: 21)]
        let c = Complet(profil: profil, changements: changements)
        let texte = c.resume.texte
        // Les dix prochaines améliorations : identifiant, nom, niveau visé, date, coût.
        let lancements = c.plan.steps.filter { !$0.fromSnapshot }
        let premier = lancements[0]
        let nom = reference.name(of: premier.step.itemID)!
        #expect(texte.contains("(id \(premier.step.itemID)) \(nom) \(premier.step.level)"))
        #expect(texte.contains("lancement " + Lisible.moment(premier.start, now: maintenant, timeZone: fuseau)))
        #expect(texte.contains("coût"))
        let lignes = texte.split(separator: "\n").filter { $0.hasPrefix("- (id ") }
        #expect(lignes.count >= 10, "au moins dix lignes d'identifiants (améliorations, changements)")
        let ameliorations = texte.components(separatedBy: "Prochaines améliorations, dans l'ordre du moteur :\n")[1]
            .split(separator: "\n").prefix { $0.hasPrefix("- (id ") }
        #expect(ameliorations.count == ResumeConseil.ameliorationsMax)
        // Le reste : cap, avancement, profil (en clair), changements, consigne du moteur.
        #expect(texte.contains("Cap : hôtel de ville 16 terminé"))
        #expect(texte.contains("Avancement : total"))
        #expect(texte.contains("Profil : orientation attaque"))
        #expect(texte.contains("limite de héros en amélioration : 1"))
        #expect(texte.contains("épinglés : Arc-X"))
        #expect(texte.contains("Changements depuis la photo précédente :\n- (id \(changements[0].id)) Canon niveau 20 → 21."))
        #expect(texte.contains("Consigne du moteur, à reformuler : " + c.consigne))
        #expect(texte.contains("Ressources à réunir :"))
        #expect(c.resume.identifiants.contains(premier.step.itemID))
        #expect(c.resume.identifiants.contains(changements[0].id))
    }

    @Test func resume_valeursSousLaFormeAffichable_commeLeMoteurLesEcrit() {
        let c = Complet()
        let premier = c.plan.steps.first { !$0.fromSnapshot }!
        let couts = premier.costs.filter { $0.amount > 0 }.map { Lisible.cout($0.amount, $0.resource) }
        for cout in couts { #expect(c.resume.texte.contains(cout), "coût écrit comme l'écran : \(cout)") }
        #expect(c.resume.texte.contains("Maintenant : le\u{00A0}" + Lisible.jour(maintenant, now: maintenant, timeZone: fuseau)))
    }

    @Test func resume_neContientNiTagNiExportBrut() {
        let c = Complet()
        let texte = c.resume.texte
        #expect(Réel.export.tag == "#2PP")
        #expect(!texte.contains("#2PP"))
        #expect(!texte.contains("#"))
        for champ in ["\"tag\"", "\"timestamp\"", "\"lvl\"", "\"data\"", "\"cnt\"", "\"timer\"", "\"gear_up\"", "\"helper_cooldown\"", "\"types\"",
                      "\"modules\"", "\"buildings\"", "\"boosts\"", "{", "}", "weapon", "helper_recurrent"] {
            #expect(!texte.contains(champ), "\(champ) ne doit pas partir au modèle")
        }
        // Ni l'export réel inventé plus haut : aucun identifiant du résumé ne sort d'une section brute.
        #expect(texte.count < 6_000, "le résumé reste un résumé (\(texte.count) caractères)")
    }

    @Test func resume_leCorpsEnvoyeAuServiceNeContientNiTagNiExportBrut() async {
        let banc = BancConseiller(reponses: [.ok(GardeFousTests.json("Lance.", []))])
        let c = Complet()
        _ = await banc.conseiller.obtenir(resume: c.resume, cle: "k", reference: reference, now: maintenant)
        let requetes = await banc.transport.requetes
        #expect(requetes.count == 1)
        let corps = String(decoding: requetes[0].httpBody ?? Data(), as: UTF8.self)
        #expect(!corps.contains("#2PP") && !corps.contains("2PP"))
        #expect(!corps.contains("timestamp") && !corps.contains("gear_up") && !corps.contains("helper_cooldown"))
        #expect(corps.contains("Prochaines améliorations"))
    }

    @Test func resume_sansPhotoPrecedente_ledit_etSansChangement() {
        #expect(Complet(changements: nil).resume.texte.contains("Changements depuis la photo précédente : pas de photo précédente."))
        #expect(Complet(changements: []).resume.texte.contains("Changements depuis la photo précédente : aucun."))
    }

    @Test func resume_leChangementVientDeLaPhotoPrecedente() throws {
        // Même village, un Canon au niveau 20 dans la photo d'avant : le changement attendu est « Canon niveau 20 → 21 ».
        let texte = try Fixtures.texte("reel-hdv16")
        let canon = reference.items.first { $0.name == "Canon" }!.id
        let avant = texte.replacingOccurrences(of: "{\"data\":\(canon),\"lvl\":21", with: "{\"data\":\(canon),\"lvl\":20")
        try #require(avant != texte)
        let ancien = Village(export: try VillageExport.parse(avant), reference: reference)
        #expect(Réel.village.changements(depuis: ancien) == [ChangementPhoto(id: canon, depuis: 20, vers: 21)])
    }

    @Test func resume_laConsigneDuMoteurPasseSesPropresGardeFous() {
        // Le résumé contient tout ce que la consigne du moteur dit : si le modèle la recopie, elle est acceptée.
        let decalages: [Double] = [0, 3600 * 5, 86_400, 86_400 * 3, 86_400 * 9]
        for (i, decalage) in decalages.enumerated() {
            let c = Complet(now: Réel.village.date.addingTimeInterval(decalage))
            let texte = c.consigne.split(separator: ".").prefix(3).joined(separator: ".") + "."
            let v = GardeFous.verifier(ReponseConseil(texte: texte, ids: []), resume: c.resume, reference: reference)
            #expect(v == .acceptee(texte), "cas \(i) : \(c.consigne) → \(v)")
        }
    }

    @Test func resume_aucunNombreAccidentel_lesLibellesNeLegitimentRien() {
        // Les nombres du résumé sont ceux du village ; aucun libellé n'en glisse un (« dix prochaines », « sept jours »).
        let c = Complet()
        let libelles = c.resume.texte.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("Consigne") }
            .joined(separator: " ").replacingOccurrences(of: #"\d[\d  ,]*"#, with: "", options: .regularExpression)
        #expect(Nombres.lire(libelles).filter { if case .nombre = $0.valeur { true } else { false } }.isEmpty, "\(Nombres.lire(libelles))")
    }

    // MARK: Le cache

    @Test func cache_rouvrirSansChangement_n_appellePas() async {
        let c = Complet()
        let banc = BancConseiller(reponses: [bonneReponse(c)])
        let k = cle()
        let premier = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant)
        #expect(await banc.transport.requetes.count == 1)
        // Rouvrir l'écran, dix fois, plus tard dans la journée : rien ne repart.
        for i in 1...10 {
            let encore = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant.addingTimeInterval(Double(i) * 60))
            #expect(encore == premier)
        }
        #expect(await banc.transport.requetes.count == 1)
        #expect(premier.estConseil && banc.conseiller.garde(pour: k) != nil)
    }

    @Test func cache_laCleChange_unNouvelAppelParti() async {
        let c = Complet()
        let banc = BancConseiller(reponses: [bonneReponse(c), bonneReponse(c)])
        _ = await banc.conseiller.obtenir(resume: c.resume, cle: cle(), reference: reference, now: maintenant)
        _ = await banc.conseiller.obtenir(resume: c.resume, cle: cle(profil: Profile(orientation: .defense)), reference: reference, now: maintenant)
        #expect(await banc.transport.requetes.count == 2)
    }

    @Test func cache_unEchecEstGarde_pasDeNouvelAppelAvantLeDelai() async {
        let c = Complet()
        let banc = BancConseiller(reponses: [.http(500), bonneReponse(c)])
        let k = cle()
        let a = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant)
        #expect(a == .repli(.erreur(.serviceUnavailable(status: 500))))
        let b = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant.addingTimeInterval(60))
        #expect(b == .repli(.enAttente))
        #expect(await banc.transport.requetes.count == 1)
        let apres = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference,
                                                  now: maintenant.addingTimeInterval(Conseiller.attenteApresEchec + 1))
        #expect(apres.estConseil)
        #expect(await banc.transport.requetes.count == 2)
    }

    @Test func cache_sansCle_rienNestPartiNiGarde() async {
        let c = Complet()
        let banc = BancConseiller(cle: nil, reponses: [])
        let issue = await banc.conseiller.obtenir(resume: c.resume, cle: cle(), reference: reference, now: maintenant)
        #expect(issue == .repli(.erreur(.noKey)))
        #expect(banc.store.load() == nil)
        #expect(await banc.transport.requetes.isEmpty)
    }

    @Test func cache_lesDeuxLanceursDeLaMemeCle_serventLeMemeConseil() async {
        // Un conseil gardé survit à un nouveau `Conseiller` (l'app rouverte) : il est relu dans les préférences.
        let c = Complet()
        let banc = BancConseiller(reponses: [bonneReponse(c)])
        let k = cle()
        let issue = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant)
        let rouvert = BancConseiller.rouvrir(banc)
        #expect(issue.estConseil && rouvert.garde(pour: k) == issue.texte(repli: ""))
        #expect(rouvert.garde(pour: cle(commit: "autre")) == nil)
    }

    // MARK: La clé du conseil

    @Test func cle_dependDeLaPhoto_duProfil_desActions_desVersionsDesDonnees_etDuJour() {
        let base = cle()
        #expect(cle() == base)
        #expect(cle(photo: Réel.village.date.addingTimeInterval(1)) != base)
        #expect(cle(profil: Profile(orientation: .attack)) != base)
        #expect(cle(profil: Profile(heroLimit: 2)) != base)
        #expect(cle(profil: Profile(pinned: [1000008])) != base)
        #expect(cle(profil: Profile(builderReduction: Reduction(percent: 20, endsAt: maintenant.addingTimeInterval(86_400)))) != base)
        #expect(cle(profil: Profile(quietHours: nil)) != base)
        #expect(cle(actions: [1000008]) != base)
        #expect(cle(commit: "def") != base)
        #expect(cle(conseils: "2026-11-10") != base)
        #expect(cle(tz: TimeZone(identifier: "America/New_York")!) != base)
        // Le jour de l'appareil : « demain 14 h » écrit hier serait faux aujourd'hui.
        #expect(cle(now: maintenant.addingTimeInterval(86_400)) != base)
    }

    @Test func cle_nChangePasQuandRienNaChange() {
        let base = cle(profil: Profile(pinned: [3, 1, 2]), actions: [9, 4])
        #expect(cle(profil: Profile(pinned: [1, 2, 3]), actions: [4, 9]) == base)           // l'ordre des ensembles ne compte pas
        #expect(cle(profil: Profile(pinned: [3, 1, 2]), actions: [9, 4], now: maintenant.addingTimeInterval(600)) == base)   // plus tard, le même jour
        #expect(base.count == 32 && base.allSatisfy { $0.isHexDigit })
    }

    // MARK: Pas d'horloge, pas de journal

    @Test func aucuneLectureDeLHorloge_dansLeConseilDuPaquet() throws {
        let dossier = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/ChantierKit/Conseil")
        var lus = 0
        for nom in try FileManager.default.contentsOfDirectory(atPath: dossier.path(percentEncoded: false)) where nom.hasSuffix(".swift") {
            let texte = try String(contentsOf: dossier.appending(path: nom), encoding: .utf8)
            lus += 1
            for interdit in ["Date()", "Date.now", "Calendar.current", "TimeZone.current", "ContinuousClock", "SuspendingClock", "ProcessInfo"] {
                #expect(!texte.contains(interdit), "\(interdit) dans \(nom)")
            }
        }
        #expect(lus >= 7)
    }
}

extension BancConseiller {
    /// Un nouveau `Conseiller` sur les mêmes préférences : l'app rouverte.
    static func rouvrir(_ banc: BancConseiller) -> Conseiller {
        let client = ClaudeClient(keys: MemorySecretStore(BancConseiller.cle), budget: BudgetStore(defaults: UserDefaults(suiteName: "chantier-test-\(UUID().uuidString)")!),
                                  transport: FauxTransport([]), calendar: BancConseiller.calendrier, sleep: { _ in })
        return Conseiller(client: client, store: banc.store)
    }
}
