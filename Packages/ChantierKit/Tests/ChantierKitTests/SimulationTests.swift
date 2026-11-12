import Foundation
import Testing
@testable import ChantierKit

// Simulation et cap (T13) : règles S0 à S5 et S7 du PLAN §5.4, listées en tête de Simulation.swift.
// Villages inventés à l'HDV 3 (aides `Prio` de PrioritesTests), dates en secondes après `Rest.date` (la photo).

enum Sim {
    typealias P = Prio
    static let petHouse = 1000068
    /// Sans heures sans jeu : les calculs de tête restent simples.
    static let free = Profile(quietHours: nil)
    static let utc = TimeZone(identifier: "UTC")!

    static func at(_ seconds: Int) -> Date { Rest.date.addingTimeInterval(TimeInterval(seconds)) }
    static func offset(_ d: Date) -> Int { Int(d.timeIntervalSince(Rest.date)) }

    /// Le village à l'HDV 3, avec `huts` cabanes d'ouvrier.
    static func village(_ items: [ReferenceItem], _ sections: [String: [ExportEntry]], huts: Int = 1) -> (Village, ReferenceData) {
        var s = sections
        s["buildings", default: []].append(P.e(P.hut, 1, huts))
        return P.village(items + [P.item(P.hut, .economy, count: huts, [P.lv(0, 0)])], s)
    }

    static func plan(_ items: [ReferenceItem], _ sections: [String: [ExportEntry]], huts: Int = 1,
                     profile: Profile = free, now: Date = Rest.date, advice: AdviceData = AdviceData(),
                     boosts: [String: Int] = [:]) -> Plan {
        let (v, r) = village(items, sections, huts: huts)
        return makePlan(for: v, reference: r, advice: advice, profile: profile, now: now, boosts: boosts)
    }

    /// « cannon2 0→300 » ; `copy` ajoute « #k » (exemplaire).
    static func label(_ s: ScheduledStep, copy: Bool = false) -> String {
        "\(P.names[s.step.itemID] ?? "#\(s.step.itemID)")\(s.step.level)\(copy ? "#\(s.copy)" : "") \(offset(s.start))→\(offset(s.end))"
    }
    static func labels(_ p: Plan, copy: Bool = false) -> [String] { p.steps.map { label($0, copy: copy) } }

    /// Un niveau à 100 d'or et `d` secondes.
    static func lv(_ d: Int, _ requires: [Requirement] = []) -> (Int?, Int, [Requirement]) { (100, d, requires) }
}

@Suite struct SimulationTests {
    typealias P = Prio
    typealias S = Sim

    // MARK: - Règles

    @Test func S0_photoDeHuitJours_lesPostesSontLibresMaintenantPasALaFinDuMinuteur() {
        // Les deux minuteurs (1 h et 2 h) sont finis depuis huit jours : on relance à `now`, pas dans le passé.
        let items = [P.item(P.cannon, .defenses, [S.lv(10), S.lv(100), S.lv(100)]),
                     P.item(P.king, .heroes, section: "heroes", [S.lv(10), S.lv(50), S.lv(50)])]
        let now = S.at(8 * 86_400)                                     // 691 200 s
        let plan = S.plan(items, ["buildings": [P.e(P.cannon, 1, timer: 3600)], "heroes": [P.e(P.king, 1, timer: 7200)]],
                          huts: 2, now: now)
        #expect(S.labels(plan) == ["cannon2 0→3600", "king2 0→7200", "king3 691200→691250", "cannon3 691200→691300"])
        #expect(plan.steps.prefix(2).allSatisfy { $0.fromSnapshot })
        #expect(plan.steps.allSatisfy { $0.fromSnapshot || $0.start >= now })
        #expect(plan.cap == S.at(691_300))
    }

