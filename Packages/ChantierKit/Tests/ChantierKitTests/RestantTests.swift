import Foundation
import Testing
@testable import ChantierKit

// Améliorations restantes (T10) : règles Q1 à Q7 du PLAN §5.2, listées en tête de Restant.swift.
// Référence inventée `Rest`, calculable de tête ; le village réel sert aux étapes écrites à la main.

enum Rest {
    static let th = 1000001, cannon = 1000008, wall = 1000010, ricochet = 1000085
    static let troop = 4000000, pet = 73000000, gear = 90000000, helper = 93000000
    static let date = Date(timeIntervalSince1970: 1_000_000)

    /// `levels` : (coût, durée, prérequis) du niveau 1, 2, 3… ; coût nil : aucun.
    static func item(_ id: Int, _ section: String, _ category: ChantierKit.Category?, _ worker: WorkerKind,
                     counts: [Int], max: [Int], resource: Resource = .gold,
                     levels: [(Int?, Int, [Requirement])], alternative: Resource? = nil,
                     mergedFrom: [Requirement] = []) -> ReferenceItem {
        ReferenceItem(id: id, names: ["en": "#\(id)"], section: section, category: category,
                      exclusion: category == nil ? .helper : nil, worker: worker,
                      levels: levels.enumerated().map { i, l in
                          ReferenceLevel(level: i + 1, costs: l.0.map { [ResourceAmount(resource: resource, amount: $0)] } ?? [],
                                         duration: l.1, requires: l.2, alternativeResource: alternative)
                      },
                      countByTownHall: counts, maxLevelByTownHall: max, mergedFrom: mergedFrom)
    }

    static let items = [
        item(th, "buildings", .economy, .builder, counts: [0, 1, 1, 1], max: [0, 1, 2, 3],
             levels: [(0, 0, []), (1000, 100, []), (2000, 200, [])]),
        item(cannon, "buildings", .defenses, .builder, counts: [0, 1, 2, 2], max: [0, 1, 2, 3],
             levels: [(100, 10, []), (200, 20, [Requirement(itemID: th, level: 2)]),
                      (301, 30, [Requirement(itemID: th, level: 3)])]),
        item(wall, "buildings", .walls, .builder, counts: [0, 0, 2, 4], max: [0, 0, 1, 2],
             levels: [(300, 0, []), (500, 0, [])], alternative: .elixir),
        item(troop, "units", .laboratory, .laboratory, counts: [0, 0, 0, 0], max: [0, 0, 1, 2], resource: .elixir,
             levels: [(nil, 0, []), (500, 100, [])]),
        item(pet, "pets", .pets, .petHouse, counts: [0, 0, 0, 0], max: [0, 0, 1, 2], resource: .darkElixir,
             levels: [(nil, 0, []), (1000, 1000, [])]),
        item(gear, "equipment", .equipment, .blacksmith, counts: [0, 1, 1, 1], max: [0, 0, 2, 3], resource: .shinyOre,
             levels: [(nil, 0, []), (7, 0, []), (9, 0, [])]),
        item(helper, "helpers", nil, .builder, counts: [0, 1, 1, 1], max: [0, 1, 2, 3], levels: [(1, 1, [])]),
    ]
    static let reference = ReferenceData(items: items, maxTownHall: 3)
    /// Idem, avec un Canon ricochet autorisé à l'HDV 3, fait de deux canons au niveau 2.
    static let referenceFusion = ReferenceData(items: items + [
        item(ricochet, "buildings", .defenses, .builder, counts: [0, 0, 0, 1], max: [0, 0, 0, 1],
             levels: [(1000, 100, [])], mergedFrom: [Requirement(itemID: cannon, level: 2), Requirement(itemID: cannon, level: 2)])
    ], maxTownHall: 3)

    static func village(_ buildings: [ExportEntry], units: [ExportEntry] = [], other: [String: [ExportEntry]] = [:],
                        reference: ReferenceData = reference) -> Village {
        var sections = other
        sections["buildings"] = [Mini.e(th, 3)] + buildings
        sections["units"] = units
        let export = VillageExport(tag: "#2PP", date: date, sections: sections, idLists: [:], boosts: [:], warnings: [])
        return Village(export: export, reference: reference)
    }

    static func steps(_ v: Village, _ profile: Profile = Profile(), now: Date = date,
                      reference: ReferenceData = reference) -> [UpgradeStep] {
        remainingSteps(of: v, reference: reference, profile: profile, now: now)
    }
}

