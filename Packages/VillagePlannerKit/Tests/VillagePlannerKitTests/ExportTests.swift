import Foundation
import Testing
@testable import VillagePlannerKit

// Lecteur d'export (T03). Le contrat des résultats est Fixtures/LISEZMOI.md.

enum Fixtures {
    static func texte(_ nom: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: nom, withExtension: "json", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func lire(_ nom: String) throws -> VillageExport {
        try VillageExport.parse(texte(nom))
    }
}

extension VillageExport {
    func entrée(_ section: String, _ id: Int) -> ExportEntry? {
        sections[section]?.first { $0.id == id }
    }
}

/// Générateur à graine fixe (SplitMix64) : mêmes tirages à chaque exécution.
struct GénérateurGraine: RandomNumberGenerator {
    var état: UInt64
    mutating func next() -> UInt64 {
        état &+= 0x9E37_79B9_7F4A_7C15
        var z = état
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Export réel

@Suite struct ExportRéelTests {
    @Test func réelHdv16CompteExact() throws {
        let e = try Fixtures.lire("reel-hdv16")
        #expect(e.warnings.isEmpty)
        #expect(e.tag == "#2PP")
        #expect(e.date == Date(timeIntervalSince1970: 1_794_414_482))

        let b = try #require(e.sections["buildings"])
        #expect(b.count == 46)
        #expect(b.reduce(0) { $0 + $1.count } == 420)
        #expect(b.filter { $0.id == 1_000_010 }.reduce(0) { $0 + $1.count } == 325)
        #expect(e.sections["traps"]?.reduce(0) { $0 + $1.count } == 44)
        #expect(e.sections["units"]?.count == 30)
        #expect(e.sections["siege_machines"]?.count == 7)
        #expect(e.sections["spells"]?.count == 17)
        let heroes = try #require(e.sections["heroes"])
        #expect(heroes.count == 6)
        #expect(heroes.filter { $0.timer != nil }.count == 3)
        let pets = try #require(e.sections["pets"])
        #expect(pets.count == 8)
        #expect(pets.filter { $0.timer != nil }.count == 1)
        #expect(e.sections["equipment"]?.count == 41)
        #expect(e.sections["helpers"]?.count == 3)

        let principales = ["buildings", "traps", "units", "siege_machines", "spells", "heroes", "pets", "equipment", "helpers"]
        func minuteurs(_ l: [ExportEntry]) -> Int { l.reduce(0) { $0 + ($1.timer == nil ? 0 : 1) + minuteurs($1.children) } }
        #expect(principales.reduce(0) { $0 + minuteurs(e.sections[$1] ?? []) } == 8)
    }

    @Test func cntAbsentVautUnEtMinuteurLu() throws {
        let e = try Fixtures.lire("reel-hdv16")
        let enAmélioration = try #require(e.sections["buildings"]?.first { $0.timer == 186_233 })
        #expect(enAmélioration.count == 1)
        #expect(enAmélioration.level == 10)
        let murs = try #require(e.sections["buildings"]).filter { $0.id == 1_000_010 }
        #expect(murs.map(\.count) == [225, 100])
    }

    @Test func typesEtModulesDeviennentDesEnfants() throws {
        let e = try Fixtures.lire("reel-hdv16")
        let atelier = try #require(e.entrée("buildings", 1_000_097))
        #expect(atelier.level == nil)
        #expect(atelier.children.map(\.id) == [103_000_011, 103_000_012, 103_000_013])
        #expect(atelier.children[0].children.map(\.id) == [102_000_033, 102_000_034, 102_000_035])
        #expect(atelier.children[0].children.map(\.level) == [1, 2, 1])
        #expect(atelier.extras["types"] == nil && atelier.extras["modules"] == nil)
    }

    @Test func champsAnnexesConservésDansExtras() throws {
        let e = try Fixtures.lire("reel-hdv16")
        #expect(e.entrée("buildings", 1_000_001)?.extras["weapon"] == .number(1))
        let aveGearUp = try #require(e.sections["buildings"]?.first { $0.id == 1_000_008 && $0.count == 1 })
        #expect(aveGearUp.extras["gear_up"] == .number(1))
        #expect(e.entrée("helpers", 93_000_000)?.extras["helper_cooldown"] == .number(9790))
        #expect(e.entrée("heroes", 28_000_000) != nil)
    }

    @Test func décorationsSansNiveauEtListesDIdentifiants() throws {
        let e = try Fixtures.lire("reel-hdv16")
        #expect(e.sections["decos"]?.allSatisfy { $0.level == nil } == true)
        #expect(e.idLists["skins"]?.count == 14)
        #expect(e.idLists["house_parts"]?.count == 29)
        #expect(e.sections["buildings2"]?.reduce(0) { $0 + $1.count } == 235)
        #expect(e.boosts["clocktower_cooldown"] != nil)
    }
}

// MARK: - Exports abîmés

@Suite struct ExportAbîmésTests {
    @Test func abime01Vide() {
        #expect(throws: ExportError.empty) { try Fixtures.lire("abime-01-vide") }
    }

    @Test func abime02Tronqué() {
        #expect(throws: ExportError.notJSON) { try Fixtures.lire("abime-02-tronque") }
    }

    @Test func abime03PasUnExport() {
        #expect(throws: ExportError.notAVillageExport) { try Fixtures.lire("abime-03-pas-un-export") }
    }

    @Test func abime04SansTimestamp() {
        #expect(throws: ExportError.notAVillageExport) { try Fixtures.lire("abime-04-sans-timestamp") }
    }

    /// Un export abîmé sur un seul élément : cet élément disparaît, tout le reste est intact.
    private func vérifierÉcarté(_ nom: String, section: String, id: Int, champ: String) throws {
        let sain = try Fixtures.lire("reel-hdv16")
        let e = try Fixtures.lire(nom)
        #expect(e.entrée(section, id) == nil)
        #expect(sain.entrée(section, id) != nil)
        #expect(e.warnings.count == 1)
        let w = try #require(e.warnings.first)
        #expect(w.kind == .entryDropped)
        #expect(w.section == section && w.id == id && w.field == champ)
        for (clé, entrées) in sain.sections {
            let attendu = clé == section ? entrées.filter { $0.id != id } : entrées
            #expect(e.sections[clé] == attendu, "section \(clé)")
        }
        #expect(e.idLists == sain.idLists && e.boosts == sain.boosts && e.date == sain.date)
    }

    @Test func abime05NiveauNégatif() throws {
        try vérifierÉcarté("abime-05-niveau-negatif", section: "units", id: 4_000_000, champ: "lvl")
    }

    @Test func abime06CntZéro() throws {
        try vérifierÉcarté("abime-06-cnt-zero", section: "traps", id: 12_000_000, champ: "cnt")
    }

    @Test func abime07LvlTexte() throws {
        try vérifierÉcarté("abime-07-lvl-texte", section: "heroes", id: 28_000_000, champ: "lvl")
    }

    @Test func abime08CinqMoRefuséSansDécodage() throws {
        let texte = try Fixtures.texte("abime-08-5mo")
        #expect(texte.utf8.count > 5_000_000)
        #expect(throws: ExportError.tooLarge) { try VillageExport.parse(texte) }
    }

    @Test func tropGrosEstRefuséAvantTouteLecture() {
        // Pas du JSON : si le texte était décodé, l'erreur serait notJSON.
        let pasDuJSON = String(repeating: "x", count: VillageExport.maxBytes + 1)
        #expect(throws: ExportError.tooLarge) { try VillageExport.parse(pasDuJSON) }
        #expect(throws: ExportError.notJSON) { try VillageExport.parse(String(repeating: "x", count: VillageExport.maxBytes)) }
    }

    @Test func exigencesMinimales() throws {
        #expect(throws: ExportError.notAVillageExport) { try VillageExport.parse(#"{"timestamp":1}"#) }
        #expect(throws: ExportError.notAVillageExport) { try VillageExport.parse(#"{"spells":[]}"#) }
        #expect(throws: ExportError.notAVillageExport) { try VillageExport.parse(#"{"timestamp":"1","spells":[]}"#) }
        #expect(throws: ExportError.notAVillageExport) { try VillageExport.parse(#"[1,2]"#) }
        #expect(throws: ExportError.notAVillageExport) { try VillageExport.parse(#""texte""#) }
        #expect(throws: ExportError.notJSON) { try VillageExport.parse("pas du json") }
        let e = try VillageExport.parse(#"{"timestamp":1,"spells":[]}"#)
        #expect(e.tag == nil && e.warnings.isEmpty && e.sections["spells"] == [])
    }

    @Test func espacesEtBOMAutour() throws {
        _ = try VillageExport.parse("\u{FEFF}\n  " + #"{"timestamp":1,"spells":[]}"# + "\n\n")
    }
}

// MARK: - Exports d'une version future

@Suite struct ExportFuturTests {
    @Test func futur01SectionInconnue() throws {
        let e = try Fixtures.lire("futur-01-section-inconnue")
        #expect(e.entrée("guardians_futurs", 99_000_000)?.level == 1)
        #expect(e.warnings.count == 1)
        let w = try #require(e.warnings.first)
        #expect(w.kind == .unknownSection && w.section == "guardians_futurs")
    }

    @Test func futur02IdentifiantInconnuSansAvertissementDuLecteur() throws {
        // L'avertissement « identifiant inconnu » viendra du Village (T05).
        let e = try Fixtures.lire("futur-02-identifiant-inconnu")
        #expect(e.entrée("units", 77_777_777) != nil)
        #expect(e.sections["units"]?.last?.id == 77_777_777)
        #expect(e.warnings.isEmpty)
    }

    @Test func futur03ChampInconnuConservé() throws {
        let e = try Fixtures.lire("futur-03-champ-inconnu")
        let héros = try #require(e.sections["heroes"]?.first)
        #expect(héros.extras["champ_futur"] == .object(["a": .number(1)]))
        #expect(héros.timer == 258_572)
        #expect(e.warnings.isEmpty)
    }

    @Test func futur04Hdv99() throws {
        let e = try Fixtures.lire("futur-04-hdv-99")
        #expect(e.entrée("buildings", 1_000_001)?.level == 99)
        #expect(e.warnings.isEmpty)
    }

    @Test func futur05Niveau999SansAvertissementDuLecteur() throws {
        let e = try Fixtures.lire("futur-05-niveau-999")
        #expect(e.entrée("units", 4_000_000)?.level == 999)
        #expect(e.warnings.isEmpty)
    }

    @Test func futur06SectionConnueVide() throws {
        let e = try Fixtures.lire("futur-06-section-connue-vide")
        #expect(e.sections["spells"] == [])
        #expect(e.warnings.isEmpty)
    }

    @Test func sectionsInconnuesDeToutesFormesConservées() throws {
        let e = try VillageExport.parse(#"""
        {"timestamp":1,"spells":[],"ids_futurs":[1,2],"scalaire":7,"objet":{"a":[1]},"mixte":[1,"a"],
         "boosts":{"a":3,"b":"x"},"skins":[1,"x",-2],"heroes":{"data":1}}
        """#)
        #expect(e.idLists["ids_futurs"] == [1, 2])
        #expect(e.extras["scalaire"] == .number(7))
        #expect(e.extras["objet"] == .object(["a": .array([.number(1)])]))
        #expect(e.extras["mixte"] == .array([.number(1), .string("a")]))
        #expect(e.extras["heroes"] != nil && e.sections["heroes"] == nil)
        #expect(e.boosts == ["a": 3])
        #expect(e.idLists["skins"] == [1])
        let genres = e.warnings.map(\.kind)
        #expect(genres.filter { $0 == .unknownSection }.count == 4)
        #expect(genres.contains(.malformedSection))
    }

    @Test func sectionInconnueSansDataEntierGardéeBruteSansRienÉcarter() throws {
        let e = try VillageExport.parse(#"""
        {"timestamp":1,"spells":[],"zz":[{"id":5,"x":1}],"zm":[{"data":1,"lvl":2},{"id":5}],
         "zo":{"x":1},"zn":[{"data":"1"}],"zi":[1,-2]}
        """#)
        #expect(e.extras["zz"] == .array([.object(["id": .number(5), "x": .number(1)])]))
        #expect(e.extras["zm"] == .array([.object(["data": .number(1), "lvl": .number(2)]), .object(["id": .number(5)])]))
        #expect(e.extras["zo"] == .object(["x": .number(1)]))
        #expect(e.extras["zn"] != nil && e.extras["zi"] != nil)
        for clé in ["zz", "zm", "zo", "zn", "zi"] { #expect(e.sections[clé] == nil && e.idLists[clé] == nil) }
        #expect(e.warnings.count == 5)
        #expect(e.warnings.allSatisfy { $0.kind == .unknownSection })
    }

    @Test func bornesDeCntLvlEtTimerAuxDeuxBords() throws {
        func lire(_ champs: String) throws -> VillageExport {
            try VillageExport.parse(#"{"timestamp":1,"buildings":[{"data":7,\#(champs)}]}"#)
        }
        let dix_ans = 10 * 365 * 86_400
        // Bord haut accepté
        let ok = try #require(try lire(#""lvl":100000,"cnt":100000,"timer":\#(dix_ans)"#).sections["buildings"]?.first)
        #expect(ok.level == 100_000 && ok.count == 100_000 && ok.timer == dix_ans)
        #expect(try lire(#""lvl":0"#).sections["buildings"]?.first?.level == 0)
        // Un cran au-dessus : lvl et cnt écartent l'élément, comme une valeur invalide
        for (champ, texte) in [("lvl", #""lvl":100001"#), ("cnt", #""lvl":1,"cnt":100001"#)] {
            let e = try lire(texte)
            #expect(e.sections["buildings"] == [])
            #expect(e.warnings.map(\.kind) == [.entryDropped])
            #expect(e.warnings.first?.id == 7 && e.warnings.first?.field == champ)
        }
        // Minuteur hors bornes : élément gardé, valeur brute dans extras (jamais perdue en silence)
        for brut in [dix_ans + 1, -1] {
            let e = try lire(#""lvl":3,"timer":\#(brut)"#)
            let entrée = try #require(e.sections["buildings"]?.first)
            #expect(entrée.level == 3 && entrée.timer == nil)
            #expect(entrée.extras["timer"] == .number(Double(brut)))
            #expect(e.warnings.map(\.kind) == [.fieldIgnored] && e.warnings.first?.field == "timer")
        }
        let texte = try lire(#""lvl":3,"timer":"bientôt""#)
        #expect(texte.sections["buildings"]?.first?.extras["timer"] == .string("bientôt"))
        // Cohérence avec futur-05 : 999 reste conservé
        #expect(try Fixtures.lire("futur-05-niveau-999").entrée("units", 4_000_000)?.level == 999)
    }

    @Test func nombreDémesuré1e999RefuséCommeJSONInvalide() {
        // Choix accepté : JSONSerialization rejette 1e999, donc tout le texte est notJSON.
        #expect(throws: ExportError.notJSON) {
            try VillageExport.parse(#"{"timestamp":1,"buildings":[{"data":1,"lvl":1e999}]}"#)
        }
    }

    @Test func enfantsTropProfondsConservésSansRécursionInfinie() throws {
        var imbriqué = #"{"data":1,"lvl":1}"#
        for _ in 0..<50 { imbriqué = #"{"data":1,"modules":["# + imbriqué + "]}" }
        let e = try VillageExport.parse(#"{"timestamp":1,"buildings":["# + imbriqué + "]}")
        #expect(e.sections["buildings"]?.count == 1)
        #expect(e.warnings.contains { $0.kind == .fieldIgnored && $0.field == "modules" })
    }

    @Test func avertissementsPlafonnés() throws {
        let junk = Array(repeating: "1", count: 5000).joined(separator: ",")
        let e = try VillageExport.parse(#"{"timestamp":1,"buildings":["# + junk + "]}")
        #expect(e.sections["buildings"] == [])
        #expect(e.warnings.count == Avertissements.maximum + 1)
        #expect(e.warnings.last?.kind == .truncated)
    }
}

// MARK: - Mille variantes aléatoires

@Suite struct ExportVariantesTests {
    static var extrêmes: [Any] { [
        "texte", NSNull(), true, false, -3, 0, 1, 999, 999_999_999_999, Int.max, Int.min,
        1e30, -1e30, 1e308, 3.5, -0.0, [Any](), [1, "a"] as [Any], ["data": 1] as [String: Any], [String: Any](),
    ] }

    static func compter(_ v: Any) -> Int {
        if let a = v as? [Any] { return 1 + a.reduce(0) { $0 + compter($1) } }
        if let o = v as? [String: Any] { return 1 + o.values.reduce(0) { $0 + compter($1) } }
        return 1
    }

    /// Parcours en profondeur dans l'ordre des clés triées ; `cibles` : numéros de nœuds à altérer.
    /// Retourne nil quand le nœud est retiré.
    static func altérer(_ v: Any, _ cibles: Set<Int>, _ n: inout Int, _ rng: inout GénérateurGraine) -> Any? {
        let moi = n
        n += 1
        if cibles.contains(moi) {
            if moi != 0, Int.random(in: 0..<3, using: &rng) == 0 { return nil }
            return extrêmes.randomElement(using: &rng)!
        }
        if let a = v as? [Any] { return a.compactMap { altérer($0, cibles, &n, &rng) } }
        if let o = v as? [String: Any] {
            var sortie: [String: Any] = [:]
            for k in o.keys.sorted() { if let x = altérer(o[k]!, cibles, &n, &rng) { sortie[k] = x } }
            return sortie
        }
        return v
    }

    @Test func milleVariantesNePlantentJamais() throws {
        let base = try JSONSerialization.jsonObject(
            with: Data(Fixtures.texte("reel-hdv16").utf8), options: [.fragmentsAllowed])
        let nœuds = Self.compter(base)
        var rng = GénérateurGraine(état: 0xC0FFEE)
        var lectures = 0, erreurs: [ExportError: Int] = [:], avertissements = 0

        for _ in 0..<1000 {
            var cibles = Set<Int>()
            for _ in 0..<Int.random(in: 1...6, using: &rng) { cibles.insert(Int.random(in: 0..<nœuds, using: &rng)) }
            var n = 0
            let variante = Self.altérer(base, cibles, &n, &rng) ?? NSNull()
            let données = try JSONSerialization.data(withJSONObject: variante, options: [.fragmentsAllowed])
            do {
                let e = try VillageExport.parse(String(decoding: données, as: UTF8.self))
                lectures += 1
                avertissements += e.warnings.count
                for entrée in e.sections.values.joined() { Self.vérifier(entrée) }
                #expect(e.boosts.values.allSatisfy { abs($0) <= 1 << 53 })
            } catch {
                erreurs[error, default: 0] += 1
            }
        }
        // Le tirage doit vraiment exercer les deux issues, sinon le test ne prouve rien.
        #expect(lectures > 300, "lectures réussies : \(lectures)")
        #expect(avertissements > 100, "avertissements : \(avertissements)")
        #expect(erreurs.values.reduce(0, +) > 0, "aucune erreur tirée")
        #expect(lectures + erreurs.values.reduce(0, +) == 1000)
    }

    static func vérifier(_ e: ExportEntry) {
        #expect(e.count >= 1 && e.id >= 0)
        #expect(e.count <= 100_000)
        #expect(e.level.map { (0...100_000).contains($0) } ?? true)
        #expect(e.timer.map { (0...315_360_000).contains($0) } ?? true)
        e.children.forEach(vérifier)
    }

    @Test func texteTronquéOuCorrompuNePlantePas() throws {
        let base = Array(try Fixtures.texte("reel-hdv16").utf8)
        var rng = GénérateurGraine(état: 42)
        for _ in 0..<300 {
            var octets = Array(base.prefix(Int.random(in: 0...base.count, using: &rng)))
            for _ in 0..<Int.random(in: 0...3, using: &rng) where !octets.isEmpty {
                octets[Int.random(in: 0..<octets.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng)
            }
            _ = try? VillageExport.parse(String(decoding: octets, as: UTF8.self))
        }
    }
}

// MARK: - Vitesse

/// Temps processeur du fil courant, en ms : insensible à la charge de la machine (contrairement à l'horloge murale).
func tempsCPUFilCourant() -> Double {
    var t = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
    return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6
}

/// Médiane (ms de temps processeur) de `passages` exécutions de `corps`, toutes sur le fil appelant.
func medianeCPU(passages: Int = 11, _ corps: () throws -> Void) rethrows -> Double {
    var durées: [Double] = []
    for _ in 0..<passages {
        let debut = tempsCPUFilCourant()
        try corps()
        durées.append(tempsCPUFilCourant() - debut)
    }
    return durées.sorted()[passages / 2]
}
