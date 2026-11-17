import Foundation
import Testing
@testable import VillagePlannerKit

// Priorités (T12) : règles P1 à P6 et E1 à E4 du PLAN §5.3, listées en tête de Priorites.swift.
// Petites références inventées, calculables de tête ; le village réel sert à l'exemple écrit à la main.

enum Prio {
    static let th = 1000001, lab = 1000007, hall = 1000071, cc = 1000014, camp = 1000000, mine = 1000004
    static let hut = 1000015, cannon = 1000008, xbow = 1000021, inferno = 1000027, bomb = 12000000, wall = 1000010
    static let king = 28000000, queen = 28000001, warden = 28000002
    static let troopA = 4000000, troopB = 4000001, troopC = 4000002, troopD = 4000003, troopE = 4000004
    static let pet = 73000000, pet2 = 73000001, gear = 90000000, gear2 = 90000001
    static let multiGear = 1000079                          // réservé à l'HDV 17 : absent du village

    static let names: [Int: String] = [
        lab: "lab", hall: "hall", cc: "cc", camp: "camp", mine: "mine", cannon: "cannon", xbow: "xbow",
        inferno: "inferno", bomb: "bomb", wall: "wall", king: "king", queen: "queen", warden: "warden",
        troopA: "A", troopB: "B", troopC: "C", troopD: "D", troopE: "E", pet: "pet", pet2: "pet2", gear: "gear", gear2: "gear2",
    ]

    /// Un type présent aux HDV 1 à 4 avec tous ses niveaux ; `levels` : (coût, durée, prérequis).
    static func item(_ id: Int, _ category: VillagePlannerKit.Category, section: String = "buildings",
                     worker: WorkerKind = .builder, resource: Resource = .gold, count: Int = 1,
                     _ levels: [(Int?, Int, [Requirement])]) -> ReferenceItem {
        let n = levels.count
        return Rest.item(id, section, category, worker, counts: [0, count, count, count, count], max: [0, n, n, n, n],
                         resource: resource, levels: levels)
    }
    static func lv(_ cost: Int?, _ duration: Int, _ requires: [Requirement] = []) -> (Int?, Int, [Requirement]) {
        (cost, duration, requires)
    }
    static let thItem = Rest.item(th, "buildings", .economy, .builder, counts: [0, 1, 1, 1, 1], max: [0, 1, 2, 3, 4],
                                  levels: [(0, 0, []), (0, 0, []), (0, 0, []), (0, 0, [])])

    static func e(_ id: Int, _ level: Int, _ count: Int = 1, timer: Int? = nil) -> ExportEntry {
        Mini.e(id, level, count, timer: timer)
    }

    /// Le village à l'HDV 3 ; `maxTownHall` : le plus haut HDV de la référence.
    static func village(_ items: [ReferenceItem], _ sections: [String: [ExportEntry]],
                        maxTownHall: Int = 3, joueur: EquipementsJoueur? = nil) -> (Village, ReferenceData) {
        let reference = ReferenceData(items: [thItem] + items, maxTownHall: maxTownHall)
        var s = sections
        s["buildings", default: []].insert(e(th, 3), at: 0)
        let export = VillageExport(tag: "#2PP", date: Rest.date, sections: s, idLists: [:], boosts: [:], warnings: [])
        return (Village(export: export, reference: reference, joueur: joueur), reference)
    }

    static func queues(_ items: [ReferenceItem], _ sections: [String: [ExportEntry]], profile: Profile = Profile(),
                       advice: AdviceData = advice, now: Date = Rest.date,
                       joueur: EquipementsJoueur? = nil) -> [WorkerKind: [PrioritizedStep]] {
        let (v, r) = village(items, sections, joueur: joueur)
        return priorities(of: remainingSteps(of: v, reference: r, profile: profile, now: now),
                          in: v, reference: r, advice: advice, profile: profile)
    }

    /// Conseils inventés : l'Inferno avant l'Arc-X ; la Multi-Gear Tower (HDV 17) en tête, absente du village.
    static let advice = AdviceData(lists: [
        "defenses": AdviceList(criterion: "x", sources: [], ids: [multiGear, inferno, xbow]),
        "laboratory": AdviceList(criterion: "x", sources: [], ids: [troopA]),
        "pets": AdviceList(criterion: "x", sources: [], ids: [pet2]),
        "equipment": AdviceList(criterion: "x", sources: [], ids: [gear2]),
    ])