    @Test func S1_troisHerosEnCoursAvecUneLimiteAUn_lEtatDeDepartEstGarde() {
        let hero = { (id: Int) in P.item(id, .heroes, section: "heroes", [S.lv(10), S.lv(1000), S.lv(1000)]) }
        let items = [hero(P.king), hero(P.queen), hero(P.warden)]
        let heroes = ["heroes": [P.e(P.king, 1, timer: 100), P.e(P.queen, 1, timer: 200), P.e(P.warden, 1, timer: 300)]]
        // Limite à un : les trois minuteurs vont à leur terme ; plus rien ne part avant qu'ils soient tous finis (t = 300),
        // puis un héros à la fois. File : la chaîne la plus longue d'abord (E3) : warden, queen, king.
        let limited = S.plan(items, heroes, huts: 3, profile: Profile(heroLimit: 1, quietHours: nil))
        #expect(S.labels(limited) == ["king2 0→100", "queen2 0→200", "warden2 0→300",
                                      "warden3 300→1300", "queen3 1300→2300", "king3 2300→3300"])
        #expect(limited.heroLimitApplied)
        // Sans limite : chacun repart dès que son minuteur finit ; « au plus tôt ».
        let open = S.plan(items, heroes, huts: 3)
        #expect(S.labels(open).suffix(3) == ["king3 100→1100", "queen3 200→1200", "warden3 300→1300"])
        #expect(!open.heroLimitApplied)
    }

    @Test func S2_unPosteLibreAttendUnPrerequisTenuParUnAutrePoste() {
        // La troupe A 2 exige le labo 2, que l'ouvrier construit de 0 à 500 : le labo, libre, attend 500.
        let items = [P.item(P.lab, .economy, [S.lv(10), S.lv(500)]),
                     P.item(P.troopA, .laboratory, section: "units", worker: .laboratory,
                            [P.lv(nil, 0), P.lv(500, 100, [Requirement(itemID: P.lab, level: 2)])])]
        let plan = S.plan(items, ["buildings": [P.e(P.lab, 1)], "units": [P.e(P.troopA, 1)]])
        #expect(S.labels(plan) == ["lab2 0→500", "A2 500→600"])
    }

    @Test func S2_laLimiteDeHerosSeReappliqueAChaqueEvenement() {
        // Trois ouvriers, un héros à la fois. File (T12) : king2, cannon2, king3, queen2.
        // t = 0 : king2, cannon2 ; le 3e ouvrier ne prend ni king3 (S3) ni queen2 (limite) : il reste libre.
        // t = 100 : king3 ; queen2 attend encore. t = 200 : queen2.
        let items = [P.item(P.king, .heroes, section: "heroes", [S.lv(10), S.lv(100), S.lv(100)]),
                     P.item(P.queen, .heroes, section: "heroes", [S.lv(10), S.lv(100)]),
                     P.item(P.cannon, .defenses, [S.lv(10), S.lv(300)])]
        let plan = S.plan(items, ["buildings": [P.e(P.cannon, 1)], "heroes": [P.e(P.king, 1), P.e(P.queen, 1)]],
                          huts: 3, profile: Profile(heroLimit: 1, quietHours: nil))
        #expect(S.labels(plan) == ["king2 0→100", "cannon2 0→300", "king3 100→200", "queen2 200→300"])
        #expect(plan.heroLimitApplied)
    }

    @Test func S2_unPasNonLancableGardeSaPlace_lOuvrierPrendLeSuivant() {
        // Le cas du Prince des sbires : la file met king2, king3, king4 d'affilée (E3), puis le canon.
        // Le 2e ouvrier ne peut pas lancer king3 (king2 en cours) : il prend le canon au lieu d'attendre.
        let items = [P.item(P.king, .heroes, section: "heroes", [S.lv(10), S.lv(100), S.lv(100), S.lv(100)]),
                     P.item(P.cannon, .defenses, [S.lv(10), S.lv(300)])]
        let plan = S.plan(items, ["buildings": [P.e(P.cannon, 1)], "heroes": [P.e(P.king, 1)]], huts: 2)
        #expect(S.labels(plan) == ["king2 0→100", "cannon2 0→300", "king3 100→200", "king4 200→300"])
    }

    @Test func S3_deuxExemplairesEnParallele_unExemplaireUnNiveauALaFois() {
        // Deux canons au niveau 1 et trois ouvriers : les deux niveaux 2 ensemble, le 3e ouvrier ne prend pas
        // un niveau 3 tant que le niveau 2 du même canon n'est pas fini.
        let items = [P.item(P.cannon, .defenses, count: 2, [S.lv(10), S.lv(100), S.lv(100)])]
        let plan = S.plan(items, ["buildings": [P.e(P.cannon, 1, 2)]], huts: 3)
        #expect(S.labels(plan, copy: true) == ["cannon2#0 0→100", "cannon2#1 0→100", "cannon3#0 100→200", "cannon3#1 100→200"])
        #expect(Set(plan.steps.map(\.lane)) == [0, 1])
    }

    @Test func S4_unLancementDansLesHeuresSansJeuAttendLeurFin() {
        // 23 h → 7 h UTC. Rest.date = 12 janvier 1970, 13 h 46 min 40 s UTC ; minuit = −49 600 s.
        let quiet = Profile(quietHours: QuietHours(start: 23, end: 7, timeZone: S.utc))
        let items = [P.item(P.cannon, .defenses, [S.lv(10), S.lv(3600), S.lv(3600)])]
        let midnight = -49_600, h = 3600
        // Départ à 22 h 30 : le canon 2 finit à 23 h 30 ; le 3 part à 7 h le lendemain.
        let evening = S.plan(items, ["buildings": [P.e(P.cannon, 1)]], profile: quiet, now: S.at(midnight + 22 * h + 1800))
        #expect(S.labels(evening) == ["cannon2 31400→35000", "cannon3 62000→65600"])
        #expect(S.offset(evening.steps[1].start) == midnight + 31 * h)
        // Départ en pleine nuit : rien avant 7 h.
        let night = S.plan(items, ["buildings": [P.e(P.cannon, 1)]], profile: quiet, now: S.at(midnight + 23 * h + 1800))
        #expect(S.offset(night.steps[0].start) == midnight + 31 * h)
        // Une plage qui ne passe pas minuit (1 h → 6 h) et une plage vide.
        let d = Rest.date.addingTimeInterval(TimeInterval(midnight + 2 * h))           // 2 h
        #expect(QuietHours(start: 1, end: 6, timeZone: S.utc).release(d) == d.addingTimeInterval(TimeInterval(4 * h)))
        #expect(QuietHours(start: 3, end: 6, timeZone: S.utc).release(d) == d)
        #expect(QuietHours(start: 5, end: 5, timeZone: S.utc).release(d) == d)
    }

    @Test func S5_lesReductionsSAppliquentAuxLancementsAvantLeurFin() {
        // −50 % pour les ouvriers jusqu'à t = 100 : canon 2 (lancé à 0) et 3 (lancé à 50) durent 50 s et coûtent 50 ;
        // le 4, lancé à 100, quand la réduction est finie, dure 100 s et coûte 100. La réduction du labo n'y change rien.
        let items = [P.item(P.cannon, .defenses, [S.lv(10), S.lv(100), S.lv(100), S.lv(100)])]
        let profile = Profile(builderReduction: Reduction(percent: 50, endsAt: S.at(100)),
                              laboratoryReduction: Reduction(percent: 90, endsAt: S.at(1000)), quietHours: nil)
        let plan = S.plan(items, ["buildings": [P.e(P.cannon, 1)]], profile: profile)
        #expect(S.labels(plan) == ["cannon2 0→50", "cannon3 50→100", "cannon4 100→200"])
        #expect(plan.steps.map { $0.costs.first?.amount } == [50, 50, 100])
        #expect(plan.steps.map(\.reductionPercent) == [50, 50, 0])
    }

    @Test func S7_prerequisImpossible_laSimulationFinitEtRendLesBloquees() {
        // A 2 exige le labo 9 (le labo s'arrête au 1) ; A 3 suit A 2 ; le familier n'a pas de Maison ; limite de héros à 0.
        let items = [P.item(P.lab, .economy, [S.lv(10)]),
                     P.item(P.troopA, .laboratory, section: "units", worker: .laboratory,
                            [P.lv(nil, 0), P.lv(500, 100, [Requirement(itemID: P.lab, level: 9)]), P.lv(500, 100)]),
                     P.item(P.pet, .pets, section: "pets", worker: .petHouse, [P.lv(nil, 0), P.lv(100, 100)]),
                     P.item(P.king, .heroes, section: "heroes", [S.lv(10), S.lv(100)]),
                     P.item(P.cannon, .defenses, [S.lv(10), S.lv(300)])]
        let plan = S.plan(items, ["buildings": [P.e(P.lab, 1), P.e(P.cannon, 1)], "units": [P.e(P.troopA, 1)],
                                  "pets": [P.e(P.pet, 1)], "heroes": [P.e(P.king, 1)]],
                          profile: Profile(heroLimit: 0, quietHours: nil))
        #expect(S.labels(plan) == ["cannon2 0→300"])
        #expect(plan.cap == S.at(300))
        let blocked = plan.blocked.map { "\(P.names[$0.step.itemID]!)\($0.step.level)" }
        #expect(blocked == ["king2", "A2", "A3", "pet2"])
        #expect(plan.blocked.map(\.reason) == [.heroLimit, .requirement(Requirement(itemID: P.lab, level: 9)),
                                               .previousLevel, .noWorker])
    }

    // MARK: - Décisions

    @Test func minuteurIllisible_posteOccupeJusquALaFinLaPlusTardive() {
        // Fin inconnue : l'ouvrier est tenu jusqu'à photo + durée complète du niveau (300 s), puis le canon 3 part.
        let items = [P.item(P.cannon, .defenses, [S.lv(10), S.lv(300), S.lv(100)])]
        let plan = S.plan(items, ["buildings": [ExportEntry(id: P.cannon, level: 1, extras: ["timer": .string("?")])]])
        #expect(S.labels(plan) == ["cannon2 0→300", "cannon3 300→400"])
        #expect(plan.unknownTimers == 1)
    }

    @Test func unPosteConstruitPendantLePlanCompteDesSonNiveau1() {
        // Pas de Maison des familiers (à construire, 200 s) : le familier attend qu'elle existe.
        let items = [P.item(S.petHouse, .economy, [S.lv(200)]),
                     P.item(P.pet, .pets, section: "pets", worker: .petHouse, [P.lv(nil, 0), P.lv(100, 100)])]
        let plan = S.plan(items, ["pets": [P.e(P.pet, 1)]])
        #expect(plan.steps.map(\.step.itemID) == [S.petHouse, P.pet])
        #expect(S.labels(plan).last == "pet2 200→300")                     // Maison des familiers : 0 → 200
    }

    @Test func lePlanDitQuelPosteFinitEnDernier_etSiUnePotionEtaitActive() {
        let items = [P.item(P.lab, .economy, [S.lv(10), S.lv(200)]),
                     P.item(P.troopA, .laboratory, section: "units", worker: .laboratory, [P.lv(nil, 0), P.lv(500, 400)])]
        let sections = ["buildings": [P.e(P.lab, 1)], "units": [P.e(P.troopA, 1)]]
        let plan = S.plan(items, sections, boosts: ["clocktower_cooldown": 70_000, "lab_boost": 3600, "builder_boost": 0])
        #expect(plan.workerEnds == [.builder: S.at(200), .laboratory: S.at(400)])
        #expect(plan.lastWorker == .laboratory && plan.cap == S.at(400))
        #expect(plan.activeBoosts == ["lab_boost"] && plan.potionActive)   // la tour de l'horloge est la base des ouvriers
        #expect(!S.plan(items, sections, boosts: ["clocktower_cooldown": 70_000]).potionActive)
        let empty = S.plan([], [:])
        #expect(empty.cap == nil && empty.lastWorker == nil && empty.steps.isEmpty)
    }

    // MARK: - Trois villages calculés de tête

    @Test func villageDeTete1_deuxOuvriers() {
        // Canon 2 et 3 (300 s chacun), mine 2 (500 s), deux ouvriers, tout en or (E2 ne départage rien).
        // File : canon 2 (chaîne 600 s, E3), mine 2 (500 > 300 restants du canon), canon 3.
        // t = 0 : canon 2 → 300 et mine 2 → 500 ; t = 300 : canon 3 → 600. Cap = 600 = borne basse (chaîne du canon).
        let items = [P.item(P.cannon, .defenses, [S.lv(10), S.lv(300), S.lv(300)]), P.item(P.mine, .economy, [S.lv(10), S.lv(500)])]
        let plan = S.plan(items, ["buildings": [P.e(P.cannon, 1), P.e(P.mine, 1)]], huts: 2)
        #expect(S.labels(plan) == ["cannon2 0→300", "mine2 0→500", "cannon3 300→600"])
        #expect(plan.steps.map(\.lane) == [0, 1, 0])
        #expect(plan.cap == S.at(600) && plan.lastWorker == .builder)
    }

    @Test func villageDeTete2_leLaboAttendLOuvrier() {
        // Un ouvrier monte le labo 2 (200 s). Le labo fait d'abord B 2 (le moins cher, 50 s), puis attend le labo 2
        // pour A 2 (100 s) : 200 → 300. Ouvriers finis à 200, labo à 300 : le labo finit en dernier.
        let items = [P.item(P.lab, .economy, [S.lv(10), S.lv(200)]),
                     P.item(P.troopA, .laboratory, section: "units", worker: .laboratory, resource: .elixir,
                            [P.lv(nil, 0), P.lv(500, 100, [Requirement(itemID: P.lab, level: 2)])]),
                     P.item(P.troopB, .laboratory, section: "units", worker: .laboratory, resource: .elixir,
                            [P.lv(nil, 0), P.lv(10, 50)])]
        let plan = S.plan(items, ["buildings": [P.e(P.lab, 1)], "units": [P.e(P.troopA, 1), P.e(P.troopB, 1)]])
        #expect(S.labels(plan) == ["lab2 0→200", "B2 0→50", "A2 200→300"])
        #expect(plan.workerEnds == [.builder: S.at(200), .laboratory: S.at(300)] && plan.lastWorker == .laboratory)
    }

    @Test func villageDeTete3_unHerosALaFois() {
        // Roi 2, reine 2 (100 s chacun), canon 2 (300 s), deux ouvriers, un héros à la fois.
        // File : roi 2 (P2, E4), canon 2 (la limite est prise : le 2e ouvrier prend autre chose), reine 2.
        // t = 0 : roi → 100, canon → 300 ; t = 100 : reine → 200. Cap 300. Sans limite : roi et reine d'abord,
        // canon de 100 à 400 : la limite donne ici un cap plus tôt.
        let items = [P.item(P.king, .heroes, section: "heroes", [S.lv(10), S.lv(100)]),
                     P.item(P.queen, .heroes, section: "heroes", [S.lv(10), S.lv(100)]),
                     P.item(P.cannon, .defenses, [S.lv(10), S.lv(300)])]
        let sections = ["buildings": [P.e(P.cannon, 1)], "heroes": [P.e(P.king, 1), P.e(P.queen, 1)]]
        let plan = S.plan(items, sections, huts: 2, profile: Profile(heroLimit: 1, quietHours: nil))
        #expect(S.labels(plan) == ["king2 0→100", "cannon2 0→300", "queen2 100→200"])
        #expect(plan.cap == S.at(300) && plan.heroLimitApplied)
        let open = S.plan(items, sections, huts: 2)
        #expect(S.labels(open) == ["king2 0→100", "queen2 0→100", "cannon2 100→400"])
    }

    // MARK: - Propriétés sur des villages aléatoires

    @Test func proprietes_villagesAleatoiresAGraineFixe() {
        for seed in UInt64(1)...200 {
            let (v, r, profile, now) = Aleatoire.village(seed)
            let plan = makePlan(for: v, reference: r, advice: AdviceData(), profile: profile, now: now)
            Aleatoire.verifier(plan, v, r, profile, now, seed: seed)
        }
    }

    // MARK: - Village réel

    @Test func reelHdv16_dateDuCapEtDixPremiersLancements() {
        // Profil par défaut (heures sans jeu 23 h → 7 h, Paris), `now` = date de la photo (11 nov. 2026, 17 h 28 min 2 s).
        let plan = Réel.plan
        #expect(plan.cap == Réel.paris(2028, 11, 30, 7, 0, 0))
        #expect(plan.lastWorker == .laboratory)
        #expect(plan.workerEnds[.builder] == Réel.paris(2027, 3, 21, 9, 11, 55))
        #expect(plan.workerEnds[.petHouse] == Réel.paris(2027, 12, 2, 20, 14, 16))
        #expect(plan.blocked.isEmpty && !plan.heroLimitApplied && !plan.potionActive && plan.unknownTimers == 0)
        #expect(plan.steps.filter(\.fromSnapshot).count == 8)                 // 6 ouvriers, le labo, la Maison des familiers
        // Les dix premiers lancements : (type, niveau, poste, couloir, départ heure de Paris).
        let attendu: [(Int, Int, WorkerKind, Int, [Int])] = [
            (1000068, 9, .builder, 0, [2026, 11, 12, 7, 0, 0]),        // Maison des familiers : forge finie à 2 h 34, nuit
            (1000029, 8, .builder, 1, [2026, 11, 12, 7, 0, 0]),        // Usine de sorts noirs : reine finie à 5 h 52, nuit
            (1000006, 18, .builder, 2, [2026, 11, 12, 8, 14, 55]),     // Caserne : fin du Champion royal
            (73000004, 10, .petHouse, 0, [2026, 11, 12, 20, 14, 16]),  // Phénix : fin de son niveau 9
            (4000110, 2, .laboratory, 0, [2026, 11, 12, 20, 55, 0]),   // fin de la recherche en cours
            (1000059, 8, .builder, 3, [2026, 11, 13, 21, 11, 50]),     // Atelier : fin du 1er Arc-X
            (28000006, 61, .builder, 4, [2026, 11, 13, 21, 11, 55]),   // Prince des sbires : fin du 2e Arc-X
            (28000000, 87, .builder, 5, [2026, 11, 14, 17, 17, 34]),   // Roi : fin de son niveau 86
            (1000068, 10, .builder, 0, [2026, 11, 18, 7, 0, 0]),       // Maison des familiers 9 finie la nuit
            (28000006, 62, .builder, 4, [2026, 11, 18, 21, 11, 55]),   // Prince 61 fini : le 62 suit
        ]
        let launches = Array(plan.steps.filter { !$0.fromSnapshot }.prefix(10))
        #expect(launches.map(\.step.itemID) == attendu.map(\.0))
        #expect(launches.map(\.step.level) == attendu.map(\.1))
        #expect(launches.map(\.worker) == attendu.map(\.2))
        #expect(launches.map(\.lane) == attendu.map(\.3))
        #expect(launches.map(\.start) == attendu.map { Réel.paris($0.4[0], $0.4[1], $0.4[2], $0.4[3], $0.4[4], $0.4[5]) })
    }

    @Test func reelHdv16_capAuDessusDeLaBorneBasse() {
        let b = Aleatoire.bounds(Réel.steps, Réel.village, Profile())
        let cap = Réel.plan.cap!.timeIntervalSince(Réel.export.date)
        // Borne du PLAN §5.4 (ouvriers ÷ 6, plus longue chaîne) et borne par poste (le labo, seul, fait tout à la suite).
        print("reel-hdv16 : cap \(cap / 86_400) j ; borne du PLAN \(Double(b.plan) / 86_400) j ; borne par poste \(Double(b.all) / 86_400) j")
        #expect(cap >= Double(b.all))
        #expect(cap <= Double(b.all) * 1.01)                                  // le labo fixe le cap, à 1 % près
    }

    @Test func memeEntreeMemeSortie_exportMelange() {
        var g = Aleatoire.Graine(state: 7)
        for _ in 0..<3 {
            let e = Réel.export
            let shuffled = VillageExport(tag: e.tag, date: e.date, sections: e.sections.mapValues { $0.shuffled(using: &g) },
                                         idLists: e.idLists, boosts: e.boosts, warnings: e.warnings)
            let v = Village(export: shuffled, reference: Réel.reference)
            #expect(makePlan(for: v, reference: Réel.reference, advice: Réel.advice, profile: Profile(),
                             now: e.date, boosts: e.boosts) == Réel.plan)
        }
    }

    @Test func makePlanSurReelHdv16EnMoinsDe200msDeTempsProcesseur() {
        _ = Réel.plan
        func cpu() -> Double {
            var t = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
            return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6
        }
        let runs = (0..<5).map { _ -> Double in
            let start = cpu()
            _ = makePlan(for: Réel.village, reference: Réel.reference, advice: Réel.advice, profile: Profile(), now: Réel.export.date)
            return cpu() - start
        }.sorted()
        print("makePlan reel-hdv16 : médiane \(runs[2]) ms de processeur, max \(runs[4]) ms sur 5 passages")
        #expect(runs[2] < 200)
    }
}

