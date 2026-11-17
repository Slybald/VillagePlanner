import Foundation
import Testing
@testable import VillagePlannerKit

// Avancement (T05) : règles A1 à A5 du PLAN §5.1. Référence inventée : `Mini` (VillageTests.swift).

@Suite struct AvancementTests {
    func report(_ v: Village, _ r: ReferenceData = Mini.reference) -> ProgressReport { progress(of: v, reference: r) }

    // MARK: - Règles

    @Test func A1_poidsEstLaDuree() {
        // Canon au niveau 1 (en retard) : niveaux 2 et 3 à faire, 20 + 30 ; canon au 3 : niveau 3 fait, 30.
        #expect(report(Mini.late).categories[.defenses] == Progress(done: 30, total: 80, unit: .seconds))
    }

    @Test func A1_dureesToutesNullesPoidsUn() {
        let bombe = Mini.item(Mini.bomb, "traps", .traps, counts: [0, 0, 2, 2], max: [0, 0, 1, 2], weights: [0, 0])
        let ref = ReferenceData(items: [Mini.items[0], bombe], maxTownHall: 3)
        let v = Mini.village([Mini.e(Mini.th, 3)], traps: [Mini.e(Mini.bomb, 1), Mini.e(Mini.bomb, 2)], reference: ref)
        // Deux niveaux 2 à faire, un fait : 1 ÷ 2.
        #expect(report(v, ref).categories[.traps] == Progress(done: 1, total: 2, unit: .levels))
    }

    @Test func A2_mursPoidsCout() {
        // 2 murs au niveau 2 (faits : 2 × 200), 2 à construire (niveaux 1 et 2 : 2 × 300) → 400 ÷ 1 000.
        let v = Mini.village([Mini.e(Mini.th, 3), Mini.e(Mini.wall, 2, 2)])
        #expect(report(v).categories[.walls] == Progress(done: 400, total: 1000, unit: .cost))
    }

    @Test func A3_equipementsUnNiveauVautUn() {
        // Équipement au niveau 3 à l'HDV 3 : niveaux 3 et 4 à faire (base 2), un fait. Durées ignorées.
        let v = Mini.village([Mini.e(Mini.th, 3)], other: ["equipment": [Mini.e(Mini.gear, 3)]])
        #expect(report(v).categories[.equipment] == Progress(done: 1, total: 2, unit: .levels))
    }

    @Test func A4_totalMoyenneDesCategoriesQuiOntQuelqueChoseAFaire() {
        let r = report(Mini.late)
        // Ressources (l'HDV seul), pièges… : rien à cet HDV pour ce qui n'a ni niveau nouveau ni retard.
        #expect(r.categories[.economy]?.hasWork == false)
        #expect(r.categories[.pets]?.hasWork == false)
        // Défenses 0,375 ; murs, pièges, héros 1 → (0,375 + 1 + 1 + 1) ÷ 4.
        #expect(r.total == 0.84375)
        // Aucune catégorie n'a rien à faire : le total vaut 1.
        let vide = ReferenceData(items: [Mini.items[0]], maxTownHall: 3)
        let seul = report(Mini.village([Mini.e(Mini.th, 3)], reference: vide), vide)
        #expect(seul.categories.values.allSatisfy { !$0.hasWork })
        #expect(seul.total == 1)
        #expect(seul.categories.count == VillagePlannerKit.Category.allCases.count)
    }

    @Test func A5_horsAvancementNeComptePas() throws {
        // Assistant (V8), équipement au niveau 1 (V4), identifiant inconnu (V5) : avancement inchangé.
        let autres: [String: [ExportEntry]] = ["helpers": [Mini.e(Mini.helper, 1)], "equipment": [Mini.e(Mini.gear, 1)],
                                               "units": [Mini.e(77777777, 3)]]
        let v = Mini.village(Mini.finishedBuildings, traps: [Mini.e(Mini.bomb, 2)], heroes: [Mini.e(Mini.king, 2)], other: autres)
        #expect(v.status == .staleReference)
        #expect(report(v) == report(Mini.finished))
        // V7 : aucun pourcentage.
        let hdv4 = Mini.village([Mini.e(Mini.th, 4)])
        #expect(report(hdv4).total == nil && report(hdv4).categories.isEmpty)
    }