    // Le village « tous rangs » : tout coûte de l'or (E2 ne départage rien), durées de 10 s sauf l'Arc-X (50 s).
    static let all: [ReferenceItem] = [
        item(lab, .economy, [lv(100, 10), lv(100, 10), lv(100, 10)]),
        item(troopA, .laboratory, section: "units", worker: .laboratory, [lv(nil, 0), lv(500, 100, [Requirement(itemID: lab, level: 2)])]),
        item(camp, .economy, [lv(100, 10), lv(100, 10)]),
        item(cc, .economy, [lv(100, 10), lv(100, 10)]),
        item(cannon, .defenses, [lv(100, 10), lv(100, 10)]),
        item(king, .heroes, section: "heroes", [lv(100, 10), lv(100, 10)]),
        item(inferno, .defenses, [lv(100, 10), lv(100, 10)]),
        item(xbow, .defenses, [lv(100, 10), lv(100, 50)]),
        item(mine, .economy, [lv(100, 10), lv(100, 10)]),
        item(bomb, .traps, section: "traps", [lv(100, 10), lv(100, 10)]),
        item(wall, .walls, [lv(100, 0), lv(100, 0)]),
    ]
    static let allSections: [String: [ExportEntry]] = [
        "buildings": [e(lab, 1), e(camp, 1), e(cc, 1), e(inferno, 1), e(xbow, 1), e(mine, 1), e(wall, 1)],   // canon à construire
        "units": [e(troopA, 1)], "heroes": [e(king, 1)], "traps": [e(bomb, 1)],
    ]

    static func labels(_ q: [PrioritizedStep]?) -> [String] { (q ?? []).map { "\(names[$0.step.itemID] ?? "#\($0.step.itemID)")\($0.step.level)" } }
}

@Suite struct PrioritesTests {
    typealias P = Prio
    func builder(_ profile: Profile = Profile()) -> [PrioritizedStep] { P.queues(P.all, P.allSections, profile: profile)[.builder]! }

    // MARK: - Rangs de la file des ouvriers

    @Test func P1_ceQuiDebloquePuisChateauEtCampsPuisBatimentsAConstruire() {
        let q = builder()
        // Labo 2 (exigé par la troupe A), camps et château, puis le canon à construire.
        #expect(P.labels(Array(q.prefix(4))) == ["lab2", "camp2", "cc2", "cannon1"])
        #expect(q.prefix(4).map(\.reason) == [.unlocks, .armyAndCastle, .armyAndCastle, .build])
        // Le labo 3 n'est exigé par rien : P4, pas P1. Le canon 2 n'est plus « à construire ».
        #expect(q.first { P.labels([$0]) == ["lab3"] }?.reason == .otherBuilding)
        #expect(q.first { P.labels([$0]) == ["cannon2"] }?.reason == .otherBuilding)
    }

    @Test func P1_lesBatimentsDOrigineDUneFusionDebloquentLeBatimentFusionne() {
        // Canon ricochet à faire de deux canons au niveau 2 : les canons 2 débloquent, le ricochet se construit après.
        let v = Rest.village([Mini.e(Rest.cannon, 1, 2)], reference: Rest.referenceFusion)
        let steps = remainingSteps(of: v, reference: Rest.referenceFusion, profile: Profile(), now: Rest.date)
        let q = priorities(of: steps, in: v, reference: Rest.referenceFusion, advice: AdviceData(), profile: Profile())[.builder]!
        #expect(q.map(\.step.itemID).prefix(2) == [Rest.cannon, Rest.ricochet])
        #expect(q.prefix(2).map(\.reason) == [.unlocks, .build])
    }

    @Test func P2_lesHerosJusteApresP1() {
        let q = builder()
        #expect(P.labels([q[4]]) == ["king2"] && q[4].reason == .hero)
    }

    @Test func P3_lesDefensesClesDansLOrdreDeConseils() {
        let q = builder()
        // L'Inferno passe avant l'Arc-X, dont la chaîne est pourtant plus longue (E3 dirait l'inverse).
        #expect(P.labels(Array(q[5...6])) == ["inferno2", "xbow2"])
        #expect(q[5...6].map(\.reason) == [.keyDefense(position: 1), .keyDefense(position: 2)])
    }

    @Test func P3_unIdentifiantAbsentDuVillageOuDUnHdvSuperieurEstIgnore() {
        // La Multi-Gear Tower (HDV 17) est en tête de la liste : elle n'entre pas dans la file, l'ordre ne bouge pas.
        let sans = AdviceData(lists: ["defenses": AdviceList(criterion: "x", sources: [], ids: [P.inferno, P.xbow])])
        let a = P.labels(P.queues(P.all, P.allSections)[.builder])
        #expect(a == P.labels(P.queues(P.all, P.allSections, advice: sans)[.builder]))
        #expect(!a.contains { $0.hasPrefix("#\(P.multiGear)") })
        // Dans le village réel (HDV 16), ni la Multi-Gear Tower ni la Super Wizard Tower (HDV 18).
        #expect(!Réel.queues[.builder]!.contains { [1000079, 1000102].contains($0.step.itemID) })
    }

    @Test func P4_lesAutresDefensesEtBatimentsApresLesDefensesCles() {
        let q = builder()
        // À égalité (or, 10 s chacun) : E4, l'identifiant.
        #expect(P.labels(Array(q[7...9])) == ["mine2", "lab3", "cannon2"])
        #expect(q[7...9].allSatisfy { $0.reason == .otherBuilding })
    }

    @Test func P5_lesPiegesEnDernier() {
        let q = builder()
        #expect(P.labels([q.last!]) == ["bomb2"] && q.last!.reason == .trap)
        #expect(q.count == 11)
    }

    @Test func P6_lesMursNEntrentJamaisDansLaFile() {
        let (v, r) = P.village(P.all, P.allSections)
        #expect(remainingSteps(of: v, reference: r, profile: Profile(), now: Rest.date).contains { $0.itemID == P.wall })
        #expect(P.queues(P.all, P.allSections).values.allSatisfy { !$0.contains { $0.step.category == .walls } })
        #expect(!Réel.queues.values.contains { $0.contains { $0.step.category == .walls } })
    }

    // MARK: - Orientation

    @Test func orientationEstLaTableDuPlan() {
        #expect(Orientation.balanced.rankOrder == [.p1, .p2, .p3, .p4, .p5])
        #expect(Orientation.attack.rankOrder == [.p2, .p1, .p3, .p4, .p5])
        #expect(Orientation.defense.rankOrder == [.p1, .p3, .p4, .p2, .p5])
        #expect(P.labels(builder(Profile(orientation: .attack)))
                == ["king2", "lab2", "camp2", "cc2", "cannon1", "inferno2", "xbow2", "mine2", "lab3", "cannon2", "bomb2"])
        #expect(P.labels(builder(Profile(orientation: .defense)))
                == ["lab2", "camp2", "cc2", "cannon1", "inferno2", "xbow2", "mine2", "lab3", "cannon2", "king2", "bomb2"])
    }