extension Réel {
    static let plan = makePlan(for: village, reference: reference, advice: advice, profile: Profile(),
                               now: export.date, boosts: export.boosts)
    static func paris(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }
}

/// Villages aléatoires à graine fixe et les propriétés du plan (PLAN §10).
enum Aleatoire {
    typealias P = Prio

    /// SplitMix64 : le même tirage sur toutes les machines.
    struct Graine: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let pool: [(id: Int, category: ChantierKit.Category, section: String, worker: WorkerKind)] = [
        (P.cannon, .defenses, "buildings", .builder), (P.xbow, .defenses, "buildings", .builder),
        (P.inferno, .defenses, "buildings", .builder), (P.mine, .economy, "buildings", .builder),
        (P.camp, .economy, "buildings", .builder), (P.bomb, .traps, "traps", .builder),
        (P.king, .heroes, "heroes", .builder), (P.queen, .heroes, "heroes", .builder), (P.warden, .heroes, "heroes", .builder),
        (P.troopA, .laboratory, "units", .laboratory), (P.troopB, .laboratory, "units", .laboratory),
        (P.troopC, .laboratory, "units", .laboratory), (P.pet, .pets, "pets", .petHouse), (P.pet2, .pets, "pets", .petHouse),
    ]

    static func village(_ seed: UInt64) -> (Village, ReferenceData, Profile, Date) {
        var g = Graine(state: seed)
        func rnd(_ r: ClosedRange<Int>) -> Int { Int.random(in: r, using: &g) }
        let chosen = pool.filter { _ in rnd(0...1) == 1 }
        var maxLevel: [Int: Int] = [P.lab: rnd(1...3)]
        for c in chosen { maxLevel[c.id] = rnd(2...4) }
        let targets = [P.lab] + chosen.map(\.id)
        var items: [ReferenceItem] = []
        var sections: [String: [ExportEntry]] = [:]
        let lab = (id: P.lab, category: ChantierKit.Category.economy, section: "buildings", worker: WorkerKind.builder)
        for c in [lab] + chosen {
            let n = maxLevel[c.id]!
            let unlock = c.worker != .builder                             // niveau 1 d'une troupe ou d'un familier : rien
            let levels = (1...n).map { l -> (Int?, Int, [Requirement]) in
                if unlock, l == 1 { return (nil, 0, []) }
                var req: [Requirement] = []
                let others = targets.filter { $0 != c.id }
                if rnd(0...3) == 0, !others.isEmpty {
                    let t = others[rnd(0...(others.count - 1))]
                    req = [Requirement(itemID: t, level: rnd(1...(maxLevel[t]! + 1)))]   // + 1 : parfois impossible
                }
                return (rnd(0...500), rnd(0...3000), req)
            }
            let count = c.id != P.lab && (c.section == "buildings" || c.section == "traps") ? rnd(1...3) : 1
            items.append(P.item(c.id, c.category, section: c.section, worker: c.worker, count: count, levels))
            let level = rnd(1...n)
            if level < n, rnd(0...9) < 3 {                                // un minuteur, parfois fini à `now`
                sections[c.section, default: []].append(P.e(c.id, level, timer: rnd(0...6000)))
                if count > 1 { sections[c.section, default: []].append(P.e(c.id, level, count - 1)) }
            } else {
                sections[c.section, default: []].append(P.e(c.id, level, count))
            }
        }
        if rnd(0...1) == 1 {
            items.append(P.item(Sim.petHouse, .economy, [P.lv(0, 0)]))
            sections["buildings", default: []].append(P.e(Sim.petHouse, 1))
        }
        let huts = rnd(1...3)
        sections["buildings", default: []].append(P.e(P.hut, 1, huts))
        items.append(P.item(P.hut, .economy, count: huts, [P.lv(0, 0)]))
        let (v, r) = P.village(items, sections)
        let now = Rest.date.addingTimeInterval(TimeInterval(rnd(0...4000)))
        let reduction = rnd(0...2) == 0 ? Reduction(percent: rnd(0...60), endsAt: now.addingTimeInterval(TimeInterval(rnd(0...5000)))) : nil
        let limit = [nil, nil, 0, 1, 2][rnd(0...4)]
        let quiet = rnd(0...1) == 0 ? nil : QuietHours(start: rnd(0...23), end: rnd(0...23), timeZone: Sim.utc)
        return (v, r, Profile(builderReduction: reduction, heroLimit: limit, quietHours: quiet), now)
    }

