import Foundation
import Testing
@testable import ChantierKit
@testable import outils

/// Le reference.json embarqué, contrôlé contre l'export réel anonymisé (HDV 16).
@Suite struct ReferenceTests {
    static let reference = try! ReferenceData.load()
    static let hdv = 16

    /// Les lignes de l'export réel, sections du village principal, `types` et `modules` compris.
    struct Ligne { let section: String; let id: Int; let niveau: Int?; let nombre: Int }
    static let lignes: [Ligne] = {
        let url = Bundle.module.url(forResource: "reel-hdv16", withExtension: "json", subdirectory: "Fixtures")!
        let racine = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        func parcourir(_ e: [String: Any], _ section: String) -> [Ligne] {
            [Ligne(section: section, id: e["data"] as! Int, niveau: e["lvl"] as? Int, nombre: e["cnt"] as? Int ?? 1)]
                + ((e["types"] as? [[String: Any]] ?? []) + (e["modules"] as? [[String: Any]] ?? []))
                .flatMap { parcourir($0, section) }
        }
        return ["buildings", "traps", "units", "siege_machines", "spells", "heroes", "pets", "equipment", "helpers"]
            .flatMap { s in (racine[s] as? [[String: Any]] ?? []).flatMap { parcourir($0, s) } }
    }()
    static func present(_ id: Int) -> Int { lignes.filter { $0.id == id }.reduce(0) { $0 + $1.nombre } }

    @Test func chargementEmbarqueLegerEtRapide() throws {
        let url = try #require(ReferenceData.bundledURL)
        let taille = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(taille < 1_500_000)
        let debut = ContinuousClock.now
        let r = try ReferenceData.load()
        let duree = ContinuousClock.now - debut
        #expect(duree < .milliseconds(100), "chargement en \(duree)")
        #expect(r.items.count > 200 && r.maxTownHall >= 18)
        #expect(r.source.name == "ClashKingInc/ClashKingAssets" && !r.source.date.isEmpty)
    }