    @Test func unPrerequisDeLaFileDesOuvriersPasseAvant() {
        // Attaque : les héros d'abord, mais le roi 2 exige le Hall des héros 2. Le reine 2 exige un Hall 9, introuvable :
        // elle attend en fin de file.
        let items = [P.item(P.hall, .economy, [P.lv(100, 10), P.lv(100, 10)]),
                     P.item(P.king, .heroes, section: "heroes", [P.lv(100, 10), P.lv(100, 10, [Requirement(itemID: P.hall, level: 2)])]),
                     P.item(P.queen, .heroes, section: "heroes", [P.lv(100, 10), P.lv(100, 10, [Requirement(itemID: P.hall, level: 9)])]),
                     P.item(P.mine, .economy, [P.lv(100, 10), P.lv(100, 10)])]
        let s = ["buildings": [P.e(P.hall, 1), P.e(P.mine, 1)], "heroes": [P.e(P.king, 1), P.e(P.queen, 1)]]
        let q = P.queues(items, s, profile: Profile(orientation: .attack))[.builder]!
        #expect(P.labels(q) == ["hall2", "king2", "mine2", "queen2"])
    }

    // MARK: - Égalités

    @Test func E1_unEpingleDAbordEtDevantToutSonPoste() {
        // Le piège épinglé (P5) passe devant le labo qui débloque (P1) ; deux épinglés gardent leur ordre de rang.
        let q = builder(Profile(pinned: [P.bomb, P.xbow]))
        #expect(P.labels(Array(q.prefix(3))) == ["xbow2", "bomb2", "lab2"])
        #expect(q.prefix(2).allSatisfy(\.pinned) && !q[2].pinned)
        // Labo : la troupe B, hors liste, passe devant la troupe A de la liste.
        let lab = P.queues(Self.labItems, Self.labSections, profile: Profile(pinned: [P.troopB]))[.laboratory]!
        #expect(P.labels([lab[0]]) == ["B2"])
    }