extension [UpgradeStep] {
    func of(_ id: Int) -> [UpgradeStep] { filter { $0.itemID == id } }
    var levels: [Int] { map(\.level) }
}

@Suite struct RestantTests {
    func e(_ id: Int, _ level: Int, _ count: Int = 1, timer: Int? = nil) -> ExportEntry { Mini.e(id, level, count, timer: timer) }
    let c = Rest.cannon

    // MARK: - Q1 : un pas par niveau, jusqu'au maximum

    @Test func Q1_unPasParNiveauDeNiveauPlusUnAuMaximum() {
        // Canon au niveau 1, maximum 3 : niveaux 2 et 3. Un canon au maximum : rien.
        let s = Rest.steps(Rest.village([e(c, 1), e(c, 3)])).of(c)
        #expect(s.levels == [2, 3])
        #expect(s.allSatisfy { $0.status == .todo && $0.count == 1 })
    }

    @Test func Q1_batimentACostruireCommenceAuNiveau1() {
        // Deux canons autorisés, aucun présent : un groupe de 2 au niveau 0, niveaux 1 à 3.
        let s = Rest.steps(Rest.village([]))
        #expect(s.of(c).levels == [1, 2, 3])
        #expect(s.of(c).allSatisfy { $0.count == 2 })
    }

    @Test func Q1_niveauUnDUneTroupeSansCoutNiDuree() {
        // Troupe déblocable, absente de l'export : niveau 1 (déblocage, ni coût ni durée) puis niveau 2.
        let s = Rest.steps(Rest.village([e(c, 3, 2)])).of(Rest.troop)
        #expect(s.levels == [1, 2])
        #expect(s[0].costs.isEmpty && s[0].duration == 0 && s[0].remaining == 0)
        #expect(s[1].costs == [ResourceAmount(resource: .elixir, amount: 500)] && s[1].duration == 100)
    }

    @Test func Q1_niveauDeLHdvJamaisAFaireASonPropreHdv() {
        // HDV 3 au maximum de l'HDV 3 : aucun pas ; en amélioration vers le 4 : toujours aucun.
        #expect(Rest.steps(Rest.village([e(c, 3, 2)])).of(Rest.th).isEmpty)
        let enCours = Rest.village([e(c, 3, 2), e(Rest.th, 3, timer: 99)])
        #expect(enCours.elements(Rest.th).contains { $0.upgrading })
        #expect(Rest.steps(enCours).of(Rest.th).isEmpty)
    }

    @Test func Q1_niveauAuDessusDuMaximumTenuPourTermine() {
        #expect(Rest.steps(Rest.village([e(c, 9, 2)])).of(c).isEmpty)
    }

    @Test func Q1_hdvInconnuAucunPas() {
        let export = VillageExport(tag: "#2PP", date: Rest.date, sections: ["buildings": [e(Rest.th, 9), e(c, 1)]],
                                   idLists: [:], boosts: [:], warnings: [])
        #expect(Rest.steps(Village(export: export, reference: Rest.reference)).isEmpty)
    }

    // MARK: - Q2 : en cours

    @Test func Q2_enCoursTempsDuMinuteurRienAPayer() {
        // Canon 1 → 2 en cours, 3 600 s à l'export, calcul 600 s plus tard : il reste 3 000 s, rien à payer.
        let v = Rest.village([e(c, 1, timer: 3600), e(c, 3)])
        let s = Rest.steps(v, now: Rest.date.addingTimeInterval(600)).of(c)
        #expect(s.levels == [2, 3])
        #expect(s[0].status == .inProgress(ends: Rest.date.addingTimeInterval(3600)))
        #expect(s[0].costs.isEmpty && s[0].remaining == 3000 && s[0].isInProgress)
        // Le niveau d'après reste à faire, plein tarif.
        #expect(s[1].status == .todo && s[1].costs == [ResourceAmount(resource: .gold, amount: 301)] && s[1].remaining == 30)
        // Un minuteur déjà fini : 0 seconde, jamais négatif.
        #expect(Rest.steps(v, now: Rest.date.addingTimeInterval(9999)).of(c)[0].remaining == 0)
    }

