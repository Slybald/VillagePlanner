import Foundation
import Testing
@testable import ChantierKit

// Assistants dans la simulation (T15) : règle S6 du PLAN §5.4, détaillée en tête de Assistants.swift.
// Villages inventés à l'HDV 3 (aides `Prio` et `Sim`), calculés à la main ; dates en secondes après `Rest.date`.
// Un assistant de niveau n : multiplicateur n, un service d'une heure (3 600 s), pause de 23 h (82 800 s après le
// début d'un service, soit 86 400 − 3 600).

enum Aide {
    typealias P = Prio
    typealias S = Sim
    static let apprentice = 93_000_000, labAssistant = 93_000_001, alchemist = 93_000_002
    static let heure = 3600, jour = 23 * 3600
    static let h = 3600

    /// Un assistant de la référence : `levels` = (multiplicateur, secondes de service) du niveau 1, 2, 3…
    static func helper(_ id: Int, _ levels: [(Int, Int)]) -> ReferenceItem {
        ReferenceItem(id: id, names: ["en": "#\(id)"], section: "helpers", category: nil, exclusion: .helper, worker: .builder,
                      levels: levels.enumerated().map { i, l in
                          ReferenceLevel(level: i + 1, costs: [], duration: 0, requires: [], helperMultiplier: l.0, helperSeconds: l.1)
                      },
                      countByTownHall: [0, 1, 1, 1, 1], maxLevelByTownHall: [0, levels.count, levels.count, levels.count, levels.count],
                      mergedFrom: [])
    }
    /// Comme les données : Apprenti et Assistant de labo n × 1 h ; Alchimiste 0 et 4.
    static let helpers = [helper(apprentice, [(1, 3600), (2, 3600), (3, 3600)]),
                          helper(labAssistant, [(1, 3600), (2, 3600), (3, 3600)]),
                          helper(alchemist, [(0, 4), (0, 4), (0, 4)])]

    static func app(_ level: Int, cooldown: Int? = nil) -> Assistants.Helper {
        .init(itemID: apprentice, level: level, cooldown: cooldown)
    }
    static func lab(_ level: Int, cooldown: Int? = nil) -> Assistants.Helper {
        .init(itemID: labAssistant, level: level, cooldown: cooldown)
    }

    static func plan(_ items: [ReferenceItem], _ sections: [String: [ExportEntry]], huts: Int = 1,
                     _ assistants: Assistants = Assistants(), profile: Profile = S.free) -> Plan {
        let (v, r) = S.village(items + helpers, sections, huts: huts)
        return makePlan(for: v, reference: r, advice: AdviceData(), profile: profile, now: Rest.date, assistants: assistants)
    }

    /// Un canon qui passe du niveau 1 aux niveaux 2, 3… de ces durées (en heures).
    static func canon(_ hours: [Int]) -> ReferenceItem {
        P.item(P.cannon, .defenses, [S.lv(10)] + hours.map { S.lv($0 * h) })
    }
    static func services(_ p: Plan) -> [String] {
        p.helperServices.map { "\(P.names[$0.itemID] ?? "#\($0.itemID)")\($0.level) \(S.offset($0.start)) -\($0.savedSeconds)" }
    }
}

@Suite struct AssistantsTests {
    typealias A = Aide
    typealias P = Prio
    typealias S = Sim

    // MARK: - Calcul d'un service

    @Test func S6_unServiceRetireLeMultiplicateurEnHeures_etFinitPlusTotSiLAmeliorationFinitPendant() {
        // Niveau 2 (× 2) sur 100 h : retire 2 h. Sur 1 h 30 : le service dure 30 min (90 min ÷ 3).
        #expect(helperRemaining(100 * 3600, service: 3600, multiplier: 2) == 100 * 3600 - 7200)
        #expect(helperRemaining(5400, service: 3600, multiplier: 2) == 1800)
        // Au seuil des deux formules : 3 600 × (1 + 2) = 10 800 s restantes → 3 600 s.
        #expect(helperRemaining(10_800, service: 3600, multiplier: 2) == 3600)
        #expect(helperRemaining(10_801, service: 3600, multiplier: 2) == 3601)
        // Multiplicateur nul (l'Alchimiste), service nul, rien à faire : aucun changement.
        #expect(helperRemaining(5400, service: 4, multiplier: 0) == 5400)
        #expect(helperRemaining(5400, service: 0, multiplier: 3) == 5400)
        #expect(helperRemaining(0, service: 3600, multiplier: 3) == 0)
    }