    @Test func E2_laRessourceLaMoinsDemandeeParCeQuiEstDejaPlace() {
        // Trois P4 : canon (or, 30 s), labo (or, 20 s), mine (élixir, 10 s). Le canon d'abord (E3) ; ensuite l'or est
        // déjà demandé et l'élixir pas : la mine passe avant le labo, malgré sa chaîne plus courte.
        let items = [P.item(P.cannon, .defenses, [P.lv(100, 10), P.lv(100, 30)]),
                     P.item(P.lab, .economy, [P.lv(100, 10), P.lv(100, 20)]),
                     P.item(P.mine, .economy, resource: .elixir, [P.lv(100, 10), P.lv(100, 10)])]
        let s = ["buildings": [P.e(P.cannon, 1), P.e(P.lab, 1), P.e(P.mine, 1)]]
        #expect(P.labels(P.queues(items, s)[.builder]) == ["cannon2", "mine2", "lab2"])
    }

    @Test func E2_enPartDuTotalDeChaqueRessource() {
        // Quatre P4. Labo (or 1 000, 100 s) puis Hall (élixir noir 10, 90 s) : E3, rien n'est encore demandé.
        // Restent canon (or 99 000) et mine (élixir noir 10) : l'or placé fait 1 000 sur 100 000 (1 %), l'élixir noir
        // 10 sur 20 (50 %). En unités, l'élixir noir serait « moins demandé » (10 < 1 000) ; en part, c'est l'or.
        let items = [P.item(P.lab, .economy, [P.lv(1, 10), P.lv(1000, 100)]),
                     P.item(P.hall, .economy, resource: .darkElixir, [P.lv(1, 10), P.lv(10, 90)]),
                     P.item(P.cannon, .defenses, [P.lv(1, 10), P.lv(99_000, 10)]),
                     P.item(P.mine, .economy, resource: .darkElixir, [P.lv(1, 10), P.lv(10, 10)])]
        let s = ["buildings": [P.e(P.lab, 1), P.e(P.hall, 1), P.e(P.cannon, 1), P.e(P.mine, 1)]]
        #expect(P.labels(P.queues(items, s)[.builder]) == ["lab2", "hall2", "cannon2", "mine2"])
    }

    @Test func E2_unPasADeuxRessourcesPrendLaPlusDemandee() {
        // Labo (or 1 000, 100 s) d'abord (E3). Le canon coûte or 1 000 et élixir 10 : l'or est demandé à 50 %,
        // l'élixir à 0 %. Sa part est la plus forte des deux (50 %) : la mine (élixir noir, 0 %) passe avant lui,
        // malgré sa chaîne plus courte. Avec la plus faible des parts, le canon passerait (E3, 50 s contre 10).
        let canon = ReferenceItem(id: P.cannon, names: ["en": "c"], section: "buildings", category: .defenses,
                                  exclusion: nil, worker: .builder,
                                  levels: [ReferenceLevel(level: 1, costs: [], duration: 10, requires: []),
                                           ReferenceLevel(level: 2, costs: [ResourceAmount(resource: .gold, amount: 1000),
                                                                            ResourceAmount(resource: .elixir, amount: 10)],
                                                          duration: 50, requires: [])],
                                  countByTownHall: [0, 1, 1, 1, 1], maxLevelByTownHall: [0, 2, 2, 2, 2], mergedFrom: [])
        let items = [P.item(P.lab, .economy, [P.lv(1, 10), P.lv(1000, 100)]), canon,
                     P.item(P.mine, .economy, resource: .darkElixir, [P.lv(1, 10), P.lv(10, 10)])]
        let s = ["buildings": [P.e(P.lab, 1), P.e(P.cannon, 1), P.e(P.mine, 1)]]
        #expect(P.labels(P.queues(items, s)[.builder]) == ["lab2", "mine2", "cannon2"])
    }