    /// Bornes basses du cap, en secondes après `now` : celle du PLAN §5.4 (ouvriers ÷ nombre d'ouvriers, plus longue
    /// chaîne d'un exemplaire, héros à faire ÷ limite) et la même avec un terme par poste (labo, familiers : un seul).
    /// Les héros déjà en cours ne comptent pas dans le terme des héros : S1 les laisse tourner ensemble.
    static func bounds(_ steps: [UpgradeStep], _ v: Village, _ profile: Profile, blocked: [BlockedStep] = []) -> (plan: Int, all: Int) {
        // Un exemplaire par pas, sans les niveaux bloqués (S7) : ils ne tournent jamais.
        let out = Set(blocked.map { "\($0.step.element)#\($0.copy)#\($0.step.level)" })
        let timed = steps.filter { $0.category != .walls && $0.worker != .blacksmith }.flatMap { s in
            (0..<s.count).compactMap { k in out.contains("\(s.element)#\(k)#\(s.level)") ? nil : (s, k) }
        }
        func total(_ s: [(UpgradeStep, Int)]) -> Int { s.reduce(0) { $0 + ($1.0.remaining ?? 0) } }
        var chains: [String: Int] = [:]
        for (s, k) in timed { chains["\(s.element)#\(k)", default: 0] += s.remaining ?? 0 }
        // Postes en parallèle : leur nombre, ou plus de minuteurs que de postes dans la photo (S1 les garde tous).
        func lanes(_ w: WorkerKind) -> Int { max(v.workers[w] ?? 0, timed.filter { $0.0.worker == w && $0.0.isInProgress }.count) }
        var plan = chains.values.max() ?? 0
        if lanes(.builder) > 0 { plan = max(plan, total(timed.filter { $0.0.worker == .builder }) / lanes(.builder)) }
        if let limit = profile.heroLimit, limit > 0 {
            plan = max(plan, total(timed.filter { $0.0.category == .heroes && !$0.0.isInProgress }) / limit)
        }
        var all = plan
        for w in [WorkerKind.laboratory, .petHouse] where lanes(w) > 0 {
            all = max(all, total(timed.filter { $0.0.worker == w }) / lanes(w))
        }
        return (plan, all)
    }

