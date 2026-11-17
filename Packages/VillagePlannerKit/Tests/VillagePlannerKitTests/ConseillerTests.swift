import Foundation
import Testing
@testable import VillagePlannerKit

// Le résumé, le cache et la clé du conseil (T20). Le village est l'export réel anonymisé `reel-hdv16` (tag factice #2PP).
// Aucun test n'appelle le vrai service : le transport est simulé et compte les appels.

/// Un plan, sa consigne et son résumé, calculés comme l'app le fait.
struct Complet {
    static let fuseau = TimeZone(identifier: "Europe/Paris")!
    static let advice = (try? AdviceData.load()) ?? AdviceData()

    let resume: ResumeConseil
    let plan: Plan
    let consigne: String
    let etat: String

    init(village: Village = Réel.village, export: VillageExport = Réel.export, profil: Profile = Profile(),
         now: Date = Réel.village.date.addingTimeInterval(3600), changements: [ChangementPhoto]? = nil) {
        let reference = Réel.reference
        plan = makePlan(for: village, reference: reference, advice: Self.advice, profile: profil, now: now, boosts: export.boosts,
                        assistants: Assistants(export: export, reference: reference))
        let pas = remainingSteps(of: village, reference: reference, profile: profil, now: now)
        consigne = VillagePlannerKit.consigne(of: plan, photo: village.date, reference: reference, timeZone: Self.fuseau)
        resume = ResumeConseil.make(village: village, rapport: progress(of: village, reference: reference), plan: plan,
                                    besoins: resourceNeeds(of: plan, remaining: pas), profil: profil, reference: reference,
                                    photo: village.date, consigneMoteur: consigne, changements: changements, timeZone: Self.fuseau)
        etat = ResumeConseil.etatDuPlan(plan, reference: reference, photo: village.date)
    }
}

private let reference = Réel.reference
private let maintenant = Réel.village.date.addingTimeInterval(3600)

private func cle(photo: Date = Réel.village.date, profil: Profile = Profile(), actions: [Int] = [], commit: String = "abc", conseils: String = "2026-11-09",
                 etat: String = Complet().etat, now: Date = maintenant, tz: TimeZone = Complet.fuseau) -> String {
    CleConseil.make(photo: photo, profil: profil, actionsLocales: actions, referenceCommit: commit, conseilsDate: conseils, etatDuPlan: etat, now: now, timeZone: tz)
}