    @Test func E2_unGroupeDExemplairesDemandeSonCoutFoisLeNombre() {
        // Mine (élixir 100, 100 s), puis cinq canons (or 100 chacun, 90 s) : E3. L'or placé fait 5 × 100 = 500 sur
        // 600 (83 %), l'élixir 100 sur 150 (67 %) : le Hall (élixir 50) passe avant le labo (or 100).
        // Compté une fois, l'or ferait 100 sur 200 (50 %) et le labo passerait.
        let items = [P.item(P.mine, .economy, resource: .elixir, [P.lv(1, 10), P.lv(100, 100)]),
                     P.item(P.cannon, .defenses, count: 5, [P.lv(1, 10), P.lv(100, 90)]),
                     P.item(P.lab, .economy, [P.lv(1, 10), P.lv(100, 10)]),
                     P.item(P.hall, .economy, resource: .elixir, [P.lv(1, 10), P.lv(50, 10)])]
        let s = ["buildings": [P.e(P.mine, 1), P.e(P.cannon, 1, 5), P.e(P.lab, 1), P.e(P.hall, 1)]]
        #expect(P.labels(P.queues(items, s)[.builder]) == ["mine2", "cannon2", "hall2", "lab2"])
    }

    @Test func E3_laChaineRestanteLaPlusLongue() {
        // Mêmes rang et ressource : le canon (deux niveaux, 20 s) avant la mine (un niveau, 15 s), malgré l'identifiant ;
        // après son niveau 2, il ne lui reste que 10 s : la mine passe.
        let items = [P.item(P.cannon, .defenses, [P.lv(100, 10), P.lv(100, 10), P.lv(100, 10)]),
                     P.item(P.mine, .economy, [P.lv(100, 10), P.lv(100, 15)])]
        let s = ["buildings": [P.e(P.cannon, 1), P.e(P.mine, 1)]]
        #expect(P.labels(P.queues(items, s)[.builder]) == ["cannon2", "mine2", "cannon3"])
    }

    @Test func E3_unMinuteurEnCoursAllongeLaChaine() {
        // Canon en cours vers le 2 (100 s restantes) puis le 3 (10 s) : chaîne 110 s, devant la mine (15 s).
        let items = [P.item(P.cannon, .defenses, [P.lv(100, 10), P.lv(100, 10), P.lv(100, 10)]),
                     P.item(P.mine, .economy, [P.lv(100, 10), P.lv(100, 15)])]
        let s = ["buildings": [P.e(P.cannon, 1, timer: 100), P.e(P.mine, 1)]]
        let q = P.queues(items, s)[.builder]!
        #expect(P.labels(q) == ["cannon3", "mine2"])
        #expect(q.allSatisfy { !$0.step.isInProgress })            // l'en cours n'est jamais placé
    }

    @Test func E4_lIdentifiantEnDernier() {
        let items = [P.item(P.cannon, .defenses, [P.lv(100, 10), P.lv(100, 10)]),
                     P.item(P.mine, .economy, [P.lv(100, 10), P.lv(100, 10)])]
        let s = ["buildings": [P.e(P.cannon, 1), P.e(P.mine, 1)]]
        #expect(P.labels(P.queues(items, s)[.builder]) == ["mine2", "cannon2"])
    }

    // MARK: - Limite de héros

    static let heroItems = [P.item(P.hut, .economy, [P.lv(0, 0)]),
                            P.item(P.king, .heroes, section: "heroes", [P.lv(100, 10), P.lv(100, 10)]),
                            P.item(P.queen, .heroes, section: "heroes", [P.lv(100, 10), P.lv(100, 10)]),
                            P.item(P.warden, .heroes, section: "heroes", [P.lv(100, 10), P.lv(100, 10)]),
                            P.item(P.mine, .economy, [P.lv(100, 10), P.lv(100, 10)]),
                            P.item(P.cannon, .defenses, [P.lv(100, 10), P.lv(100, 10)])]
    // Trois ouvriers, le roi en amélioration : deux ouvriers libres.
    static let heroSections = ["buildings": [P.e(P.hut, 1, 3), P.e(P.mine, 1), P.e(P.cannon, 1)],
                               "heroes": [P.e(P.king, 1, timer: 500), P.e(P.queen, 1), P.e(P.warden, 1)]]

    @Test func limiteDeHerosRespecteeDansLesLancementsPossiblesMaintenant() {
        func q(_ limit: Int?) -> [String] { P.labels(P.queues(Self.heroItems, Self.heroSections, profile: Profile(heroLimit: limit))[.builder]) }
        #expect(q(nil) == ["queen2", "warden2", "mine2", "cannon2"])
        // Limite 1, déjà atteinte par le roi : les deux ouvriers libres prennent des bâtiments.
        #expect(q(1) == ["mine2", "cannon2", "queen2", "warden2"])
        // Limite 2 : un héros de plus, pas deux.
        #expect(q(2) == ["queen2", "mine2", "warden2", "cannon2"])
    }