    @Test func fichierCorrompuOuAbsentDonneUneErreurTypee() {
        #expect(throws: ReferenceError.corrupt) { try ReferenceData.decode(Data("{\"items\":[".utf8)) }
        #expect(throws: ReferenceError.corrupt) { try ReferenceData.decode(Data("{}".utf8)) }
        #expect(throws: ReferenceError.corrupt) { try ReferenceData.decode(Data()) }
        let futur = #"{"format":99,"maxTownHall":19,"source":{"name":"","license":"","commit":"","date":""},"items":[]}"#
        #expect(throws: ReferenceError.unsupportedFormat(99)) { try ReferenceData.decode(Data(futur.utf8)) }
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID()).json")
        #expect(throws: ReferenceError.missing) { try ReferenceData.load(from: absent) }
    }

    /// Même entrée, mêmes octets : réécrire le fichier embarqué redonne exactement le même fichier.
    @Test func ecritureCanoniqueStable() throws {
        let url = try #require(ReferenceData.bundledURL)
        #expect(try Rapport.encoder(Self.reference) == Data(contentsOf: url))
    }

    @Test func chaqueIdentifiantDeLExportAUnNomEtUnPoste() {
        for l in Self.lignes {
            let classe = l.id / 1_000_000
            guard let item = Self.reference.item(l.id) else {
                // Seule exception permise : une défense fabriquée ou un module d'une autre rotation.
                #expect(classe == 102 || classe == 103, "\(l.section) \(l.id) absent de la référence")
                continue
            }
            #expect(item.names["en"]?.isEmpty == false, "\(l.id) sans nom")
            #expect(item.section == l.section, "\(l.id) : section \(item.section), export \(l.section)")
        }
    }

    @Test func niveauxDeLExportSousLesMaximumsDeLHdv16() {
        for l in Self.lignes {
            guard let niveau = l.niveau, let item = Self.reference.item(l.id) else { continue }
            if item.exclusion == .craftedDefense { continue }          // hors avancement (V8)
            if item.category == .equipment && niveau == 1 { continue } // non possédé (V4)
            #expect(niveau <= item.maxLevel(atTownHall: Self.hdv),
                    "\(l.id) \(item.name) : niveau \(niveau) > max \(item.maxLevel(atTownHall: Self.hdv))")
        }
    }

    @Test func chaqueTypeAUneCategorieOuUneRaisonDEtreHorsAvancement() {
        for i in Self.reference.items {
            #expect((i.category == nil) == (i.exclusion != nil), "\(i.id) \(i.name)")
        }
        #expect(Self.reference.item(4000026)?.exclusion == .superTroop)   // Super Barbarian
        #expect(Self.reference.item(4000030)?.exclusion == .seasonal)     // Ice Wizard
        #expect(Self.reference.item(107000000)?.exclusion == .guardian)   // Longshot
        #expect(Self.reference.item(93000002)?.exclusion == .helper)      // Alchemist
        #expect(Self.reference.item(103000011)?.exclusion == .craftedDefense)
        #expect(Self.reference.item(4000051)?.section == "siege_machines")
    }

    @Test func nombresCumulesParHdv() throws {
        let murs = try #require(Self.reference.item(1000010))
        #expect(Array(murs.countByTownHall[14...18]) == [325, 325, 325, 325, 325])
        #expect(Self.reference.item(1000008)?.count(atTownHall: 16) == 7)   // Canons
        // L'Aigle est consommé par l'HDV 17.
        #expect(Self.reference.item(1000031)?.count(atTownHall: 16) == 1)
        #expect(Self.reference.item(1000031)?.count(atTownHall: 17) == 0)
    }

    @Test func V2_fusionsDesCanonsEtDesToursDArchers() throws {
        let ricochet = try #require(Self.reference.item(1000085))
        let multiArcher = try #require(Self.reference.item(1000084))
        #expect(ricochet.mergedFrom == [Requirement(itemID: 1000008, level: 21), Requirement(itemID: 1000008, level: 21)])
        #expect(multiArcher.mergedFrom == [Requirement(itemID: 1000009, level: 21), Requirement(itemID: 1000009, level: 21)])
        for (base, fusion) in [(1000008, ricochet), (1000009, multiArcher)] {
            let autorises = Self.reference.item(base)!.count(atTownHall: Self.hdv)
            let consommes = Self.present(fusion.id) * fusion.mergedFrom.filter { $0.itemID == base }.count
            #expect(autorises - consommes == Self.present(base), "\(base) : \(autorises) − \(consommes)")
        }
    }

    /// Le maximum suit les chaînes de prérequis : chaque niveau jusqu'au maximum a ses prérequis
    /// à l'HDV donné (labo, Hall des héros, Maison des familiers, Forgeron…), le suivant non.
    @Test func maximumsSuiventLesChainesDePrerequis() {
        let r = Self.reference
        func tient(_ q: Requirement, _ n: Int) -> Bool {
            q.itemID == 1000001 ? q.level <= n : (r.item(q.itemID)?.maxLevel(atTownHall: n) ?? 0) >= q.level
        }
        for n in [Self.hdv, r.maxTownHall] {
            for i in r.items where i.id != 1000001 && i.maxLevel(atTownHall: n) > 0 {
                let max = i.maxLevel(atTownHall: n)
                #expect(i.levels.filter { $0.level <= max }.allSatisfy { $0.requires.allSatisfy { tient($0, n) } },
                        "\(i.id) \(i.name) HDV \(n)")
                if let suivant = i.levels.first(where: { $0.level == max + 1 }) {
                    #expect(!suivant.requires.allSatisfy { tient($0, n) }, "\(i.id) \(i.name) HDV \(n)")
                }
            }
        }
        // Exemple : le Roi barbare plafonne avec le Hall des héros.
        #expect(r.item(28000000)!.levels[0].requires.contains { $0.itemID == 1000071 })
    }

    /// Contrôle dans l'autre sens : ce qui est déblocable à l'HDV 16 et absent de l'export.
    /// Chaque ligne est plausible : le bâtiment qui le débloque n'a pas encore le niveau voulu.
    @Test func deblocableAHdv16EtAbsentDeLExport() {
        let absents = Self.reference.items
            .filter { $0.category != nil && $0.maxLevel(atTownHall: Self.hdv) > 0 && Self.present($0.id) == 0 }
            .map(\.id)
        #expect(absents == [
            4000132,   // Thrower : Casernes niveau 18, l'export en a 17
            4000135,   // Troop Launcher : Atelier niveau 8, l'export en a 7
            26000123,  // Angry Spell : Usine de sorts noirs niveau 8, l'export en a 7
            73000010,  // Spirit Fox : Maison des familiers niveau 9, l'export en a 8
            73000011,  // Angry Jelly : Maison des familiers niveau 10
            90000056,  // Stun Blaster : Forgeron niveau 9, l'export en a 8 (en amélioration)
        ])
    }

    @Test func S6_assistantsMultiplicateurEtDureeParNiveau() throws {
        let apprenti = try #require(Self.reference.item(93000000))
        #expect(apprenti.levels.allSatisfy { $0.helperMultiplier != nil && $0.helperSeconds == 3600 })
        #expect(apprenti.levels.map(\.helperMultiplier) == apprenti.levels.map(\.level))
    }
}