    @Test func ameliorationEnCoursNeComptePasCommeFaite() {
        // Canon 2 → 3 en cours : le niveau 3 n'est pas fait avant la fin.
        let v = Mini.village([Mini.e(Mini.th, 3), Mini.e(Mini.cannon, 2, timer: 3600), Mini.e(Mini.cannon, 3)])
        #expect(v.elements(Mini.cannon).first { $0.level == 2 }?.upgradeEnds == Mini.date.addingTimeInterval(3600))
        #expect(report(v).categories[.defenses] == Progress(done: 30, total: 60, unit: .seconds))
        // Réel : le Roi 85 → 86 en cours ; aucun des niveaux 86 à 95 n'est fait.
        let roi = try! #require(Réel.village.elements(28000000).first)
        #expect(roi.upgrading && roi.level == 85)
    }

    @Test func chaqueAvancementEntre0Et1() throws {
        let r = Réel.reference
        var villages = [Réel.village, Mini.justUpgraded, Mini.finished, Mini.late]
        for nom in ["futur-02-identifiant-inconnu", "futur-03-champ-inconnu", "futur-05-niveau-999", "futur-06-section-connue-vide"] {
            villages.append(Village(export: try Fixtures.lire(nom), reference: r))
        }
        for v in villages {
            let p = progress(of: v, reference: v.townHall > 3 ? r : Mini.reference)
            #expect(p.categories.count == VillagePlannerKit.Category.allCases.count)
            for c in p.categories.values { #expect((0...1).contains(c.fraction) && c.done <= c.total && c.done >= 0) }
            let total = try #require(p.total)
            #expect((0...1).contains(total))
        }
    }

    // MARK: - Calcul à la main sur reel-hdv16.json (détail dans la PR)

    @Test func calculALaMainHerosMursPieges() {
        let p = progress(of: Réel.village, reference: Réel.reference)
        // Héros : Reine 91 et 92 faits (2 × 604 800 s), Gardien 66 et 67 faits (2 × 604 800 s).
        #expect(p.categories[.heroes] == Progress(done: 2_419_200, total: 28_425_600, unit: .seconds))
        // Murs : niveau 17 à 5 000 000 d'or ; 100 faits sur 325.
        #expect(p.categories[.walls] == Progress(done: 500_000_000, total: 1_625_000_000, unit: .cost))
        // Pièges : 39 pièges ont un niveau à faire, aucun n'est fait.
        #expect(p.categories[.traps] == Progress(done: 0, total: 7_473_600, unit: .seconds))
    }

    @Test func reelHdv16ValeursFigees() {
        let p = progress(of: Réel.village, reference: Réel.reference)
        #expect(p.categories[.equipment] == Progress(done: 0, total: 191, unit: .levels))
        #expect(p.categories.values.allSatisfy { $0.hasWork })
        let attendu = [VillagePlannerKit.Category.defenses: 11_102_400.0 / 20_736_000, .traps: 0, .economy: 4_579_200.0 / 17_409_600,
                       .walls: 500.0 / 1625, .heroes: 2_419_200.0 / 28_425_600, .laboratory: 3_369_600.0 / 68_630_400,
                       .pets: 0, .equipment: 0]
        for (c, f) in attendu {
            let écart = abs(p.categories[c]!.fraction - f)
            #expect(écart < 1e-12, "\(c)")
        }
        let écartTotal = abs(p.total! - attendu.values.reduce(0, +) / 8)
        #expect(écartTotal < 1e-12)
    }

    // MARK: - Trois villages inventés

    @Test func villageToutJustePasseAuNouvelHdv() {
        let r = report(Mini.justUpgraded)
        // Défenses 0 ÷ 60, murs 0 ÷ 1 000, pièges 0 ÷ 50, héros 0 ÷ 60 ; l'HDV seul : rien à faire.
        for c in [VillagePlannerKit.Category.defenses, .walls, .traps, .heroes] {
            #expect(r.categories[c]?.hasWork == true && r.categories[c]?.fraction == 0)
        }
        #expect(r.categories[.walls]?.total == 1000)
        #expect(r.categories[.economy]?.hasWork == false)
        #expect(r.total == 0)
    }

    @Test func villageTermine() {
        let r = report(Mini.finished)
        #expect(r.categories.values.filter(\.hasWork).allSatisfy { $0.fraction == 1 })
        #expect(r.categories.values.filter(\.hasWork).count == 4)
        #expect(r.total == 1)
    }

    @Test func villageEnRetardSurLHdvPrecedent() {
        let r = report(Mini.late)
        // Le retard s'ajoute au chemin : 30 ÷ 80 au lieu de 30 ÷ 60.
        #expect(r.categories[.defenses]?.fraction == 0.375)
        #expect(r.total == 0.84375)
    }
}