    @Test func limiteDeHeros_unMinuteurFiniDepuisLaPhotoLibereLOuvrier() {
        // Le roi devait finir 500 s après la photo ; on calcule 600 s après : il ne compte plus (S0). Trois ouvriers
        // libres et une place de héros : la reine, puis deux bâtiments, puis le gardien.
        let q = P.queues(Self.heroItems, Self.heroSections, profile: Profile(heroLimit: 1), now: Rest.date.addingTimeInterval(600))
        #expect(P.labels(q[.builder]) == ["queen2", "mine2", "cannon2", "warden2"])
    }

    // MARK: - Labo, familiers, forge

    // A dans la liste ; B (élixir 500), C (élixir noir 10), D (900 puis 100), E absent (niveau 1 gratuit, puis 50).
    static let labItems = [
        P.item(P.troopA, .laboratory, section: "units", worker: .laboratory, resource: .elixir, [P.lv(nil, 0), P.lv(9999, 10)]),
        P.item(P.troopB, .laboratory, section: "units", worker: .laboratory, resource: .elixir, [P.lv(nil, 0), P.lv(500, 10)]),
        P.item(P.troopC, .laboratory, section: "units", worker: .laboratory, resource: .darkElixir, [P.lv(nil, 0), P.lv(10, 10)]),
        P.item(P.troopD, .laboratory, section: "units", worker: .laboratory, resource: .elixir, [P.lv(nil, 0), P.lv(900, 10), P.lv(100, 10)]),
        P.item(P.troopE, .laboratory, section: "units", worker: .laboratory, resource: .elixir, [P.lv(nil, 0), P.lv(50, 10)]),
    ]
    static let labSections = ["units": [P.e(P.troopA, 1), P.e(P.troopB, 1), P.e(P.troopC, 1), P.e(P.troopD, 1)]]

    @Test func labo_liste_puisLeMoinsCher_puisIdentifiant() {
        let q = P.queues(Self.labItems, Self.labSections)[.laboratory]!
        // A (liste) ; E1 gratuit ; E2 50 ; B 500 ; D2 900, puis D3 100 (les niveaux se suivent) ; C (élixir noir, plus rare).
        #expect(P.labels(q) == ["A2", "E1", "E2", "B2", "D2", "D3", "C2"])
        #expect(q[0].reason == .advice(position: 0) && q[1...].allSatisfy { $0.reason == .cheapest })
    }

    @Test func famillesEtForge_suiventLeurListe() {
        let items = [P.item(P.pet, .pets, section: "pets", worker: .petHouse, resource: .darkElixir, [P.lv(1, 10), P.lv(1, 10)]),
                     P.item(P.pet2, .pets, section: "pets", worker: .petHouse, resource: .darkElixir, [P.lv(9, 10), P.lv(9, 10)]),
                     P.item(P.gear, .equipment, section: "equipment", worker: .blacksmith, resource: .shinyOre, [P.lv(nil, 0), P.lv(1, 0), P.lv(1, 0)]),
                     P.item(P.gear2, .equipment, section: "equipment", worker: .blacksmith, resource: .shinyOre, [P.lv(nil, 0), P.lv(9, 0), P.lv(9, 0)])]
        let s = ["pets": [P.e(P.pet, 1), P.e(P.pet2, 1)], "equipment": [P.e(P.gear, 2), P.e(P.gear2, 2)]]
        let q = P.queues(items, s)
        #expect(P.labels(q[.petHouse]) == ["pet22", "pet2"])
        #expect(P.labels(q[.blacksmith]) == ["gear23", "gear3"])
    }

    // MARK: - Équipements équipés (T30)

    static let forge = [P.item(P.gear, .equipment, section: "equipment", worker: .blacksmith, resource: .shinyOre, [P.lv(nil, 0), P.lv(1, 0), P.lv(1, 0)]),
                        P.item(P.gear2, .equipment, section: "equipment", worker: .blacksmith, resource: .shinyOre, [P.lv(nil, 0), P.lv(9, 0), P.lv(9, 0)])]