    static func verifier(_ plan: Plan, _ v: Village, _ r: ReferenceData, _ profile: Profile, _ now: Date, seed: UInt64) {
        let c = Comment(rawValue: "graine \(seed)")
        // Jamais deux améliorations en même temps sur un couloir ; jamais plus de couloirs que de postes.
        for w in WorkerKind.allCases {
            for lane in Set(plan.steps.filter { $0.worker == w }.map(\.lane)) {
                let l = plan.steps.filter { $0.worker == w && $0.lane == lane }.sorted { $0.start < $1.start }
                #expect(zip(l, l.dropFirst()).allSatisfy { $1.start >= $0.end }, c)
            }
            #expect(plan.steps.filter { $0.worker == w && !$0.fromSnapshot }.allSatisfy { $0.lane < (v.workers[w] ?? 0) }, c)
        }
        // Jamais deux niveaux du même exemplaire en parallèle, et dans l'ordre.
        let copies = Dictionary(grouping: plan.steps) { "\($0.step.element)#\($0.copy)" }
        for (_, l) in copies {
            let s = l.sorted { $0.start < $1.start }
            #expect(zip(s, s.dropFirst()).allSatisfy { $1.start >= $0.end && $1.step.level == $0.step.level + 1 }, c)
        }
        // Prérequis remplis au lancement ; aucun lancement avant `now` ni dans les heures sans jeu.
        for s in plan.steps where !s.fromSnapshot {
            for req in s.step.requires {
                let atStart = v.elements.contains { $0.itemID == req.itemID && $0.level >= req.level }
                    || plan.steps.contains { $0.step.itemID == req.itemID && $0.step.level >= req.level && $0.end <= s.start }
                #expect(atStart, c)
            }
            #expect(s.start >= now, c)
            #expect(profile.quietHours.map { $0.release(s.start) == s.start } ?? true, c)
        }
        // Tout pas à faire est soit lancé, soit bloqué (la simulation s'est terminée sur tout).
        let steps = remainingSteps(of: v, reference: r, profile: profile, now: now)
        let todo = steps.filter { !$0.isInProgress && $0.category != .walls && $0.worker != .blacksmith }.reduce(0) { $0 + $1.count }
        #expect(plan.steps.filter { !$0.fromSnapshot }.count + plan.blocked.count == todo, c)
        // Même entrée, même sortie.
        #expect(makePlan(for: v, reference: r, advice: AdviceData(), profile: profile, now: now) == plan, c)
        // Cap au-dessus de la borne basse, limite de héros comprise.
        let b = bounds(steps, v, profile, blocked: plan.blocked)
        if b.all > 0, let cap = plan.cap { #expect(cap >= now.addingTimeInterval(TimeInterval(b.all)), c) }
    }
}