/// Une réponse que les garde-fous acceptent : le premier lancement du plan, et le suivant.
private func bonneReponse(_ c: Complet) -> Reponse {
    GardeFousTests.ok(c.resume.candidats[0].id, "elle débloque d'autres améliorations", c.resume.candidats[1].id)
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
        let premier = c.plan.steps.first { !$0.fromSnapshot }!
        let nom = reference.name(of: premier.step.itemID)!
        #expect(texte.contains("(id \(premier.step.itemID)) \(nom) \(premier.step.level)"))
        #expect(texte.contains("lancement " + Lisible.moment(premier.start, now: maintenant, timeZone: Complet.fuseau)))
        #expect(texte.contains("coût"))
        let ameliorations = texte.components(separatedBy: "Prochaines améliorations, dans l'ordre du moteur :\n")[1]
            .split(separator: "\n").prefix { $0.hasPrefix("- (id ") }
        #expect(ameliorations.count == ResumeConseil.ameliorationsMax)
        // Le reste : cap, avancement, profil (en clair), changements, consigne du moteur, choix possibles.
        #expect(texte.contains("Cap : hôtel de ville 16 terminé"))
        #expect(texte.contains("Avancement : total"))
        #expect(texte.contains("Profil : orientation attaque"))
        #expect(texte.contains("limite de héros en amélioration : 1"))
        #expect(texte.contains("épinglés : Arc-X"))
        #expect(texte.contains("Changements depuis la photo précédente :\n- (id \(changements[0].id)) Canon niveau 20 → 21."))
        #expect(texte.contains("Consigne du moteur, à reformuler : " + c.consigne))
        #expect(texte.contains("Ressources à réunir :"))
        #expect(texte.contains("Choix possibles pour « premier » et « ensuite » : (id \(c.resume.candidats[0].id))"))
        #expect(c.resume.candidats.count == ResumeConseil.choixMax)
    }

    @Test func resume_valeursSousLaFormeAffichable_commeLeMoteurLesEcrit() {
        let c = Complet()
        let premier = c.plan.steps.first { !$0.fromSnapshot }!
        for cout in premier.costs.filter({ $0.amount > 0 }).map({ Lisible.cout($0.amount, $0.resource) }) {
            #expect(c.resume.texte.contains(cout), "coût écrit comme l'écran : \(cout)")
        }
        #expect(c.resume.texte.contains("Maintenant : le\u{00A0}" + Lisible.jour(maintenant, now: maintenant, timeZone: Complet.fuseau)))
    }

    @Test func resume_neContientNiTagNiExportBrut() {
        let texte = Complet().resume.texte
        #expect(Réel.export.tag == "#2PP")
        #expect(!texte.contains("#2PP") && !texte.contains("#"))
        for champ in ["\"tag\"", "\"timestamp\"", "\"lvl\"", "\"data\"", "\"cnt\"", "\"timer\"", "\"gear_up\"", "\"helper_cooldown\"", "\"types\"",
                      "\"modules\"", "\"buildings\"", "\"boosts\"", "{", "}", "weapon", "helper_recurrent"] {
            #expect(!texte.contains(champ), "\(champ) ne doit pas partir au modèle")
        }
        #expect(texte.count < 6_000, "le résumé reste un résumé (\(texte.count) caractères)")
    }

    @Test func resume_leCorpsEnvoyeAuServiceNeContientNiTagNiExportBrut() async {
        let c = Complet()
        let banc = BancConseiller(reponses: [bonneReponse(c)])
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

    @Test func consigneComposee_aLaForme_quand_lance_raison_puis_prepare() {
        let c = Complet()
        let (p, e) = (c.resume.candidats[0], c.resume.candidats[1])
        let texte = c.resume.composer(premier: p, raison: "Elle débloque d'autres améliorations", ensuite: e).replacingOccurrences(of: "\u{00A0}", with: " ")
        #expect(texte == "Demain 7 h, lance Animalerie 9 : elle débloque d'autres améliorations. Puis Usine de sorts noirs 8. Prépare 29 M d'élixir.")
        // Un second lancement à une autre heure garde son heure et ne compte pas dans le montant.
        let t = c.resume.candidats[2]
        let autre = c.resume.composer(premier: p, raison: "c'est un héros", ensuite: t).replacingOccurrences(of: "\u{00A0}", with: " ")
        #expect(autre.contains("Puis \(t.nom) \(t.niveau) demain 8 h 15."))
        // « Prépare » couvre tout ce que la consigne cite : l'Animalerie (11 M) et la Caserne (15 M).
        #expect(autre.hasSuffix("Prépare 26 M d'élixir."))
    }

    // MARK: Le cache

    @Test func cache_rouvrirSansChangement_n_appellePas() async {
        let c = Complet()
        let banc = BancConseiller(reponses: [bonneReponse(c)])
        let k = cle()
        let premier = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant)
        #expect(await banc.transport.requetes.count == 1)
        // Rouvrir l'écran, dix fois, plus tard dans la journée, avant le premier lancement : rien ne repart.
        for i in 1...10 {
            let encore = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant.addingTimeInterval(Double(i) * 60))
            #expect(encore == premier)
        }
        #expect(await banc.transport.requetes.count == 1)
        #expect(premier.estConseil && banc.conseiller.garde(pour: k, now: maintenant) != nil)
    }

    @Test func cache_laCleChange_unNouvelAppelParti() async {
        let c = Complet()
        let banc = BancConseiller(reponses: [bonneReponse(c), bonneReponse(c)])
        _ = await banc.conseiller.obtenir(resume: c.resume, cle: cle(), reference: reference, now: maintenant)
        _ = await banc.conseiller.obtenir(resume: c.resume, cle: cle(profil: Profile(orientation: .defense)), reference: reference, now: maintenant)
        #expect(await banc.transport.requetes.count == 2)
    }

    @Test func cache_unConseilDontLePremierPasADejaCommence_nEstPlusMontre() async {
        let c = Complet()
        let banc = BancConseiller(reponses: [bonneReponse(c), bonneReponse(c)])
        let k = cle()
        let issue = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant)
        guard case .conseil(_, let jusqua?) = issue else { Issue.record("pas de conseil daté : \(issue)"); return }
        #expect(jusqua == c.resume.candidats[0].debut)
        #expect(banc.conseiller.garde(pour: k, now: jusqua.addingTimeInterval(-1)) != nil)
        #expect(banc.conseiller.garde(pour: k, now: jusqua) == nil)
        // Même clé, mais le premier lancement a commencé : on redemande au lieu de montrer l'ancien conseil.
        _ = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: jusqua.addingTimeInterval(60))
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
        let apres = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant.addingTimeInterval(Conseiller.attenteApresEchec + 1))
        #expect(apres.estConseil)
        #expect(await banc.transport.requetes.count == 2)
    }

    @Test func cache_sansCle_rienNestPartiNiGarde() async {
        let banc = BancConseiller(cle: nil, reponses: [])
        let issue = await banc.conseiller.obtenir(resume: Complet().resume, cle: cle(), reference: reference, now: maintenant)
        #expect(issue == .repli(.erreur(.noKey)))
        #expect(banc.store.load() == nil)
        #expect(await banc.transport.requetes.isEmpty)
    }

    @Test func cache_unConseilGarde_survitALaReouvertureDeLApp() async {
        let c = Complet()
        let banc = BancConseiller(reponses: [bonneReponse(c)])
        let k = cle()
        let issue = await banc.conseiller.obtenir(resume: c.resume, cle: k, reference: reference, now: maintenant)
        let rouvert = BancConseiller.rouvrir(banc)
        #expect(issue.estConseil && rouvert.garde(pour: k, now: maintenant)?.texte == issue.texte(repli: ""))
        #expect(rouvert.garde(pour: cle(commit: "autre"), now: maintenant) == nil)
    }

    // MARK: La clé du conseil

    @Test func cle_dependDeLaPhoto_duProfil_desActions_desVersionsDesDonnees_duJour_etDeLEtatDuPlan() {
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
        #expect(cle(now: maintenant.addingTimeInterval(86_400)) != base)       // le jour de l'appareil
        #expect(cle(etat: "autre") != base)
    }

    @Test func cle_changeQuandLePremierPasDuPlanChange() {
        // Une heure après la photo, le premier lancement est demain 7 h ; vingt heures après, un poste est libre : le plan a changé.
        let tot = Complet(now: Réel.village.date.addingTimeInterval(3600)), tard = Complet(now: Réel.village.date.addingTimeInterval(20 * 3600))
        #expect(tot.etat != tard.etat)
        #expect(cle(etat: tot.etat) != cle(etat: tard.etat))
        // Un profil qui réordonne les lancements change aussi l'état.
        let attaque = Complet(profil: Profile(orientation: .attack, heroLimit: 1))
        #expect(attaque.resume.candidats.map(\.id) != tot.resume.candidats.map(\.id) ? attaque.etat != tot.etat : true)
        // Retourner au premier plan sans rien changer : même état (un poste libre n'a pas de date).
        let a = Complet(now: Réel.village.date.addingTimeInterval(20 * 3600)), b = Complet(now: Réel.village.date.addingTimeInterval(20 * 3600 + 600))
        #expect(a.etat == b.etat)
    }

    @Test func cle_nChangePasQuandRienNaChange() {
        let base = cle(profil: Profile(pinned: [3, 1, 2]), actions: [9, 4])
        #expect(cle(profil: Profile(pinned: [1, 2, 3]), actions: [4, 9]) == base)           // l'ordre des ensembles ne compte pas
        #expect(cle(profil: Profile(pinned: [3, 1, 2]), actions: [9, 4], now: maintenant.addingTimeInterval(600)) == base)   // plus tard, le même jour
        #expect(base.count == 32 && base.allSatisfy { $0.isHexDigit })
    }

    // MARK: Pas d'horloge, pas de journal

    @Test func aucuneLectureDeLHorloge_dansLeConseilDuPaquet() throws {
        let dossier = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/VillagePlannerKit/Conseil")
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
        let client = ClaudeClient(keys: MemorySecretStore(BancConseiller.cle), budget: BudgetStore(defaults: PreferencesDeTest.neuves()),
                                  transport: FauxTransport([]), calendar: BancConseiller.calendrier, sleep: { _ in })
        return Conseiller(client: client, store: banc.store)
    }
}
