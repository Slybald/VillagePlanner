import Foundation
import Testing
@testable import ChantierKit

// Village (T05) : règles V1 à V8 du PLAN §5.0.

/// Une petite référence inventée, calculable de tête. HDV 1 à 3.
enum Mini {
    static let th = 1000001, cannon = 1000008, wall = 1000010, bomb = 12000000, king = 28000000
    static let ricochet = 1000085, gear = 90000000, helper = 93000000

    /// `weights` : durée (ou coût, pour les murs) des niveaux 1, 2, 3…
    static func item(_ id: Int, _ section: String, _ category: ChantierKit.Category?, counts: [Int], max: [Int],
                     weights: [Int], cost: Bool = false, mergedFrom: [Requirement] = []) -> ReferenceItem {
        let levels = weights.enumerated().map { i, w in
            ReferenceLevel(level: i + 1, costs: cost ? [ResourceAmount(resource: .gold, amount: w)] : [],
                           duration: cost ? 0 : w, requires: [])
        }
        return ReferenceItem(id: id, names: ["en": "#\(id)"], section: section, category: category,
                             exclusion: category == nil ? .helper : nil, worker: .builder, levels: levels,
                             countByTownHall: counts, maxLevelByTownHall: max, mergedFrom: mergedFrom)
    }

    static let items = [
        item(th, "buildings", .economy, counts: [0, 1, 1, 1], max: [0, 1, 2, 3], weights: [0, 100, 200]),
        item(cannon, "buildings", .defenses, counts: [0, 1, 2, 2], max: [0, 1, 2, 3], weights: [10, 20, 30]),
        item(wall, "buildings", .walls, counts: [0, 0, 2, 4], max: [0, 0, 1, 2], weights: [100, 200], cost: true),
        item(bomb, "traps", .traps, counts: [0, 0, 1, 1], max: [0, 0, 1, 2], weights: [5, 50]),
        item(king, "heroes", .heroes, counts: [0, 0, 0, 1], max: [0, 0, 0, 2], weights: [0, 60]),
        item(gear, "equipment", .equipment, counts: [0, 1, 1, 1], max: [0, 0, 2, 4], weights: [999, 999, 999, 999]),
        item(helper, "helpers", nil, counts: [0, 1, 1, 1], max: [0, 1, 2, 3], weights: [50, 50, 50]),
    ]
    static let reference = ReferenceData(items: items, maxTownHall: 3)
    static let date = Date(timeIntervalSince1970: 1_000_000)

    static func village(_ buildings: [ExportEntry], traps: [ExportEntry] = [], heroes: [ExportEntry] = [],
                        other: [String: [ExportEntry]] = [:], reference: ReferenceData = reference) -> Village {
        var sections = other
        sections["buildings"] = buildings
        sections["traps"] = traps
        sections["heroes"] = heroes
        let export = VillageExport(tag: "#2PP", date: date, sections: sections, idLists: [:], boosts: [:], warnings: [])
        return Village(export: export, reference: reference)
    }

    static func e(_ id: Int, _ level: Int, _ count: Int = 1, timer: Int? = nil) -> ExportEntry {
        ExportEntry(id: id, level: level, count: count, timer: timer)
    }

    /// Tout juste passé à l'HDV 3 : tout au maximum de l'HDV 2.
    static let justUpgraded = village([e(th, 3), e(cannon, 2, 2), e(wall, 1, 2)], traps: [e(bomb, 1)])
    /// Tout au maximum de l'HDV 3.
    static let finishedBuildings = [e(th, 3), e(cannon, 3, 2), e(wall, 2, 4)]
    static let finished = village(finishedBuildings, traps: [e(bomb, 2)], heroes: [e(king, 2)])
    /// HDV 3, un canon resté au niveau 1, sous le maximum de l'HDV 2.
    static let late = village([e(th, 3), e(cannon, 1), e(cannon, 3), e(wall, 2, 4)], traps: [e(bomb, 2)],
                              heroes: [e(king, 2)])
}

enum Réel {
    static let reference = try! ReferenceData.load()
    static let export = try! Fixtures.lire("reel-hdv16")
    static let village = Village(export: export, reference: reference)

    static func nom(_ e: Element) -> String { reference.item(e.itemID)?.names["en"] ?? "?" }
    static func total(_ v: Village, _ id: Int) -> Int { v.elements.filter { $0.itemID == id }.reduce(0) { $0 + $1.count } }
}

extension Village {
    func elements(_ id: Int) -> [Element] { elements.filter { $0.itemID == id } }
}

@Suite struct VillageTests {
    // MARK: - Export réel

