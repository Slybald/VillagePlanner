import Foundation
import Testing
@testable import ChantierKit

// Ressources à réunir (T14) : règles R1, R2, R3 du PLAN §5.5, listées en tête de Ressources.swift.
// Villages inventés à l'HDV 3 (aides de SimulationTests) : un canon à améliorer niveau par niveau, un seul ouvrier,
// sans heures sans jeu. Dates en secondes après `Rest.date` (la photo), jours de 86 400 s.

enum Ress {
    typealias P = Prio
    typealias S = Sim
    static let day = 86_400

    /// Canon niveau 1 avec des niveaux à `costs[i]` d'or et `days` jours chacun (un ouvrier : un lancement tous les `days` jours).
    static func cannon(_ costs: [Int], days: Int = 2) -> ReferenceItem {
        P.item(P.cannon, .defenses, [P.lv(100, 10)] + costs.map { P.lv($0, days * day) })
    }

    /// Les murs : `count` morceaux au niveau 1, un niveau à `cost` d'or chacun (durée nulle : P6).
    static func walls(count: Int, cost: Int) -> ReferenceItem {
        P.item(P.wall, .walls, count: count, [P.lv(300, 0), P.lv(cost, 0)])
    }

    static func needs(_ items: [ReferenceItem], _ sections: [String: [ExportEntry]], huts: Int = 1, now: Date = Rest.date,
                      profile: Profile = S.free) -> (plan: Plan, needs: [ResourceNeed]) {
        let (v, r) = S.village(items, sections, huts: huts)
        let plan = makePlan(for: v, reference: r, advice: AdviceData(), profile: profile, now: now)
        return (plan, resourceNeeds(of: plan, remaining: remainingSteps(of: v, reference: r, profile: profile, now: now)))
    }

    static func gold(_ needs: [ResourceNeed]) -> ResourceNeed? { needs.first { $0.resource == .gold } }
}

@Suite struct RessourcesTests {
    typealias P = Prio
    typealias S = Sim
    typealias R = Ress

    static let canon: [String: [ExportEntry]] = ["buildings": [P.e(P.cannon, 1)]]

    // MARK: - Règles