    @Test func Q2_minuteurIllisibleEnCoursFinInconnue() {
        let illisible = ExportEntry(id: c, level: 1, count: 1, timer: nil, extras: ["timer": .string("?")])
        let s = Rest.steps(Rest.village([illisible, e(c, 3)])).of(c)
        #expect(s[0].status == .inProgress(ends: nil) && s[0].remaining == nil && s[0].costs.isEmpty)
        let t = RemainingTotals(s)
        #expect(t.unknownTimers == 1 && t.seconds == 30)         // le niveau 3 compte, le minuteur illisible non
    }

    @Test func Q2_reductionNeTouchePasUneAmeliorationEnCours() {
        let v = Rest.village([e(c, 1, timer: 3600), e(c, 3)])
        let profil = Profile(builderReduction: Reduction(percent: 50, endsAt: .distantFuture))
        let s = Rest.steps(v, profil).of(c)
        #expect(s[0].remaining == 3600 && s[0].reductionPercent == 0)
        #expect(s[1].remaining == 15)
    }

    // MARK: - Q3 : réductions

    @Test func Q3_reductionsSAppliquentAuCoutEtALaDuree() {
        // Ouvriers −50 % : le niveau 3 du canon coûte 301 → 150 (arrondi vers le bas), dure 30 → 15 s.
        // Labo −25 % : 500 → 375, 100 → 75. Familiers et forge : jamais réduits.
        let fin = Rest.date.addingTimeInterval(1000)
        let profil = Profile(builderReduction: Reduction(percent: 50, endsAt: fin),
                             laboratoryReduction: Reduction(percent: 25, endsAt: fin))
        let v = Rest.village([e(c, 2, 2)], other: ["pets": [e(Rest.pet, 1)], "equipment": [e(Rest.gear, 2)]])
        let s = Rest.steps(v, profil)
        let canon = s.of(c)[0]
        #expect(canon.costs == [ResourceAmount(resource: .gold, amount: 150)] && canon.duration == 15)
        #expect(canon.baseCosts == [ResourceAmount(resource: .gold, amount: 301)] && canon.baseDuration == 30)
        #expect(canon.reductionPercent == 50)
        let troupe = s.of(Rest.troop)[1]
        #expect(troupe.costs == [ResourceAmount(resource: .elixir, amount: 375)] && troupe.duration == 75)
        #expect(s.of(Rest.pet).allSatisfy { $0.reductionPercent == 0 })
        #expect(s.of(Rest.gear).allSatisfy { $0.reductionPercent == 0 })
        #expect(Rest.steps(v).of(c)[0].costs == [ResourceAmount(resource: .gold, amount: 301)])
    }