    @Test func forge_equipesEnTete_sansChangerLeReste() {
        let s = ["equipment": [P.e(P.gear, 2), P.e(P.gear2, 2)]]
        #expect(P.labels(P.queues(Self.forge, s)[.blacksmith]) == ["gear23", "gear3"])
        let q = P.queues(Self.forge, s, joueur: EquipementsJoueur(equipes: [P.gear]))[.blacksmith]
        #expect(P.labels(q) == ["gear3", "gear23"])                                  // la liste des conseils met gear2 devant : l'équipé la double
        // Un épinglé reste devant un équipé (E1 d'abord).
        let epingle = P.queues(Self.forge, s, profile: Profile(pinned: [P.gear2]), joueur: EquipementsJoueur(equipes: [P.gear]))[.blacksmith]
        #expect(P.labels(epingle) == ["gear23", "gear3"])
    }

    @Test func forge_rienNeChangeSansDonneeJoueur_etLesOuvriersNeBougentPas() {
        let s = ["equipment": [P.e(P.gear, 2), P.e(P.gear2, 2)]]
        let sans = P.queues(Self.forge, s), vide = P.queues(Self.forge, s, joueur: EquipementsJoueur())
        #expect(sans == vide)
        let avec = P.queues(Self.forge, s, joueur: EquipementsJoueur(equipes: [P.gear2]))
        #expect(avec[.builder] == sans[.builder] && avec[.laboratory] == sans[.laboratory] && avec[.petHouse] == sans[.petHouse])
    }

    @Test func v4_lApiDitPossede_remplaceLaRegle() {
        // gear est au niveau 1 dans l'export : V4 le tient pour non possédé, sauf si l'API dit qu'on l'a.
        let s = ["equipment": [P.e(P.gear, 1)]]
        #expect(P.queues(Self.forge, s)[.blacksmith]!.isEmpty)
        #expect(P.labels(P.queues(Self.forge, s, joueur: EquipementsJoueur(possedes: [P.gear]))[.blacksmith]) == ["gear2", "gear3"])
        // Un autre équipement possédé ne rend pas celui-ci possédé.
        #expect(P.queues(Self.forge, s, joueur: EquipementsJoueur(possedes: [P.gear2]))[.blacksmith]!.isEmpty)
    }

    @Test func v4_lApiNeFaitPasExisterUnEquipementAuNiveauZero() {
        let s = ["equipment": [P.e(P.gear, 0)]]
        let (v, _) = P.village(Self.forge, s, joueur: EquipementsJoueur(possedes: [P.gear]))
        #expect(!v.elements.contains { $0.itemID == P.gear })
    }

    @Test func exempleReelHdv16_forgeEquipesEnTete_lesAutresGardentLeurOrdre() {
        let forge = Réel.queues[.blacksmith]!
        let equipes = Set(forge.map(\.step.itemID).reversed().prefix(2))             // les deux derniers de la file : jamais en tête
        let v = Village(export: Réel.export, reference: Réel.reference, joueur: EquipementsJoueur(equipes: equipes))
        let steps = remainingSteps(of: v, reference: Réel.reference, profile: Profile(), now: Réel.export.date)
        let q = priorities(of: steps, in: v, reference: Réel.reference, advice: Réel.advice, profile: Profile())
        let f = q[.blacksmith]!
        let tete = f.prefix { equipes.contains($0.step.itemID) }
        #expect(!tete.isEmpty && f.dropFirst(tete.count).allSatisfy { !equipes.contains($0.step.itemID) })   // tous devant, aucun derrière
        // Les non-équipés gardent leur ordre d'avant.
        #expect(f.filter { !equipes.contains($0.step.itemID) } == forge.filter { !equipes.contains($0.step.itemID) })
        #expect(q[.builder] == Réel.queues[.builder] && q[.laboratory] == Réel.queues[.laboratory])
    }

    @Test func leMoinsCher_ressourceLaPlusRareDAbord_sansCoutZero_sansNiveauEnDernier() {
        func k(_ c: [(Resource, Int)]) -> CostKey { CostKey(c.map { ResourceAmount(resource: $0.0, amount: $0.1) }) }
        #expect(k([]) < k([(.gold, 1)]))                                            // sans coût : zéro
        #expect(k([(.gold, 9_000_000)]) < k([(.elixir, 1)]))                         // l'élixir avant l'or en rareté
        #expect(k([(.elixir, 9_000_000)]) < k([(.darkElixir, 1)]))
        #expect(k([(.shinyOre, 3000)]) < k([(.shinyOre, 100), (.glowyOre, 10)]))     // le minerai lumineux départage
        #expect(k([(.glowyOre, 900)]) < k([(.starryOre, 1)]))
        #expect(k([(.starryOre, 9_999)]) < CostKey(nil))                             // sans prochain niveau : en dernier
        // La règle tient aussi dans `AdviceData.sorted` (T11).
        struct T { let id: Int; let cost: [ResourceAmount]? }
        let items = [T(id: 3, cost: nil), T(id: 2, cost: [ResourceAmount(resource: .darkElixir, amount: 1)]),
                     T(id: 1, cost: [ResourceAmount(resource: .elixir, amount: 50)])]
        #expect(AdviceData().sorted(items, in: .laboratory, id: \.id, cost: { CostKey($0.cost) }).map(\.id) == [1, 2, 3])
    }