    @Test func R1_laProchaineEcheanceEtLesDeuxSuivantes() {
        // Canon 2 à 6 : 100, 200, 300, 400, 500 d'or, 2 j chacun, lancés à 0, 2 j, 4 j, 6 j, 8 j.
        // Trois échéances seulement : la quatrième (400 à 6 j) n'en fait pas partie ; la première est à `now`.
        let gold = R.gold(R.needs([R.cannon([100, 200, 300, 400, 500])], Self.canon).needs)
        #expect(gold?.dues == [.init(date: S.at(0), amount: 100), .init(date: S.at(2 * R.day), amount: 200),
                               .init(date: S.at(4 * R.day), amount: 300)])
    }

    @Test func R1_plusieursLancementsAuMemeInstantFontUneSeuleEcheance() {
        // Deux ouvriers, deux canons de types différents lancés ensemble : 100 + 50 = 150 à `now`, puis 100 à 2 j.
        let items = [R.cannon([100, 100]), P.item(P.xbow, .defenses, [P.lv(100, 10), P.lv(50, 2 * R.day)])]
        let gold = R.gold(R.needs(items, ["buildings": [P.e(P.cannon, 1), P.e(P.xbow, 1)]], huts: 2).needs)
        #expect(gold?.dues == [.init(date: S.at(0), amount: 150), .init(date: S.at(2 * R.day), amount: 100)])
    }

    @Test func R1_chaqueRessourceAsesEcheances() {
        // Le canon coûte de l'or, la troupe de l'élixir (labo) : deux entrées, dans l'ordre de `Resource.allCases`.
        let items = [P.item(P.lab, .economy, [P.lv(0, 0)]),
                     P.item(P.troopA, .laboratory, section: "units", worker: .laboratory, resource: .elixir,
                            [P.lv(nil, 0), P.lv(500, 100)]),
                     R.cannon([100])]
        let needs = R.needs(items, ["buildings": [P.e(P.cannon, 1), P.e(P.lab, 1)], "units": [P.e(P.troopA, 1)]]).needs
        #expect(needs.map(\.resource) == [.gold, .elixir])
        #expect(needs[0].dues == [.init(date: S.at(0), amount: 100)] && needs[1].dues == [.init(date: S.at(0), amount: 500)])
    }

    @Test func R1_unMinuteurDeLaPhotoNEstPasUneEcheance() {
        // Le canon 2 est en cours dans la photo (déjà payé) ; seul le 3 est à payer, à la fin du minuteur (1 j).
        let items = [R.cannon([100, 200])]
        let r = R.needs(items, ["buildings": [P.e(P.cannon, 1, timer: R.day)]])
        #expect(R.gold(r.needs)?.dues == [.init(date: S.at(R.day), amount: 200)])
    }

    @Test func R2_leRythmeEstLaSommeDesSeptProchainsJoursDivisee_par7() {
        // Lancements à 0, 2 j, 4 j, 6 j (100 + 200 + 300 + 400 = 1000) ; celui de 8 j (500) est hors semaine.
        // 1000 ÷ 7 = 142,86 : arrondi à 143 par jour.
        let gold = R.gold(R.needs([R.cannon([100, 200, 300, 400, 500])], Self.canon).needs)
        #expect(gold?.weekTotal == 1000)
        #expect(gold?.perDay == 143)
    }

    @Test func R2_unLancementPileASeptJoursEstDansLaSemaineSuivante() {
        // Niveaux de 7 jours : lancements à 0 (100) et à 7 j pile (200, hors de [0, 7 j[). 100 ÷ 7 = 14,3 : 15.
        let gold = R.gold(R.needs([R.cannon([100, 200], days: 7)], Self.canon).needs)
        #expect(gold?.weekTotal == 100 && gold?.perDay == 15)
        #expect(gold?.dues.count == 2)                                   // l'échéance de 7 j existe quand même (R1)
    }

    @Test func R2_unRythmeEntierNEstPasArrondi() {
        // Une seule échéance de 700 : 700 ÷ 7 = 100 pile.
        let gold = R.gold(R.needs([R.cannon([700])], Self.canon).needs)
        #expect(gold?.weekTotal == 700 && gold?.perDay == 100)
    }

    @Test func R3_lesMursFinissentAvecLeCap() {
        // 3 murs au niveau 1, niveau 2 à 500 : 1 500 d'or. Le cap est à 10 j (5 niveaux de 2 j) : 150 par jour.
        let items = [R.cannon([100, 200, 300, 400, 500]), R.walls(count: 3, cost: 500)]
        let gold = R.gold(R.needs(items, ["buildings": [P.e(P.cannon, 1), P.e(P.wall, 1, 3)]]).needs)
        #expect(gold?.wallsRemaining == 1500)
        #expect(gold?.wallsPerDay == 150)
        #expect(gold?.wallsEnd == S.at(10 * R.day))
        // Le rythme des murs s'ajoute à celui des ouvriers sans le changer (le mur n'entre pas dans la file, P6).
        #expect(gold?.weekTotal == 1000 && gold?.perDay == 143)
    }

    @Test func R3_moinsDUnJourAvantLeCap_onCompteUnJour() {
        // Le cap est dans 1 h : les 1 500 d'or de murs se paient en « un jour », pas 24 fois plus vite.
        let items = [P.item(P.cannon, .defenses, [P.lv(100, 10), P.lv(100, 3600)]), R.walls(count: 3, cost: 500)]
        let gold = R.gold(R.needs(items, ["buildings": [P.e(P.cannon, 1), P.e(P.wall, 1, 3)]]).needs)
        #expect(gold?.wallsPerDay == 1500)
    }

    @Test func R3_leRythmeEstArrondiAuDessus() {
        // 1 000 d'or de murs, cap à 3 j : 333,33 par jour, 334 pour finir à temps.
        let items = [P.item(P.cannon, .defenses, [P.lv(100, 10), P.lv(100, 3 * R.day)]), R.walls(count: 2, cost: 500)]
        let gold = R.gold(R.needs(items, ["buildings": [P.e(P.cannon, 1), P.e(P.wall, 1, 2)]]).needs)
        #expect(gold?.wallsRemaining == 1000 && gold?.wallsPerDay == 334)
    }

    @Test func R3_sansCapLesMursGardentLeurCoutMaisPasDeRythme() {
        // Rien d'autre à faire : pas de cap, donc pas de date où finir les murs.
        let r = R.needs([R.walls(count: 3, cost: 500)], ["buildings": [P.e(P.wall, 1, 3)]])
        #expect(r.plan.cap == nil)
        let gold = R.gold(r.needs)
        #expect(gold?.wallsRemaining == 1500 && gold?.wallsPerDay == nil && gold?.wallsEnd == nil)
        #expect(gold?.dues.isEmpty == true && gold?.weekTotal == 0 && gold?.perDay == 0)
    }

    @Test func toutEstFait_aucuneRessource() {
        let r = R.needs([R.cannon([])], Self.canon)
        #expect(r.needs.isEmpty)
    }

    // MARK: - Propriétés

    @Test func proprietes_villagesAleatoiresAGraineFixe() {
        for seed in UInt64(1)...100 {
            let (v, r, profile, now) = Aleatoire.village(seed)
            let plan = makePlan(for: v, reference: r, advice: AdviceData(), profile: profile, now: now)
            let steps = remainingSteps(of: v, reference: r, profile: profile, now: now)
            let needs = resourceNeeds(of: plan, remaining: steps)
            #expect(needs == resourceNeeds(of: plan, remaining: steps), "seed \(seed) : pas déterministe")
            let week = plan.steps.filter { !$0.fromSnapshot && $0.start < now.addingTimeInterval(7 * 86_400) }
            for n in needs {
                let expected = week.reduce(0) { $0 + $1.costs.filter { $0.resource == n.resource }.reduce(0) { $0 + $1.amount } }
                #expect(n.weekTotal == expected, "seed \(seed) \(n.resource) : somme de la semaine")
                #expect(n.perDay * 7 >= n.weekTotal && n.perDay * 7 < n.weekTotal + 7, "seed \(seed) : rythme")
                #expect(n.dues.count <= 3 && n.dues == n.dues.sorted { $0.date < $1.date }, "seed \(seed) : échéances")
                #expect(n.dues.allSatisfy { $0.date >= now && $0.amount > 0 }, "seed \(seed) : échéance passée ou vide")
                #expect(Set(n.dues.map(\.date)).count == n.dues.count, "seed \(seed) : deux échéances au même instant")
            }
        }
    }

    // MARK: - Village réel

    /// Calcul à la main (PR T14) : `now` = photo, 11 nov. 2026 17 h 28 min 2 s (Paris), profil par défaut.
    /// Les neuf premiers lancements de T13 tombent dans les sept jours (le dixième, +7,15 j, est hors fenêtre) ;
    /// coûts lus dans reference.json :
    ///   12 nov. 7 h 00     Maison des familiers 9 (11 M élixir) + Usine de sorts noirs 8 (18 M élixir)
    ///   12 nov. 8 h 14 55  Caserne 18 (15 M élixir)
    ///   12 nov. 20 h 14 16 Phénix 10 (190 000 élixir noir)
    ///   12 nov. 20 h 55 00 Root Rider 2, labo (15 M élixir)
    ///   13 nov. 21 h 11 50 Atelier 8 (13 M élixir)
    ///   13 nov. 21 h 11 55 Prince des sbires 61 (150 000 élixir noir)
    ///   14 nov. 17 h 17 34 Roi 87 (225 000 élixir noir)
    ///   18 nov. 7 h 00     Maison des familiers 10 (12 M élixir)
    /// Élixir : échéances 29 M, 15 M, 15 M ; semaine 11+18+15+15+13+12 = 84 M, 84 M ÷ 7 = 12 M par jour.
    /// Élixir noir : 190 000, 150 000, 225 000 ; semaine 565 000 (le Prince 62, 155 000, part à +7,15 j), ÷ 7 = 80 714,3 → 80 715.
    /// Or : rien dans la semaine (premier lancement le 9 déc.). Murs : 1 125 000 000 d'or (T10), cap le 30 nov. 2028 à 7 h
    /// soit 64 762 318 s = 749,56 j après la photo : 1 125 000 000 × 86 400 ÷ 64 762 318 = 1 500 872,8 → 1 500 873 par jour.
    @Test func reelHdv16_ressourcesDesSeptProchainsJours() {
        let plan = Réel.plan
        let steps = remainingSteps(of: Réel.village, reference: Réel.reference, profile: Profile(), now: Réel.export.date)
        let needs = resourceNeeds(of: plan, remaining: steps)
        #expect(needs.map(\.resource) == [.gold, .elixir, .darkElixir])
        func due(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, _ amount: Int) -> ResourceNeed.Due {
            .init(date: Réel.paris(y, mo, d, h, mi, s), amount: amount)
        }
        let elixir = needs[1], dark = needs[2], gold = needs[0]
        #expect(elixir.dues == [due(2026, 11, 12, 7, 0, 0, 29_000_000), due(2026, 11, 12, 8, 14, 55, 15_000_000),
                                due(2026, 11, 12, 20, 55, 0, 15_000_000)])
        #expect(elixir.weekTotal == 84_000_000 && elixir.perDay == 12_000_000)
        #expect(dark.dues == [due(2026, 11, 12, 20, 14, 16, 190_000), due(2026, 11, 13, 21, 11, 55, 150_000),
                              due(2026, 11, 14, 17, 17, 34, 225_000)])
        #expect(dark.weekTotal == 565_000 && dark.perDay == 80_715)
        #expect(gold.weekTotal == 0 && gold.perDay == 0 && gold.dues.count == 3)
        #expect(gold.dues.first?.date == Réel.paris(2026, 12, 9, 7, 0, 0))
        #expect(gold.wallsRemaining == 1_125_000_000 && gold.wallsPerDay == 1_500_873 && gold.wallsEnd == plan.cap)
        #expect(elixir.wallsRemaining == 0 && elixir.wallsPerDay == nil && dark.wallsRemaining == 0)
    }
}