    @Test func réelHdv16PostesEtAmeliorationsEnCours() throws {
        let v = Réel.village
        #expect(v.townHall == 16)
        #expect(v.status == .ok)
        #expect(v.unknown.isEmpty)
        #expect(v.workers == [.builder: 6, .laboratory: 1, .petHouse: 1, .blacksmith: 1])   // 5 cabanes + B.O.B.
        #expect(Réel.total(v, 1000007) == 1)    // labo
        #expect(Réel.total(v, 1000068) == 1)    // Maison des familiers

        // 8 améliorations en cours, fin = timestamp + timer.
        let enCours = v.elements.filter(\.upgrading)
        #expect(enCours.count == 8)
        let attendu = Réel.export.sections.filter { !$0.key.hasSuffix("2") }.values.joined()
            .compactMap { e in e.timer.map { Réel.export.date.addingTimeInterval(TimeInterval($0)) } }
        #expect(enCours.compactMap(\.upgradeEnds).sorted() == attendu.sorted())
        let roi = try #require(v.elements(28000000).first)
        #expect(roi.level == 85 && roi.upgradeEnds == Date(timeIntervalSince1970: 1_794_414_482 + 258_572))
    }

    // MARK: - Règles

    @Test func V1_batimentsEtPiegesManquantsAuNiveau0() {
        // HDV 3 : 4 murs autorisés, 2 présents → 2 à construire. Canons : 2 autorisés, 2 présents → aucun.
        let v = Mini.justUpgraded
        #expect(v.elements(Mini.wall).filter { $0.level == 0 }.map(\.count) == [2])
        #expect(v.elements(Mini.cannon).allSatisfy { $0.level > 0 })
        // Piège absent : ajouté au niveau 0.
        #expect(Mini.village([Mini.e(Mini.th, 3)]).elements(Mini.bomb).map(\.level) == [0])
        // Réel : rien ne manque parmi les bâtiments et pièges comptés.
        #expect(Réel.village.elements.filter { e in
            let item = Réel.reference.item(e.itemID)!
            return e.level == 0 && item.category != nil && ["buildings", "traps"].contains(item.section)
        }.isEmpty)
    }

    @Test func V2_fusionsRetirentLesExemplairesConsommes() {
        // Réel : 7 − 2 × 2 = 3 Canons, 8 − 2 × 2 = 4 Tours d'archers ; aucun au niveau 0.
        let v = Réel.village
        #expect(v.elements(1000008).allSatisfy { $0.level > 0 })
        #expect(v.elements(1000009).allSatisfy { $0.level > 0 })
        #expect(Réel.total(v, 1000008) == 3)
        #expect(Réel.total(v, 1000009) == 4)
        // Inventé : un Canon ricochet présent consomme les deux canons autorisés.
        let ricochet = Mini.item(Mini.ricochet, "buildings", .defenses, counts: [0, 0, 0, 1], max: [0, 0, 0, 1],
                                 weights: [40], mergedFrom: [Requirement(itemID: Mini.cannon, level: 3),
                                                             Requirement(itemID: Mini.cannon, level: 3)])
        let ref = ReferenceData(items: Mini.items + [ricochet], maxTownHall: 3)
        #expect(Mini.village([Mini.e(Mini.th, 3), Mini.e(Mini.ricochet, 1)], reference: ref).elements(Mini.cannon).isEmpty)
    }

    @Test func V3_deblocablesAbsentsAuNiveau0() {
        // Réel : liste jointe à la PR. Aucune super-troupe, troupe saisonnière ni d'événement.
        let ajoutés = Réel.village.elements.filter {
            $0.level == 0 && Village.unlockSections.contains(Réel.reference.item($0.itemID)!.section)
        }
        #expect(Set(ajoutés.map(Réel.nom)) == ["Thrower", "Troop Launcher", "Angry Spell", "Spirit Fox", "Angry Jelly"])
        #expect(ajoutés.allSatisfy { $0.count == 1 && $0.maxLevel > 0 })
        #expect(ajoutés.allSatisfy { Réel.reference.item($0.itemID)!.category != nil })
        // Inventé : le héros déblocable à l'HDV 3 et absent est ajouté au niveau 0.
        #expect(Mini.justUpgraded.elements(Mini.king).map(\.level) == [0])
    }

    @Test func V4_equipementsAuNiveau1Exclus() {
        let équipements = Réel.village.elements.filter { Réel.reference.item($0.itemID)?.category == .equipment }
        #expect(Réel.export.sections["equipment"]?.count == 41)
        #expect(équipements.count == 27)
        #expect(équipements.allSatisfy { $0.level > 1 })
        // Inventé : un équipement au niveau 1 ou absent n'est pas dans le village.
        #expect(Mini.village([Mini.e(Mini.th, 3)], other: ["equipment": [Mini.e(Mini.gear, 1)]]).elements(Mini.gear).isEmpty)
        #expect(Mini.justUpgraded.elements(Mini.gear).isEmpty)
    }

    @Test func V5_identifiantInconnuRangeAPart() throws {
        let r = Réel.reference
        let v = Village(export: try Fixtures.lire("futur-02-identifiant-inconnu"), reference: r)
        #expect(v.unknown.map(\.id) == [77777777])
        #expect(v.elements(77777777).isEmpty)
        #expect(v.status == .staleReference)
        #expect(progress(of: v, reference: r) == progress(of: Réel.village, reference: r))   // exclu des calculs
    }

    @Test func V6_niveauAuDessusDuMaximumConnuCompteTermine() throws {
        let v = Village(export: try Fixtures.lire("futur-05-niveau-999"), reference: Réel.reference)
        #expect(v.status == .staleReference)
        #expect(v.elements(4000000).map(\.level) == [999])
        // Inventé : héros au niveau 99 (maximum connu : 2) → catégorie terminée.
        let mini = Mini.village([Mini.e(Mini.th, 3)], heroes: [Mini.e(Mini.king, 99)])
        #expect(mini.status == .staleReference)
        #expect(progress(of: mini, reference: Mini.reference).categories[.heroes] == Progress(done: 60, total: 60, unit: .seconds))
    }

    @Test func V7_hdvAuDessusDuMaximumConnuSansPourcentage() throws {
        let r = Réel.reference
        let texte = try Fixtures.texte("reel-hdv16")
        // Fabriqué à partir du maximum de la référence : ne se périme pas à la sortie de l'HDV 19.
        let fabriqué = texte.replacingOccurrences(of: #"{"data":1000001,"lvl":16"#,
                                                  with: #"{"data":1000001,"lvl":\#(r.maxTownHall + 1)"#)
        #expect(fabriqué != texte)
        for export in [try VillageExport.parse(fabriqué), try Fixtures.lire("futur-04-hdv-99")] {
            let v = Village(export: export, reference: r)
            #expect(v.status == .unknownTownHall)
            #expect(v.elements.allSatisfy { $0.level > 0 || $0.itemID == 1000097 })   // inventaire seul, rien d'ajouté
            #expect(progress(of: v, reference: r) == ProgressReport())
            #expect(progress(of: v, reference: r).total == nil)
        }
    }

    @Test func V8_horsAvancementLusJamaisComptes() {
        let v = Réel.village
        // Base des ouvriers ignorée : aucun élément présent qui ne vienne du village principal.
        let principal = Set(Village.sections.flatMap { Réel.export.sections[$0] ?? [] }.map(\.id))
        #expect(v.elements.allSatisfy { principal.contains($0.itemID) || $0.level == 0 })
        #expect(!Réel.export.sections["buildings2", default: []].isEmpty)
        // Assistants et Crafting Station lus et gardés ; défenses fabriquées et modules jamais ajoutés.
        #expect(Réel.total(v, 93000000) == 1)
        #expect(Réel.total(v, 1000097) == 1)
        #expect(v.elements.filter { (102000000..<104000000).contains($0.itemID) }.isEmpty)
        // Inventé : un assistant loin de son maximum ne change rien à l'avancement.
        let avec = Mini.village(Mini.finishedBuildings, traps: [Mini.e(Mini.bomb, 2)], heroes: [Mini.e(Mini.king, 2)],
                                other: ["helpers": [Mini.e(Mini.helper, 1)]])
        #expect(avec.elements(Mini.helper).count == 1)
        #expect(progress(of: avec, reference: Mini.reference) == progress(of: Mini.finished, reference: Mini.reference))
    }

    @Test func minuteurIllisibleEnCoursFinInconnue() throws {
        let entrée = ExportEntry(id: Mini.cannon, level: 2, extras: ["timer": .string("bientôt")])
        let v = Mini.village([Mini.e(Mini.th, 3), entrée, Mini.e(Mini.cannon, 3)])
        let canon = try #require(v.elements(Mini.cannon).first { $0.level == 2 })
        #expect(canon.upgrading)
        #expect(canon.upgradeEnds == nil)
        // Jamais compté comme terminé : le niveau 3 du premier canon reste à faire.
        #expect(progress(of: v, reference: Mini.reference).categories[.defenses] == Progress(done: 30, total: 60, unit: .seconds))
    }
}