    // MARK: - Village réel

    @Test func memeEntreeMemeOrdre_entreeMelangee() {
        var g = GénérateurGraine(état: 12)
        let steps = Réel.steps
        for _ in 0..<10 {
            let q = priorities(of: steps.shuffled(using: &g), in: Réel.village, reference: Réel.reference,
                               advice: Réel.advice, profile: Profile())
            #expect(q == Réel.queues)
        }
    }

    @Test func horsAvancementJamaisDansUneFile() {
        let placed = Réel.queues.values.flatMap { $0 }
        #expect(placed.allSatisfy { Réel.reference.item($0.step.itemID)?.category != nil && !$0.step.isInProgress })
        // Toutes les étapes à faire (hors murs) sont placées, une seule fois.
        let todo = Réel.steps.filter { !$0.isInProgress && $0.category != .walls }
        #expect(placed.count == todo.count)
    }

    @Test func exempleReelHdv16_dixPremieresDeLaFileDesOuvriers() {
        // Calcul à la main dans la PR. P1 : les cinq bâtiments exigés par une autre amélioration (familiers, sorts,
        // troupes, engins), tous en élixir : E3 les range (chaîne restante la plus longue), E4 entre l'Atelier et la
        // Maison des familiers (604 800 s chacun). P2 : l'élixir noir n'est pas encore demandé (E2), le Prince des
        // sbires a la chaîne la plus longue (20 niveaux, 11 016 000 s) et la garde (E3) au moins jusqu'au niveau 65.
        let q = Réel.queues[.builder]!.prefix(10)
        let attendu: [(Int, Int, PrioritizedStep.Reason)] = [
            (1000068, 9, .unlocks), (1000029, 8, .unlocks), (1000006, 18, .unlocks), (1000059, 8, .unlocks),
            (1000068, 10, .unlocks),
            (28000006, 61, .hero), (28000006, 62, .hero), (28000006, 63, .hero), (28000006, 64, .hero), (28000006, 65, .hero),
        ]
        #expect(q.map(\.step.itemID) == attendu.map(\.0))
        #expect(q.map(\.step.level) == attendu.map(\.1))
        #expect(q.map(\.reason) == attendu.map(\.2))
    }

    // MARK: - HDV suivant

    @Test func passerALHdvSuivant_selonLeSeuilDuProfil() {
        let items = [P.item(P.king, .heroes, section: "heroes", [P.lv(100, 10), P.lv(100, 10)]),
                     P.item(P.cannon, .defenses, [P.lv(100, 10), P.lv(100, 10)])]
        func advice(_ king: Int, _ cannon: Int, _ t: TownHallThreshold, maxTH: Int = 4) -> NextTownHallAdvice {
            let (v, r) = P.village(items, ["buildings": [P.e(P.cannon, cannon)], "heroes": [P.e(P.king, king)]], maxTownHall: maxTH)
            return nextTownHallAdvice(for: v, reference: r, profile: Profile(nextTownHallThreshold: t))
        }
        #expect(advice(2, 2, .complete) == .advised)
        #expect(advice(2, 1, .complete) == .notYet)
        #expect(advice(2, 1, .heroesAndLab) == .advised)         // le canon reste, héros et labo sont faits
        #expect(advice(1, 2, .heroesAndLab) == .notYet)
        #expect(advice(2, 2, .complete, maxTH: 3) == .notYet)    // pas d'HDV au-dessus dans la référence
    }
}

extension Réel {
    static let advice = try! AdviceData.load()
    static let steps = remainingSteps(of: village, reference: reference, profile: Profile(), now: export.date)
    static let queues = priorities(of: steps, in: village, reference: reference, advice: advice, profile: Profile())
}