    // MARK: - Les améliorations futures

    @Test func S6b_unApprentiNiveau2SurDeuxCanons_calculDeTete() {
        // Un ouvrier, un canon 1 → 2 → 3 (100 h puis 50 h), Apprenti niveau 2 (retire 2 h), libre à la photo.
        // Sans lui : canon2 0 → 360 000 s (100 h), canon3 360 000 → 540 000 s (50 h), cap à 150 h.
        // Avec lui, canon2 (lancé à 0, services toutes les 82 800 s tant qu'il dure) :
        //   service 1 à 0        : 360 000 → 352 800
        //   service 2 à 82 800   : 352 800 → 345 600
        //   service 3 à 165 600  : 345 600 → 338 400
        //   service 4 à 248 400  : 338 400 → 331 200
        //   service 5 à 331 200  : pas de service, la fin (331 200) est atteinte ; libre à 248 400 + 82 800 = 331 200.
        // canon3 part à 331 200 et l'Apprenti est libre : 331 200 + 180 000 = 511 200, puis
        //   service 1 à 331 200  : 511 200 → 504 000
        //   service 2 à 414 000  : 504 000 → 496 800
        //   service 3 à 496 800  : fin atteinte, pas de service.
        // Cap : 496 800 s (138 h), soit 12 h de moins que sans assistant.
        let items = [A.canon([100, 50])]
        let sections = ["buildings": [P.e(P.cannon, 1)]]
        let sans = A.plan(items, sections)
        #expect(S.labels(sans) == ["cannon2 0→360000", "cannon3 360000→540000"])
        let avec = A.plan(items, sections, Assistants(helpers: [A.app(2)]))
        #expect(S.labels(avec) == ["cannon2 0→331200", "cannon3 331200→496800"])
        #expect(avec.cap == S.at(496_800))
        #expect(A.services(avec) == ["cannon2 0 -7200", "cannon2 82800 -7200", "cannon2 165600 -7200", "cannon2 248400 -7200",
                                     "cannon3 331200 -7200", "cannon3 414000 -7200"])
        #expect(sans.cap!.timeIntervalSince(avec.cap!) == 12 * 3600)
    }

    @Test func S6b_laPauseDe23hSEntreDeuxServices_pasUnServiceParHeure() {
        // Même village que ci-dessus : un service toutes les 82 800 s (23 h) et pas toutes les 3 600 s. Une pause
        // ignorée donnerait un service à chaque heure et une fin bien plus tôt.
        let avec = A.plan([A.canon([100])], ["buildings": [P.e(P.cannon, 1)]], Assistants(helpers: [A.app(2)]))
        let starts = avec.helperServices.map { S.offset($0.start) }
        #expect(starts == [0, 82_800, 165_600, 248_400])
        #expect(zip(starts, starts.dropFirst()).allSatisfy { $1 - $0 == helperWorkday })
        #expect(helperWorkday == 23 * 3600)
    }

    @Test func S6b_l_assistantPrendLAmeliorationLaPlusLongueDeSonPoste() {
        // Deux ouvriers, deux améliorations lancées ensemble : un canon de 100 h et un Arc-X de 40 h.
        // L'Apprenti (niveau 2) prend celle qui finit le plus tard : le canon, jusqu'à sa fin (331 200 s) ;
        // l'Arc-X (40 h = 144 000 s) n'est pas touché.
        let items = [A.canon([100]), P.item(P.xbow, .defenses, [S.lv(10), S.lv(40 * A.h)])]
        let sections = ["buildings": [P.e(P.cannon, 1), P.e(P.xbow, 1)]]
        let p = A.plan(items, sections, huts: 2, Assistants(helpers: [A.app(2)]))
        #expect(S.labels(p) == ["cannon2 0→331200", "xbow2 0→144000"])
        #expect(p.helperServices.allSatisfy { $0.itemID == P.cannon })
        #expect(p.helperServices.count == 4)
    }

    @Test func S6b_unAssistantLibreAttendUneAmeliorationAAider() {
        // Le labo est inactif (rien à rechercher) : l'Assistant de labo ne sert à personne, le plan ne change pas.
        let items = [A.canon([100])]
        let sections = ["buildings": [P.e(P.cannon, 1)]]
        let sans = A.plan(items, sections)
        let avec = A.plan(items, sections, Assistants(helpers: [A.lab(3)]))
        #expect(avec == sans)
        #expect(avec.helperServices.isEmpty)
    }

    // MARK: - Heures sans jeu

    @Test func S6c_unAssistantNEstJamaisAffectePendantLesHeuresSansJeu_maisSesServicesGardesTombentLaNuit() {
        // La photo est à 13 h 46 min 40 s (UTC) ; heures sans jeu de 15 h à 20 h pour que les durées restent
        // lisibles. L'Apprenti (niveau 2) est en pause pendant 8 000 s : libre à 16 h 00 min 00 s, en pleine plage.
        // Il ne peut être affecté qu'à la fin de la plage, 20 h 00 : 6 h 13 min 20 s après la photo = 22 400 s.
        // Ses services suivants, affectation gardée, suivent la pause de 23 h : 22 400 + 82 800 = 105 200 s, soit
        // 19 h 00 le lendemain, dans la plage : permis (aucun geste).
        let quiet = Profile(quietHours: QuietHours(start: 15, end: 20, timeZone: S.utc))
        let p = A.plan([A.canon([90])], ["buildings": [P.e(P.cannon, 1)]],
                       Assistants(helpers: [A.app(2, cooldown: 8000)]), profile: quiet)
        #expect(p.helperServices.map { S.offset($0.start) } == [22_400, 105_200, 188_000, 270_800])
        // Le lancement du canon, lui, a lieu à la photo (13 h 46, hors plage).
        #expect(S.labels(p) == ["cannon2 0→295200"])
        // L'affectation (le premier service) est hors plage : 20 h exactement.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = S.utc
        let first = p.helperServices[0].start
        #expect(calendar.component(.hour, from: first) == 20 && calendar.component(.minute, from: first) == 0)
    }

    // MARK: - La photo

    @Test func S6a_helperTimer_leServiceEnCoursRaccourcitLeMinuteurExporte() {
        // Canon en cours, minuteur exporté 36 000 s (10 h), l'Apprenti (niveau 2) a encore 1 800 s de service.
        // Pendant ces 1 800 s l'amélioration avance 3 fois plus vite : elle gagne 1 800 × 2 = 3 600 s.
        // Fin : 36 000 − 3 600 = 32 400 s. Pause de 80 000 s : pas d'autre service.
        let ends = S.at(36_000)
        let a = Assistants(helpers: [A.app(2, cooldown: 80_000)],
                           assignments: [.init(helperID: A.apprentice, itemID: P.cannon, level: 1, ends: ends,
                                               recurrent: false, timer: 1800)])
        let p = A.plan([A.canon([100])], ["buildings": [P.e(P.cannon, 1, timer: 36_000)]], a)
        #expect(S.labels(p) == ["cannon2 0→32400"])
        #expect(p.steps[0].fromSnapshot)
        #expect(A.services(p) == ["cannon2 0 -3600"])
        // Sans l'affectation dans la photo, le minuteur est celui de l'export.
        let sans = A.plan([A.canon([100])], ["buildings": [P.e(P.cannon, 1, timer: 36_000)]],
                          Assistants(helpers: [A.app(2, cooldown: 80_000)]))
        #expect(S.labels(sans) == ["cannon2 0→36000"])
    }

    @Test func S6a_helperRecurrent_l_assistantReprendSeulALaFinDeLaPause_memeLaNuit() {
        // Canon en cours, minuteur 360 000 s (100 h), Apprenti niveau 2 « gardé affecté », pause restante 7 200 s.
        // Heures sans jeu 15 h → 20 h (la photo est à 13 h 46 min 40 s) : le premier service tombe à 7 200 s,
        // soit 15 h 46 min 40 s, en pleine plage, et c'est permis : aucun geste, l'affectation est gardée.
        //   7 200 : 360 000 → 352 800 ; 90 000 : → 345 600 ; 172 800 : → 338 400 ; 255 600 : → 331 200 ;
        //   338 400 > 331 200 : fini.
        let quiet = Profile(quietHours: QuietHours(start: 15, end: 20, timeZone: S.utc))
        let a = Assistants(helpers: [A.app(2, cooldown: 7200)],
                           assignments: [.init(helperID: A.apprentice, itemID: P.cannon, level: 1, ends: S.at(360_000),
                                               recurrent: true)])
        let p = A.plan([A.canon([100])], ["buildings": [P.e(P.cannon, 1, timer: 360_000)]], a, profile: quiet)
        #expect(S.labels(p) == ["cannon2 0→331200"])
        #expect(p.helperServices.map { S.offset($0.start) } == [7200, 90_000, 172_800, 255_600])
        #expect(p.helperServices.allSatisfy { $0.savedSeconds == 7200 })
    }

    @Test func S6a_helperCooldown_unAssistantSansAffectationNeSertPasAvantLaFinDeSaPause() {
        // Pas d'affectation dans la photo ; pause de 8 000 s. Le canon est lancé à 0 (100 h), l'Apprenti ne le prend
        // qu'à 8 000 s : services à 8 000, 90 800, 173 600, 256 400 (toutes les 82 800 s), fin à 331 200 s.
        let p = A.plan([A.canon([100])], ["buildings": [P.e(P.cannon, 1)]], Assistants(helpers: [A.app(2, cooldown: 8000)]))
        #expect(S.offset(p.helperServices[0].start) == 8000)
        #expect(p.helperServices.map { S.offset($0.start) } == [8000, 90_800, 173_600, 256_400])
        #expect(S.labels(p) == ["cannon2 0→331200"])
    }

    // MARK: - Qui aide quoi

    @Test func S6d_lAlchimisteNeChangeAucuneDate() {
        let items = [A.canon([100, 50])]
        let sections = ["buildings": [P.e(P.cannon, 1)]]
        let sans = A.plan(items, sections)
        let avec = A.plan(items, sections, Assistants(helpers: [.init(itemID: A.alchemist, level: 3, cooldown: 1000)]))
        #expect(avec == sans)
        #expect(avec.helperServices.isEmpty)
        // Même affecté par une ligne d'export, il ne raccourcit rien.
        let force = A.plan(items, sections, Assistants(helpers: [.init(itemID: A.alchemist, level: 3)],
                                                       assignments: [.init(helperID: A.alchemist, itemID: P.cannon, level: 1,
                                                                           ends: nil, recurrent: true, timer: 100)]))
        #expect(force == sans)
    }

    @Test func S6d_unAssistantAbsentDeLExportNAidePersonne() {
        // Des affectations sans l'assistant dans `helpers` (pas recruté) : le plan est celui sans assistant.
        let items = [A.canon([100])]
        let sections = ["buildings": [P.e(P.cannon, 1, timer: 36_000)]]
        let sans = A.plan(items, sections)
        let a = Assistants(helpers: [], assignments: [.init(helperID: A.apprentice, itemID: P.cannon, level: 1, ends: S.at(36_000),
                                                            recurrent: true, timer: 1800)])
        #expect(A.plan(items, sections, a) == sans)
    }

    @Test func S6d_lAssistantDeLaboNAidePasLesOuvriersNiLaMaisonDesFamiliers() {
        // Un canon (ouvrier) et un familier (Maison des familiers) en amélioration : un Assistant de labo ne change rien.
        let items = [A.canon([100]),
                     P.item(P.pet, .pets, section: "pets", worker: .petHouse, [P.lv(nil, 0), P.lv(10, 100 * A.h)]),
                     P.item(S.petHouse, .economy, [P.lv(0, 0)])]
        let sections = ["buildings": [P.e(P.cannon, 1), P.e(S.petHouse, 1)], "pets": [P.e(P.pet, 1)]]
        let sans = A.plan(items, sections)
        let avec = A.plan(items, sections, Assistants(helpers: [A.lab(3)]))
        #expect(avec == sans && avec.helperServices.isEmpty)
        #expect(sans.steps.count == 2)
    }

    @Test func S6d_l_assistantDeLaboAideLeLabo_etLApprentiNeLAidePas() {
        // Une recherche de 100 h au labo (un seul ouvrier, un canon aussi) : l'Assistant de labo (niveau 3, retire 3 h)
        // la raccourcit, l'Apprenti seul non.
        let items = [A.canon([100]),
                     P.item(P.troopA, .laboratory, section: "units", worker: .laboratory, [P.lv(nil, 0), P.lv(10, 100 * A.h)]),
                     P.item(P.lab, .economy, [P.lv(0, 0)])]
        let sections = ["units": [P.e(P.troopA, 1)], "buildings": [P.e(P.lab, 1)]]
        let sans = A.plan(items, sections)
        let lab = A.plan(items, sections, Assistants(helpers: [A.lab(3)]))
        #expect(lab.helperServices.allSatisfy { $0.itemID == P.troopA } && !lab.helperServices.isEmpty)
        #expect(lab.workerEnds[.laboratory]! < sans.workerEnds[.laboratory]!)
        let app = A.plan(items, sections, Assistants(helpers: [A.app(3)]))
        #expect(app.workerEnds[.laboratory] == sans.workerEnds[.laboratory])
    }

    // MARK: - L'export

    @Test func S6_lectureDeLExport_helperTimerRecurrentEtCooldown() {
        let ref = ReferenceData(items: [P.thItem, A.canon([100]), P.item(P.troopA, .laboratory, section: "units", worker: .laboratory,
                                                                          [P.lv(nil, 0), P.lv(10, 100)])] + A.helpers, maxTownHall: 3)
        let on = JSONValue.bool(true)
        let entries: [String: [ExportEntry]] = [
            "buildings": [ExportEntry(id: P.th, level: 3),
                          ExportEntry(id: P.cannon, level: 1, timer: 5000,
                                      extras: ["helper_recurrent": on, "helper_timer": .number(1800)])],
            // Affectation sans amélioration en cours : ignorée.
            "units": [ExportEntry(id: P.troopA, level: 1, extras: ["helper_recurrent": on])],
            "helpers": [ExportEntry(id: A.apprentice, level: 2, extras: ["helper_cooldown": .number(9790)]),
                        ExportEntry(id: A.alchemist, level: 3)],
        ]
        let export = VillageExport(tag: "#2PP", date: Rest.date, sections: entries, idLists: [:], boosts: [:], warnings: [])
        let a = Assistants(export: export, reference: ref)
        #expect(a.helpers == [.init(itemID: A.apprentice, level: 2, cooldown: 9790), .init(itemID: A.alchemist, level: 3, cooldown: nil)])
        #expect(a.assignments == [.init(helperID: A.apprentice, itemID: P.cannon, level: 1, ends: S.at(5000),
                                        recurrent: true, timer: 1800)])
    }

    // MARK: - Village réel

    @Test func reelHdv16_assistantsRetires_onRetombeSurLAncienCap() {
        // Sans assistant (T13) : cap le 30 nov. 2028 à 7 h 00, poste de fin : le labo.
        let sans = makePlan(for: Réel.village, reference: Réel.reference, advice: Réel.advice, profile: Profile(),
                            now: Réel.export.date, boosts: Réel.export.boosts, assistants: Assistants())
        #expect(sans == Réel.plan)
        #expect(sans.cap == Réel.paris(2028, 11, 30, 7, 0, 0))
        #expect(sans.helperServices.isEmpty)
        // Un export dont on a retiré la section `helpers` et les champs `helper_*` donne le même plan.
        let nu = VillageExport(tag: Réel.export.tag, date: Réel.export.date,
                               sections: Réel.export.sections.filter { $0.key != "helpers" }.mapValues { entries in
                                   entries.map { ExportEntry(id: $0.id, level: $0.level, count: $0.count, timer: $0.timer,
                                                             extras: $0.extras.filter { !$0.key.hasPrefix("helper_") },
                                                             children: $0.children) }
                               },
                               idLists: Réel.export.idLists, boosts: Réel.export.boosts, warnings: Réel.export.warnings)
        #expect(Assistants(export: nu, reference: Réel.reference) == Assistants())
    }

    @Test func reelHdv16_gainDeLApprentiSurLeRoiOuLaReine_calculDeTete() {
        // 28000001 (héros), niveau 92 → 93, minuteur 44 641 s, Apprenti niveau 4 (retire 4 h), gardé affecté, pause 9 790 s.
        //   service à 9 790 s : restent 44 641 − 9 790 = 34 851 s > 3 600 × 5 = 18 000 s : le service retire 4 × 3 600 = 14 400 s ;
        //   fin : 44 641 − 14 400 = 30 241 s ; prochain service à 9 790 + 82 800 = 92 590 s : après la fin.
        // Assistant de labo niveau 1 sur 4000017 (troupe 6 → 7), minuteur 98 818 s :
        //   service à 9 790 s : restent 89 028 s : retire 3 600 s → fin 95 218 s ;
        //   service à 92 590 s : restent 2 628 s ≤ 3 600 × 2 : le service finit en 2 628 ÷ 2 = 1 314 s → fin 93 904 s.
        let a = Assistants(export: Réel.export, reference: Réel.reference)
        #expect(a.helpers.map(\.itemID) == [93_000_000, 93_000_001, 93_000_002])
        #expect(a.helpers.map(\.level) == [4, 1, 5] && a.helpers.allSatisfy { $0.cooldown == 9790 })
        #expect(a.assignments.count == 2 && a.assignments.allSatisfy(\.recurrent))
        let p = Réel.planAvecAssistants
        let t0 = Réel.export.date
        func end(_ id: Int) -> Int { Int(p.steps.first { $0.fromSnapshot && $0.step.itemID == id }!.end.timeIntervalSince(t0)) }
        #expect(end(28_000_001) == 30_241)
        #expect(end(4_000_017) == 93_904)
        let services = p.helperServices.prefix(3).map { ($0.itemID, Int($0.start.timeIntervalSince(t0)), $0.savedSeconds) }
        #expect(services.map(\.0) == [28_000_001, 4_000_017, 4_000_017])
        #expect(services.map(\.1) == [9790, 9790, 92_590] && services.map(\.2) == [14_400, 3600, 1314])
    }

    @Test func reelHdv16_nouveauCapAvecLesAssistantsDeLExport() {
        let p = Réel.planAvecAssistants
        let ancien = Réel.paris(2028, 11, 30, 7, 0, 0)
        for id in [A.apprentice, A.labAssistant] {
            let s = p.helperServices.filter { $0.helper == id }
            print("reel-hdv16 assistant \(id) : \(s.count) services, \(s.reduce(0) { $0 + $1.savedSeconds } / 3600) h gagnées")
        }
        print("reel-hdv16 avec assistants : cap \(p.cap!), poste de fin \(String(describing: p.lastWorker)), ancien \(ancien)")
        for w in [WorkerKind.builder, .laboratory, .petHouse] { print("  fin \(w) : \(String(describing: p.workerEnds[w])) (avant \(String(describing: Réel.plan.workerEnds[w])))") }
        #expect(p.cap == Réel.paris(2028, 11, 10, 7, 0, 0))
        #expect(p.cap! < ancien)
        #expect(p.lastWorker == .laboratory)
        #expect(p.blocked.isEmpty && p.unknownTimers == 0)
        #expect(p.steps.allSatisfy { $0.end >= $0.start })
        // Aucune amélioration lancée dans les heures sans jeu (S4), assistants compris.
        let quiet = QuietHours.default
        #expect(p.steps.filter { !$0.fromSnapshot }.allSatisfy { quiet.release($0.start) == $0.start })
    }

    @Test func S6_memeEntreeMemeSortie_exportMelangeAvecAssistants() {
        var g = Aleatoire.Graine(state: 11)
        let e = Réel.export
        for _ in 0..<2 {
            let shuffled = VillageExport(tag: e.tag, date: e.date, sections: e.sections.mapValues { $0.shuffled(using: &g) },
                                         idLists: e.idLists, boosts: e.boosts, warnings: e.warnings)
            let v = Village(export: shuffled, reference: Réel.reference)
            let a = Assistants(export: shuffled, reference: Réel.reference)
            #expect(makePlan(for: v, reference: Réel.reference, advice: Réel.advice, profile: Profile(), now: e.date,
                             boosts: e.boosts, assistants: a) == Réel.planAvecAssistants)
        }
    }
}

extension Réel {
    static let planAvecAssistants = makePlan(for: village, reference: reference, advice: advice, profile: Profile(),
                                             now: export.date, boosts: export.boosts,
                                             assistants: Assistants(export: export, reference: reference))
}