    @Test func Q3_reductionFinieNeSAppliquePlus() {
        let fin = Rest.date.addingTimeInterval(1000)
        let profil = Profile(builderReduction: Reduction(percent: 50, endsAt: fin))
        let v = Rest.village([e(c, 2)])
        // Une seconde avant la fin : appliquée. À la fin et après : plein tarif.
        #expect(Rest.steps(v, profil, now: fin.addingTimeInterval(-1)).of(c)[0].duration == 15)
        #expect(Rest.steps(v, profil, now: fin).of(c)[0].duration == 30)
        #expect(Rest.steps(v, profil, now: fin.addingTimeInterval(86_400)).of(c)[0].costs
                == [ResourceAmount(resource: .gold, amount: 301)])
    }

    @Test func Q3_pourcentageHorsBornesRamene() {
        #expect(Reduction(percent: 150, endsAt: .distantFuture).percent(at: Rest.date) == 100)
        #expect(Reduction(percent: -5, endsAt: .distantFuture).percent(at: Rest.date) == 0)
    }

    @Test func Q3_profilSEnregistreEtSeRelit() throws {
        let profil = Profile(builderReduction: Reduction(percent: 20, endsAt: Rest.date),
                             laboratoryReduction: nil)
        let relu = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profil))
        #expect(relu == profil)
    }

    // MARK: - Q4 : sommes

    @Test func Q4_sommesParCategorieEtParRessource() {
        // Canon 1 (×1) : niveaux 2 et 3 = 200 + 301 d'or, 20 + 30 s (le canon au 3 n'a rien). Murs au niveau 1 (×2) : niveau 2 = 2 × 500, 0 s.
        // Troupe niveau 1 : niveau 2 = 500 d'élixir, 100 s. Équipement niveau 2 : niveau 3 = 9 de minerai brillant.
        let v = Rest.village([e(c, 1), e(c, 3), e(Rest.wall, 1, 2), e(Rest.wall, 2, 2)], units: [e(Rest.troop, 1)],
                             other: ["equipment": [e(Rest.gear, 2)]])
        let parCategorie = remainingTotals(by: Rest.steps(v))
        #expect(parCategorie.count == ChantierKit.Category.allCases.count)
        let defenses = parCategorie[.defenses]!
        #expect(defenses.costs[.gold] == 501 && defenses.seconds == 50 && defenses.costs[.elixir] == 0)
        #expect(parCategorie[.walls]!.costs[.gold] == 1000 && parCategorie[.walls]!.seconds == 0)
        #expect(parCategorie[.laboratory]!.costs[.elixir] == 500 && parCategorie[.laboratory]!.seconds == 100)
        #expect(parCategorie[.equipment]!.costs[.shinyOre] == 9 && parCategorie[.equipment]!.costs[.glowyOre] == 0)
        #expect(parCategorie[.traps] == RemainingTotals())
        // Le nombre d'exemplaires multiplie : deux canons au niveau 2, niveau 3 chacun.
        let deux = RemainingTotals(Rest.steps(Rest.village([e(c, 2, 2)])).of(c))
        #expect(deux.costs[.gold] == 602 && deux.seconds == 60)
    }

    @Test func Q4_enCoursComptePourSonTempsSeulement() {
        let v = Rest.village([e(c, 1, timer: 3600), e(c, 3)])
        let t = RemainingTotals(Rest.steps(v).of(c))
        // 3 600 s du minuteur + niveau 3 (30 s) ; or : le niveau 3 seul (301).
        #expect(t.seconds == 3630 && t.costs[.gold] == 301)
    }

    // MARK: - Q5 : poste et prérequis

    @Test func Q5_posteEtPrerequisDeChaquePas() {
        let v = Rest.village([e(c, 1), e(c, 3)], other: ["equipment": [e(Rest.gear, 2)]])
        let s = Rest.steps(v)
        #expect(s.of(c).map(\.worker) == [.builder, .builder])
        #expect(s.of(c).map(\.requires) == [[Requirement(itemID: Rest.th, level: 2)], [Requirement(itemID: Rest.th, level: 3)]])
        #expect(s.of(Rest.troop).allSatisfy { $0.worker == .laboratory })
        #expect(s.of(Rest.gear).allSatisfy { $0.worker == .blacksmith && $0.category == .equipment })
        // Murs : l'autre ressource acceptée est gardée.
        #expect(Rest.steps(Rest.village([e(Rest.wall, 1, 2)])).of(Rest.wall).first?.alternativeResource == .elixir)
    }

    // MARK: - Q6 : fusion pas encore faite

    @Test func Q6_fusionPasFaiteNeDoublePasLeCompteDeSesBatimentsDOrigine() {
        // Ricochet autorisé (niveau 0, ajouté par Village) : il consomme deux canons, qui n'ont à monter
        // que jusqu'au niveau exigé (2). Le canon au niveau 3 n'a plus rien ; celui au niveau 1 fait le 2 seulement.
        let r = Rest.referenceFusion
        let v = Rest.village([e(c, 1), e(c, 3)], reference: r)
        #expect(v.elements(Rest.ricochet).map(\.level) == [0])
        let s = Rest.steps(v, reference: r)
        #expect(s.of(c).levels == [2])
        #expect(s.of(Rest.ricochet).levels == [1])
        // Sans le ricochet à construire : le canon fait 2 et 3.
        #expect(Rest.steps(Rest.village([e(c, 1), e(c, 3)])).of(c).levels == [2, 3])
    }

    @Test func Q6_lesExemplairesLesPlusAvancesSontLesConsommes() {
        // Canons aux niveaux 1 et 2 : le niveau 2 est consommé (déjà au plafond), le niveau 1 fait le 2.
        let r = Rest.referenceFusion
        let s = Rest.steps(Rest.village([e(c, 2), e(c, 1)], reference: r), reference: r).of(c)
        #expect(s.levels == [2] && s[0].count == 1)
    }

    @Test func Q6_groupeScindeQuandSeulUnExemplaireEstConsomme() {
        // Deux ricochets autorisés consommeraient quatre canons ; avec trois canons identiques au niveau 1,
        // les trois sont consommés (plafond 2) : chacun fait le niveau 2, en un seul pas de 3.
        let deux = ReferenceData(items: Rest.referenceFusion.items.map { $0.id == Rest.ricochet
            ? Rest.item(Rest.ricochet, "buildings", .defenses, .builder, counts: [0, 0, 0, 2], max: [0, 0, 0, 1],
                        levels: [(1000, 100, [])], mergedFrom: $0.mergedFrom) : $0 }, maxTownHall: 3)
        let s = Rest.steps(Rest.village([e(c, 1, 3)], reference: deux), reference: deux).of(c)
        #expect(s.levels == [2] && s.map(\.count) == [3])
        // Un seul ricochet, trois canons : deux consommés (pas de niveau 3), un libre (niveaux 2 et 3).
        let r = Rest.referenceFusion
        let t = Rest.steps(Rest.village([e(c, 1, 3)], reference: r), reference: r).of(c)
        #expect(t.map(\.level) == [2, 2, 3] && t.map(\.count) == [2, 1, 1])
    }

    @Test func Q6_exemplaireConsommeDejaEnCoursGardeSonPasEnCours() {
        // Canon 2 → 3 en cours, au-delà du plafond 2 : le minuteur est réel, son pas reste « en cours ».
        let r = Rest.referenceFusion
        let s = Rest.steps(Rest.village([e(c, 2, timer: 500), e(c, 1)], reference: r), reference: r).of(c)
        #expect(s.map(\.level) == [3, 2])
        #expect(s[0].isInProgress && s[0].remaining == 500 && s[1].status == .todo)
    }

    @Test func Q6_fusionFaiteNeChangeRien() {
        // Ricochet présent : V2 a déjà retiré ses canons, les autres gardent tous leurs niveaux.
        let r = Rest.referenceFusion
        let v = Rest.village([e(Rest.ricochet, 1), e(c, 1)], reference: r)
        #expect(v.elements(Rest.ricochet).map(\.level) == [1])
        #expect(Rest.steps(v, reference: r).of(c).levels == [2, 3])
        #expect(Rest.steps(v, reference: r).of(Rest.ricochet).isEmpty)
    }

    // MARK: - Q7 : hors avancement

    @Test func Q7_horsAvancementJamaisDePas() {
        // Assistant (V8), équipement au niveau 1 (V4, non possédé) : aucun pas, même en amélioration.
        let v = Rest.village([e(c, 3, 2)], other: ["helpers": [e(Rest.helper, 1)], "equipment": [e(Rest.gear, 1)]])
        let s = Rest.steps(v)
        #expect(s.of(Rest.helper).isEmpty && s.of(Rest.gear).isEmpty)
        #expect(s.allSatisfy { Rest.reference.item($0.itemID)?.category != nil })
    }

    // MARK: - Export réel : trois éléments écrits à la main

    /// Date du calcul = date de l'export : un minuteur vaut alors exactement son `timer`.
    static let maintenant = Réel.export.date
    static func réel(_ id: Int) -> [UpgradeStep] {
        remainingSteps(of: Réel.village, reference: Réel.reference, profile: Profile(), now: maintenant).of(id)
    }

    @Test func réelHéros_RoiDesBarbares() throws {
        // Roi (28000000) : niveau 85, 85 → 86 en cours (258 572 s), maximum 95 à l'HDV 16.
        // Niveau 86 : en cours, rien à payer. Niveaux 87 à 95 : (coût en élixir noir, durée en s), du fichier de référence.
        let attendu: [(Int, Int, Int)] = [(87, 225_000, 518_400), (88, 235_000, 518_400), (89, 245_000, 518_400),
                                          (90, 255_000, 518_400), (91, 280_000, 604_800), (92, 290_000, 604_800),
                                          (93, 300_000, 604_800), (94, 310_000, 604_800), (95, 320_000, 604_800)]
        let s = Self.réel(28000000)
        #expect(s.levels == [86] + attendu.map(\.0))
        #expect(s[0].status == .inProgress(ends: Réel.export.date.addingTimeInterval(258_572)))
        #expect(s[0].costs.isEmpty && s[0].remaining == 258_572 && s[0].count == 1)
        for (pas, (niveau, coût, durée)) in zip(s.dropFirst(), attendu) {
            #expect(pas.status == .todo && pas.worker == .builder && pas.category == .heroes)
            #expect(pas.costs == [ResourceAmount(resource: .darkElixir, amount: coût)] && pas.duration == durée, "niveau \(niveau)")
        }
        // Prérequis : le niveau 87 demande l'HDV 15 et le Hall des héros 9 ; le niveau 91, l'HDV 16 et le Hall 10.
        #expect(s[1].requires == [Requirement(itemID: 1000001, level: 15), Requirement(itemID: 1000071, level: 9)])
        #expect(s[5].level == 91 && s[5].requires == [Requirement(itemID: 1000001, level: 16), Requirement(itemID: 1000071, level: 10)])
        // Somme : 225+235+245+255+280+290+300+310+320 = 2 460 (milliers) ; 4 × 518 400 + 5 × 604 800 = 5 097 600 s,
        // plus le minuteur : 5 356 172 s.
        let t = RemainingTotals(s)
        #expect(t.costs[.darkElixir] == 2_460_000 && t.seconds == 5_356_172 && t.unknownTimers == 0)
    }

    @Test func réelBatimentEnAmelioration_ArcX() {
        // Arc-X (1000021), 4 au maximum de 11 : deux au niveau 10 en cours (186 233 s et 186 228 s), deux au niveau 11.
        // Chaque exemplaire en cours n'a plus que le niveau 11, déjà payé ; les deux au 11 n'ont rien.
        let s = Self.réel(1000021)
        #expect(s.count == 2 && s.allSatisfy { $0.level == 11 && $0.count == 1 && $0.isInProgress && $0.costs.isEmpty })
        #expect(s.compactMap(\.remaining).sorted() == [186_228, 186_233])
        #expect(s.allSatisfy { $0.requires == [Requirement(itemID: 1000001, level: 16)] && $0.category == .defenses })
        #expect(RemainingTotals(s).seconds == 372_461 && RemainingTotals(s).costs[.gold] == 0)
    }

    @Test func réelMurs() {
        // 325 murs : 225 au niveau 16, 100 au niveau 17 (maximum 17). Un seul pas : le niveau 17 des 225,
        // 5 000 000 d'or chacun (ou d'élixir), sans durée. 225 × 5 000 000 = 1 125 000 000.
        let s = Self.réel(1000010)
        #expect(s.count == 1)
        #expect(s[0].level == 17 && s[0].count == 225 && s[0].status == .todo && s[0].category == .walls)
        #expect(s[0].costs == [ResourceAmount(resource: .gold, amount: 5_000_000)] && s[0].alternativeResource == .elixir)
        #expect(s[0].duration == 0 && s[0].requires == [Requirement(itemID: 1000001, level: 16)])
        #expect(RemainingTotals(s).costs[.gold] == 1_125_000_000 && RemainingTotals(s).seconds == 0)
    }

    @Test func réelTotauxParCategorieEtParRessource() {
        // Calculés à part, à la main depuis reference.json et l'export (script de contrôle indépendant, voir la PR).
        let s = remainingSteps(of: Réel.village, reference: Réel.reference, profile: Profile(), now: Self.maintenant)
        let parCategorie = remainingTotals(by: s)
        func attendu(_ c: ChantierKit.Category, _ gold: Int = 0, _ elixir: Int = 0, _ dark: Int = 0, _ shiny: Int = 0,
                     _ glowy: Int = 0, _ starry: Int = 0, secondes: Int) -> RemainingTotals {
            RemainingTotals(costs: [.gold: gold, .elixir: elixir, .darkElixir: dark, .shinyOre: shiny, .glowyOre: glowy,
                                    .starryOre: starry], seconds: secondes, unknownTimers: 0)
        }
        #expect(parCategorie[.defenses] == attendu(.defenses, 162_000_000, secondes: 8_969_261))
        #expect(parCategorie[.economy] == attendu(.economy, 118_000_000, 182_000_000, secondes: 12_258_365))
        #expect(parCategorie[.traps] == attendu(.traps, 231_500_000, secondes: 7_473_600))
        #expect(parCategorie[.walls] == attendu(.walls, 1_125_000_000, secondes: 0))
        #expect(parCategorie[.heroes] == attendu(.heroes, 0, 58_500_000, 9_700_000, secondes: 24_807_626))
        #expect(parCategorie[.laboratory] == attendu(.laboratory, 0, 723_200_000, 5_961_500, secondes: 64_668_418))
        #expect(parCategorie[.pets] == attendu(.pets, 0, 0, 10_625_000, secondes: 33_360_374))
        #expect(parCategorie[.equipment] == attendu(.equipment, 0, 0, 0, 512_560, 39_900, 3_460, secondes: 0))
        let total = RemainingTotals(s)
        #expect(total.costs == [.gold: 1_636_500_000, .elixir: 963_700_000, .darkElixir: 26_286_500,
                                .shinyOre: 512_560, .glowyOre: 39_900, .starryOre: 3_460])
        #expect(total.seconds == 151_537_644)
    }

    @Test func réelAucunPasHorsAvancementNiAuDelaDuMaximum() {
        let s = remainingSteps(of: Réel.village, reference: Réel.reference, profile: Profile(), now: Self.maintenant)
        #expect(s.allSatisfy { Réel.reference.item($0.itemID)?.category != nil })
        let maxima = Dictionary(Réel.village.elements.map { ($0.itemID, $0.maxLevel) }, uniquingKeysWith: max)
        #expect(s.allSatisfy { $0.level <= maxima[$0.itemID]! && $0.level >= 1 })
        // Rien de l'HDV : il est au maximum de l'HDV 16.
        #expect(s.of(Village.townHallID).isEmpty)
    }

    // MARK: - Affichage (Lisible)

    @Test func lisible_dureeEnJoursEtHeures() {
        let n = "\u{00A0}"
        #expect(Lisible.duree(5_356_172) == "61" + n + "j" + n + "23" + n + "h")      // 61 j 23 h 49 min : minutes tues au-delà d'un jour
        #expect(Lisible.duree(151_537_644) == "1\u{202F}753" + n + "j" + n + "21" + n + "h")
        #expect(Lisible.duree(86_400) == "1" + n + "j")
        #expect(Lisible.duree(19_200) == "5" + n + "h" + n + "20" + n + "min")
        #expect(Lisible.duree(720) == "12" + n + "min" && Lisible.duree(0) == "moins d'une" + n + "min")
    }

    @Test func lisible_montants() {
        let n = "\u{00A0}"
        #expect(Lisible.montant(512_560) == "512\u{202F}560" && Lisible.montant(3_460) == "3\u{202F}460")
        #expect(Lisible.montant(162_000_000) == "162" + n + "M" && Lisible.montant(723_200_000) == "723,2" + n + "M")
        #expect(Lisible.montant(1_636_500_000) == "1,64" + n + "Md")
        #expect(Lisible.cout(26_286_500, .darkElixir) == "26,29" + n + "M" + n + "d'élixir" + n + "noir")
        #expect(Lisible.cout(512_560, .shinyOre) == "512\u{202F}560" + n + "de" + n + "minerai" + n + "brillant")
    }

    @Test func lisible_resumeEnCoursSansCoutEtMinuteurIllisible() {
        // Roi réel : minuteur de 258 572 s puis neuf niveaux. Arc-X : deux en cours (372 461 s), rien à payer.
        let n = "\u{00A0}"
        #expect(Lisible.resume(Self.réel(28000000)) == "Reste 61" + n + "j" + n + "23" + n + "h · 2,46" + n + "M" + n + "d'élixir" + n + "noir")
        #expect(Lisible.resume(Self.réel(1000021)) == "Reste 4" + n + "j" + n + "7" + n + "h · rien à payer")
        let illisible = ExportEntry(id: Rest.cannon, level: 2, count: 1, timer: nil, extras: ["timer": .string("?")])
        let seul = Rest.steps(Rest.village([illisible, e(Rest.cannon, 3)]))
        #expect(Lisible.resume(seul.of(Rest.cannon)) == "Fin du minuteur inconnue · rien à payer")
        #expect(Lisible.resume([]) == nil)
        // Murs : pas de durée, un coût, pour 225 exemplaires.
        #expect(Lisible.resume(Self.réel(1000010), exemplaires: 225) == "À payer 1,13" + n + "Md" + n + "d'or (pour les 225)")
    }

    @Test func lisible_mentionDeLaReductionSeulementTantQuElleCourt() {
        let fin = Rest.date.addingTimeInterval(100)
        let profil = Profile(builderReduction: Reduction(percent: 20, endsAt: fin))
        #expect(Lisible.reductions(Profile(), at: Rest.date) == nil)
        #expect(Lisible.reductions(profil, at: Rest.date) == "Avec la réduction actuelle : ouvriers −20\u{00A0}%.")
        #expect(Lisible.reductions(profil, at: fin) == nil)
    }
}
