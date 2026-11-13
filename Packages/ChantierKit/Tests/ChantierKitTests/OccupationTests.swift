import Foundation
import Testing
@testable import ChantierKit

// Taux d'occupation et cap « à ton rythme » (T24) : règles O1 à O7, listées en tête de Occupation.swift.
// Photos inventées, calculables de tête : un HDV 3, une ou deux cabanes d'ouvrier, un canon dont les niveaux 2, 3 et 4
// durent 10 h, 20 h et 40 h, un labo et une troupe de labo. Les dates sont en heures après `Occ.t0`.

enum Occ {
    static let th = 1000001, hut = 1000015, cannon = 1000008, lab = 1000007, troop = 4000000, wall = 1000010
    static let apprentice = 93_000_000
    static let t0 = Date(timeIntervalSince1970: 1_000_000)
    static func h(_ heures: Int) -> Date { t0.addingTimeInterval(TimeInterval(heures * 3600)) }
    static func hours(_ n: Int) -> Int { n * 3600 }

    static func reference(huts: Int = 1) -> ReferenceData {
        ReferenceData(items: [
            Rest.item(th, "buildings", .economy, .builder, counts: [0, 1, 1, 1], max: [0, 1, 2, 3],
                      levels: [(0, 0, []), (0, 0, []), (0, 0, [])]),
            Rest.item(hut, "buildings", .economy, .builder, counts: [0, huts, huts, huts], max: [0, 1, 1, 1],
                      levels: [(0, 0, [])]),
            Rest.item(cannon, "buildings", .defenses, .builder, counts: [0, 1, 1, 1], max: [0, 4, 4, 4],
                      levels: [(1, 3600, []), (1, hours(10), []), (1, hours(20), []), (1, hours(40), [])]),
            Rest.item(lab, "buildings", .economy, .builder, counts: [0, 1, 1, 1], max: [0, 1, 1, 1], levels: [(0, 0, [])]),
            Rest.item(troop, "units", .laboratory, .laboratory, counts: [0, 0, 0, 0], max: [0, 3, 3, 3], resource: .elixir,
                      levels: [(nil, 0, []), (1, hours(20), []), (1, hours(40), [])]),
            // Des murs qui dureraient une heure par niveau : la règle P6 les écarte quand même.
            Rest.item(wall, "buildings", .walls, .builder, counts: [0, 1, 1, 1], max: [0, 3, 3, 3],
                      levels: [(1, 3600, []), (1, 3600, []), (1, 3600, [])]),
            ReferenceItem(id: apprentice, names: ["en": "apprentice"], section: "helpers", category: nil, exclusion: .helper,
                          worker: .builder,
                          levels: [ReferenceLevel(level: 1, costs: [], duration: 0, requires: [], helperMultiplier: 1, helperSeconds: 3600)],
                          countByTownHall: [0, 1, 1, 1], maxLevelByTownHall: [0, 1, 1, 1], mergedFrom: []),
        ], maxTownHall: 3)
    }
    static let ref = reference()

    /// Une photo à `date` : un canon (niveau, minuteur en secondes), le labo, une troupe de labo (niveau, minuteur).
    static func photo(_ date: Date, cannon niveau: Int, timer: Int? = nil, huts: Int = 1, troop troupe: (Int, Int?)? = nil,
                      labo: Bool = false, boosts: [String: Int] = [:], helpers: [ExportEntry] = [],
                      cannonExtras: [String: JSONValue] = [:], murs: Int? = nil) -> VillageExport {
        var buildings = [Mini.e(th, 3), Mini.e(hut, 1, huts), ExportEntry(id: cannon, level: niveau, timer: timer, extras: cannonExtras)]
        if labo { buildings.append(Mini.e(lab, 1)) }
        if let murs { buildings.append(Mini.e(wall, murs)) }
        var sections = ["buildings": buildings, "helpers": helpers]
        if let troupe { sections["units"] = [Mini.e(troop, troupe.0, timer: troupe.1)] }
        return VillageExport(tag: "#2PP", date: date, sections: sections, idLists: [:], boosts: boosts, warnings: [])
    }

    static let libre = Profile(quietHours: nil)

    static func occupation(_ a: VillageExport, _ b: VillageExport, huts: Int = 1, profile: Profile = libre) -> Occupation {
        Occupation(between: a, and: b, reference: reference(huts: huts), profile: profile)!
    }

    static func builders(_ a: VillageExport, _ b: VillageExport, huts: Int = 1, profile: Profile = libre) -> PostOccupation {
        occupation(a, b, huts: huts, profile: profile).post(.builder)!
    }
}

@Suite struct OccupationTests {
    typealias O = Occ

    // MARK: - O1 : minuteurs de la première photo, débuts déduits de la seconde

    @Test func O1_posteJamaisLibre_cent_pour_cent() {
        // Le même minuteur court d'une photo à l'autre : le poste a travaillé toute la fenêtre.
        let a = O.photo(O.h(0), cannon: 2, timer: O.hours(20))
        let b = O.photo(O.h(10), cannon: 2, timer: O.hours(10))
        let post = O.builders(a, b)
        #expect(post.available == O.hours(10))
        #expect(post.busy == O.hours(10)...O.hours(10))
        #expect(post.free == 0...0)
        #expect(post.midRate == 1)
        #expect(!post.isApproximate)
        #expect(post.invisibleLevels == 0)
    }

    @Test func O1_posteLibreDeuxJours() {
        // A : le canon finit son niveau 3 à h24. B (h96) : niveau 4 en cours, fin à h112, durée complète 40 h, donc
        // lancé à h72. Libre de h24 à h72 : deux jours. Occupé 24 h + 24 h sur 96 h.
        let a = O.photo(O.h(0), cannon: 2, timer: O.hours(24))
        let b = O.photo(O.h(96), cannon: 3, timer: O.hours(16))
        let post = O.builders(a, b)
        #expect(post.available == O.hours(96))
        #expect(post.busy == O.hours(48)...O.hours(48))
        #expect(post.free == O.hours(48)...O.hours(48))
        #expect(post.midRate == 0.5)
        #expect(!post.isApproximate)
    }

    @Test func O1_laFinDeLaPremierePhotoSansRelanceDonneLeTempsLibre() {
        // A : fin à h5. B (h20) : rien en cours. Occupé 5 h sur 20 h.
        let post = O.builders(O.photo(O.h(0), cannon: 2, timer: O.hours(5)), O.photo(O.h(20), cannon: 3))
        #expect(post.busy == O.hours(5)...O.hours(5))
        #expect(post.free == O.hours(15)...O.hours(15))
        #expect(post.invisibleLevels == 0)       // le niveau gagné est celui du minuteur de A : rien d'invisible
    }

    @Test func O1_chaquePosteALeSien() {
        // Le canon travaille sans arrêt ; le labo a une troupe qui ne bouge pas : 100 % pour les ouvriers, 0 % pour le labo.
        let a = O.photo(O.h(0), cannon: 2, timer: O.hours(20), troop: (1, nil), labo: true)
        let b = O.photo(O.h(10), cannon: 2, timer: O.hours(10), troop: (1, nil), labo: true)
        let o = O.occupation(a, b)
        #expect(o.posts.map(\.worker) == [.builder, .laboratory])
        #expect(o.post(.builder)?.midRate == 1)
        #expect(o.post(.laboratory)?.midRate == 0)
        #expect(o.post(.laboratory)?.free == O.hours(10)...O.hours(10))
    }

    @Test func O1_autantDeTempsDisponibleQueDOuvriers() {
        // Deux cabanes : 2 × 10 h disponibles, un seul minuteur : 50 %.
        let a = O.photo(O.h(0), cannon: 2, timer: O.hours(20), huts: 2)
        let b = O.photo(O.h(10), cannon: 2, timer: O.hours(10), huts: 2)
        let post = O.builders(a, b, huts: 2)
        #expect(post.workers == 2)
        #expect(post.available == O.hours(20))
        #expect(post.midRate == 0.5)
    }

    // MARK: - O3 : améliorations lancées puis terminées entre deux photos

    @Test func O3_ameliorationInvisible_compteSaDureeDeLaReference() {
        // Le niveau 3 (20 h) a été lancé et fini entre les deux photos : aucun minuteur nulle part.
        let post = O.builders(O.photo(O.h(0), cannon: 2), O.photo(O.h(48), cannon: 3))
        #expect(post.invisibleLevels == 1)
        #expect(post.busy == O.hours(20)...O.hours(20))
        #expect(post.midRate == Double(O.hours(20)) / Double(O.hours(48)))
        // Deux niveaux d'un coup (20 h + 40 h) dans 72 h.
        let deux = O.builders(O.photo(O.h(0), cannon: 2), O.photo(O.h(72), cannon: 4))
        #expect(deux.invisibleLevels == 2)
        #expect(deux.busy == O.hours(60)...O.hours(60))
    }

    @Test func O3_unNiveauInvisiblePuisUnMinuteurVisible() {
        // A : niveau 2, rien en cours. B (h72) : niveau 3 fini, niveau 4 lancé à h50 (fin h90, 40 h). Le niveau 3 (20 h)
        // est invisible ; le niveau 4 est vu par son début déduit (22 h dans la fenêtre).
        let post = O.builders(O.photo(O.h(0), cannon: 2), O.photo(O.h(72), cannon: 3, timer: O.hours(18)))
        #expect(post.invisibleLevels == 1)
        #expect(post.busy == O.hours(42)...O.hours(42))
    }

    @Test func O3_lesMursEtLesPostesSansDureeNeComptentPas_P6() {
        let a = O.photo(O.h(0), cannon: 2, murs: 1), b = O.photo(O.h(48), cannon: 3, murs: 3)
        #expect(O.builders(a, b).busy == O.hours(20)...O.hours(20))       // les deux niveaux de murs : rien
    }

    // MARK: - O2 : une réduction rend la durée incertaine

    @Test func O2_reductionDuProfil_donneUnIntervalle() {
        let profil = Profile(builderReduction: Reduction(percent: 20, endsAt: O.h(1000)), quietHours: nil)
        let post = O.builders(O.photo(O.h(0), cannon: 2), O.photo(O.h(48), cannon: 3), profile: profil)
        #expect(post.busy == O.hours(16)...O.hours(20))                    // 20 h, moins 20 %
        #expect(post.isApproximate)
        #expect(post.rate.lowerBound < post.rate.upperBound)
        #expect(post.midRate == Double(O.hours(18)) / Double(O.hours(48)))
    }

    @Test func O2_reductionDuProfilTermineeAvantLeDebut_nePlusJoue() {
        let profil = Profile(builderReduction: Reduction(percent: 20, endsAt: O.h(-5)), quietHours: nil)
        let post = O.builders(O.photo(O.h(0), cannon: 2), O.photo(O.h(48), cannon: 3), profile: profil)
        #expect(!post.isApproximate)
    }

    @Test func O2_reductionDuProfilElargitAussiLeDebutDeduit() {
        // B : niveau 4 (40 h) fini à h60. Début entre h20 (durée complète) et h32 (réduit de 30 %), dans la fenêtre h0-h50.
        let profil = Profile(builderReduction: Reduction(percent: 30, endsAt: O.h(1000)), quietHours: nil)
        let post = O.builders(O.photo(O.h(0), cannon: 3), O.photo(O.h(50), cannon: 3, timer: O.hours(10)), profile: profil)
        #expect(post.busy == O.hours(18)...O.hours(30))
    }

    @Test func O2_potionActive_elargitLIntervalle() {
        let a = O.photo(O.h(0), cannon: 2), b = O.photo(O.h(48), cannon: 3, boosts: ["builder_boost": 1800])
        let post = O.builders(a, b)
        #expect(post.busy == O.hours(11)...O.hours(20))                    // jusqu'à neuf heures gagnées
        #expect(post.isApproximate)
        // Une potion du labo ne touche pas les ouvriers.
        #expect(!O.builders(a, O.photo(O.h(48), cannon: 3, boosts: ["lab_boost": 1800])).isApproximate)
    }

    @Test func O2_assistantDuPoste_elargitLIntervalleDeLUpgradeAide() {
        // B : le niveau 4 (40 h) est aidé (helper_recurrent) : deux services d'une heure au plus (40 h / 23 h + 1).
        let apprenti = [Mini.e(O.apprentice, 1)]
        let aide: [String: JSONValue] = ["helper_recurrent": .bool(true)]
        let a = O.photo(O.h(0), cannon: 3, helpers: apprenti)
        let b = O.photo(O.h(50), cannon: 3, timer: O.hours(10), helpers: apprenti, cannonExtras: aide)
        let post = O.builders(a, b)
        #expect(post.busy == O.hours(28)...O.hours(30))
        #expect(post.isApproximate)
        // Sans l'affectation dans la photo, l'assistant n'élargit rien.
        let sans = O.builders(a, O.photo(O.h(50), cannon: 3, timer: O.hours(10), helpers: apprenti))
        #expect(sans.busy == O.hours(30)...O.hours(30))
    }

    // MARK: - O4 : heures sans jeu

    /// 2 novembre 2026, 7 h à Paris (UTC+1).
    private static let septHeures: Date = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 7))!
    }()
    private func plus(_ heures: Int) -> Date { Self.septHeures.addingTimeInterval(TimeInterval(heures * 3600)) }

    @Test func O4_leTempsLibreDeLaNuitDeclareeNeComptePas() {
        // Le canon finit à 23 h (h16), puis le poste attend 7 h (h24) : huit heures, pendant la nuit déclarée.
        let a = O.photo(plus(0), cannon: 2, timer: O.hours(16)), b = O.photo(plus(24), cannon: 3)
        let nuit = O.builders(a, b, profile: Profile(quietHours: .default))
        #expect(nuit.available == O.hours(16))
        #expect(nuit.midRate == 1)
        // Sans heures sans jeu, ces huit heures sont du temps libre.
        let jour = O.builders(a, b)
        #expect(jour.available == O.hours(24))
        #expect(jour.busy == O.hours(16)...O.hours(16))
        #expect(abs(jour.midRate - 2.0 / 3) < 1e-9)
    }

    @Test func O4_leTempsLibreDeJourCompteMemeAvecDesHeuresSansJeu() {
        // Le canon finit à 11 h (h4) : quatre heures de travail, douze heures libres de jour (11 h à 23 h), puis la nuit.
        let a = O.photo(plus(0), cannon: 2, timer: O.hours(4)), b = O.photo(plus(24), cannon: 3)
        let post = O.builders(a, b, profile: Profile(quietHours: .default))
        #expect(post.available == O.hours(16))
        #expect(post.busy == O.hours(4)...O.hours(4))
        #expect(post.free == O.hours(12)...O.hours(12))
    }

    @Test func O4_uneFenetreFaiteDeNuitSeule_nAPasDeMesure() {
        let a = O.photo(plus(17), cannon: 2), b = O.photo(plus(22), cannon: 2)     // 0 h à 5 h
        #expect(Occupation(between: a, and: b, reference: O.ref, profile: Profile(quietHours: .default)) == nil)
    }

    // MARK: - O5 : photos dans le désordre, cas dégénérés

    @Test func O5_photosALEnvers_memeResultatQueDansLOrdre() {
        let a = O.photo(O.h(0), cannon: 2, timer: O.hours(24)), b = O.photo(O.h(96), cannon: 3, timer: O.hours(16))
        let droit = O.occupation(a, b), envers = O.occupation(b, a)
        #expect(droit == envers)
        #expect(envers.from == O.h(0) && envers.to == O.h(96))
    }

    @Test func O5_memeDateOuHdvInconnu_pasDeMesure() {
        let a = O.photo(O.h(0), cannon: 2)
        #expect(Occupation(between: a, and: a, reference: O.ref, profile: O.libre) == nil)
        let hdv99 = VillageExport(tag: "#2PP", date: O.h(10), sections: ["buildings": [Mini.e(O.th, 99)]], idLists: [:],
                                  boosts: [:], warnings: [])
        #expect(Occupation(between: a, and: hdv99, reference: O.ref, profile: O.libre) == nil)
    }

    // MARK: - O6 : le rythme des 30 derniers jours

    /// Une photo en JSON, comme l'app l'enregistre (HistoryStore lit des textes).
    private func texte(_ jour: Double, cannon niveau: Int, timer: Int? = nil) -> String {
        let t = Int(O.t0.timeIntervalSince1970 + jour * 86_400)
        let minuteur = timer.map { ",\"timer\":\($0)" } ?? ""
        return ##"{"tag":"#2PP","timestamp":\##(t),"buildings":[{"data":1000001,"lvl":3},{"data":1000015,"lvl":1},{"data":1000008,"lvl":\##(niveau)\##(minuteur)}]}"##
    }

    private func rythme(_ photos: [String]) throws -> Rhythm? {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = HistoryStore(root: dossier.url)
        for p in photos { try store.photos.save(p) }
        return store.rhythm(context: HistoryContext(reference: O.ref, profile: O.libre))
    }

    @Test func O6_unePhotoSeule_pasDeRythme() throws {
        #expect(try rythme([texte(0, cannon: 2)]) == nil)
    }

    @Test func O6_deuxPhotosSurTroisJours_pasDeRythme() throws {
        #expect(try rythme([texte(0, cannon: 2, timer: 86_400), texte(3, cannon: 3)]) == nil)
    }

    @Test func O6_troisPhotosSurSixJours_pasDeRythme() throws {
        #expect(try rythme([texte(0, cannon: 2), texte(3, cannon: 3), texte(6, cannon: 4)]) == nil)
    }

    @Test func O6_troisPhotosSurHuitJours_unRythmeMoyenne() throws {
        // Fenêtre 1 : 96 h, 48 h de travail (O1, poste libre deux jours). Fenêtre 2 : 96 h, 16 h (fin du niveau 4 à h112).
        let r = try #require(try rythme([texte(0, cannon: 2, timer: 24 * 3600), texte(4, cannon: 3, timer: 16 * 3600), texte(8, cannon: 4)]))
        #expect(r.photos == 3)
        #expect(r.to.timeIntervalSince(r.from) == 8 * 86_400)
        #expect(abs(r.rate(for: .builder) - 64.0 / 192) < 1e-9)
        #expect(r.rate(for: .laboratory) == 1)                           // pas de labo : rien de mesuré, pas d'attente
        #expect(r.rates[.builder]?.isApproximate == false)
    }

    @Test func O6_seulesLesPhotosDesTrenteDerniersJoursCompten() throws {
        // Photos aux jours 0, 40, 48 : seules deux tombent dans les 30 jours avant la dernière.
        #expect(try rythme([texte(0, cannon: 2), texte(40, cannon: 3), texte(48, cannon: 4)]) == nil)
        // Aux jours 0, 40, 45, 50 : trois photos sur dix jours.
        let r = try #require(try rythme([texte(0, cannon: 2), texte(40, cannon: 2), texte(45, cannon: 3), texte(50, cannon: 3)]))
        #expect(r.photos == 3)
        #expect(r.from == O.t0.addingTimeInterval(40 * 86_400))
    }

    @Test func O6_laPhotoIllisibleEstSautee() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = HistoryStore(root: dossier.url)
        for (jour, n) in [(0.0, 2), (4, 3), (8, 4)] { try store.photos.save(texte(jour, cannon: n)) }
        try FileManager.default.createDirectory(at: store.photos.directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: store.photos.directory.appending(path: Snapshot(date: O.t0.addingTimeInterval(2 * 86_400)).fileName))
        let contexte = HistoryContext(reference: O.ref, profile: O.libre)
        #expect(store.occupations(context: contexte).count == 2)
        #expect(store.rhythm(context: contexte)?.photos == 3)
    }

    // MARK: - O7 : le rythme dans la simulation

    private func plan(_ rythme: Rhythm?, huts: Int = 1, profile: Profile = O.libre, timer: Int? = nil, niveau: Int = 2) -> Plan {
        let r = O.reference(huts: huts)
        let export = O.photo(O.t0, cannon: niveau, timer: timer, huts: huts)
        return makePlan(for: Village(export: export, reference: r), reference: r, advice: AdviceData(), profile: profile,
                        now: O.t0, rhythm: rythme)
    }
    private func spans(_ p: Plan) -> [String] { p.steps.filter { $0.step.itemID == Occ.cannon }.map { "\($0.step.level) \(Int($0.start.timeIntervalSince(O.t0)) / 3600)→\(Int($0.end.timeIntervalSince(O.t0)) / 3600)" } }

    @Test func O7_sansRythme_lePlanEstCeluiDeToujours() {
        let sans = plan(nil)
        #expect(spans(sans) == ["3 0→20", "4 20→60"])
        #expect(sans.cap == O.h(60))
        #expect(plan(Rhythm(rate: 1)) == sans)                           // un rythme de 100 % ne change rien
        #expect(plan(Rhythm(from: .distantPast, to: .distantPast, photos: 0, rates: [:])) == sans)
    }

    @Test func O7_unPosteOccupeALaMoitie_attendLaDureeDeLaDerniereAmelioration() {
        // Niveau 3 : h0 → h20. Il attend 20 h × (1 − 0,5) / 0,5 = 20 h : le niveau 4 part à h40 et finit à h80.
        let p = plan(Rhythm(rate: 0.5))
        #expect(spans(p) == ["3 0→20", "4 40→80"])
        #expect(p.cap == O.h(80))                                         // la dernière attente ne retarde rien
    }

    @Test func O7_leMinuteurDeLaPhotoDonneAussiUneAttente_maisSeulementCeQuiResteApresNow() {
        // Minuteur du niveau 3 : 10 h restantes. Attente : 10 h × 1 = 10 h ; le niveau 4 part à h20.
        let p = plan(Rhythm(rate: 0.5), timer: O.hours(10))
        #expect(spans(p) == ["3 0→10", "4 20→60"])
        // Photo vieille de 100 h : le minuteur est fini depuis longtemps, le poste est libre maintenant, sans attente.
        let r = O.reference(), vieux = O.photo(O.t0, cannon: 2, timer: O.hours(10))
        let tard = makePlan(for: Village(export: vieux, reference: r), reference: r, advice: AdviceData(), profile: O.libre,
                            now: O.h(100), rhythm: Rhythm(rate: 0.5))
        #expect(spans(tard) == ["3 0→10", "4 100→140"])
    }

    @Test func O7_lePlancherDuTaux_pasDAttenteSansFin() {
        // Un poste jamais occupé (0 %) attend 19 fois la durée, pas l'infini.
        #expect(spans(plan(Rhythm(rate: 0))) == ["3 0→20", "4 400→440"])
    }

    @Test func O7_lAttenteFinitHorsDesHeuresSansJeu_S4() {
        // Départ à 7 h Paris ; niveau 3 : 7 h → 3 h le lendemain ; attente 20 h à 50 % : 23 h tombe dans la nuit, le niveau 4
        // part à 7 h.
        let r = O.reference()
        let debut = Self.septHeures
        let export = O.photo(debut, cannon: 2)
        let p = makePlan(for: Village(export: export, reference: r), reference: r, advice: AdviceData(),
                         profile: Profile(quietHours: .default), now: debut, rhythm: Rhythm(rate: 0.5))
        let departs = p.steps.filter { $0.step.itemID == Occ.cannon }.map { Int($0.start.timeIntervalSince(debut)) / 3600 }
        #expect(departs == [0, 48])    // 20 h + 20 h = 40 h après le début : 23 h le surlendemain, dans la nuit → 7 h
    }

    @Test func O7_deuxOuvriersLeCouloirLibreLePlusTotRelance() {
        // Deux canons au niveau 2 (une photo, deux cabanes) : chacun son couloir, chacun son attente.
        let r = ReferenceData(items: O.reference(huts: 2).items.map { $0.id == Occ.cannon
            ? Rest.item(Occ.cannon, "buildings", .defenses, .builder, counts: [0, 2, 2, 2], max: [0, 4, 4, 4],
                        levels: [(1, 3600, []), (1, O.hours(10), []), (1, O.hours(20), []), (1, O.hours(40), [])]) : $0 },
                              maxTownHall: 3)
        let export = VillageExport(tag: "#2PP", date: O.t0, sections: ["buildings": [Mini.e(Occ.th, 3), Mini.e(Occ.hut, 1, 2), Mini.e(Occ.cannon, 2, 2)]],
                                   idLists: [:], boosts: [:], warnings: [])
        let p = makePlan(for: Village(export: export, reference: r), reference: r, advice: AdviceData(), profile: O.libre,
                         now: O.t0, rhythm: Rhythm(rate: 0.5))
        // Niveau 3 des deux exemplaires à h0 → h20, puis niveau 4 des deux à h40 → h80, chacun dans son couloir.
        let canons = p.steps.filter { $0.step.itemID == Occ.cannon }
        #expect(canons.map { "\($0.step.level) \(Int($0.start.timeIntervalSince(O.t0)) / 3600)" } == ["3 0", "3 0", "4 40", "4 40"])
        #expect(Set(canons.suffix(2).map(\.lane)).count == 2)
        #expect(p.cap == O.h(80))
    }

    @Test func O7_cap_reelHdv16_sansRythme_resteCeluiDeLaVersionPrecedente() {
        // Valeurs relevées sur `main` (f4480bb) avant T24, avec les conseils vides puis avec les vrais conseils et les assistants.
        let sans = makePlan(for: Réel.village, reference: Réel.reference, advice: AdviceData(), profile: Profile(), now: Réel.export.date)
        #expect(sans.cap == Date(timeIntervalSince1970: 1_859_194_800))
        #expect(sans.steps.count == 354)
        let complet = makePlan(for: Réel.village, reference: Réel.reference, advice: (try! AdviceData.load()), profile: Profile(),
                               now: Réel.export.date, boosts: Réel.export.boosts,
                               assistants: Assistants(export: Réel.export, reference: Réel.reference))
        #expect(complet.cap == Date(timeIntervalSince1970: 1_857_448_800))
        // Avec un rythme de 100 % ou sans mesure, rien ne bouge ; à 80 %, le cap recule.
        #expect(makePlan(for: Réel.village, reference: Réel.reference, advice: AdviceData(), profile: Profile(),
                         now: Réel.export.date, rhythm: Rhythm(rate: 1)) == sans)
        let lent = makePlan(for: Réel.village, reference: Réel.reference, advice: AdviceData(), profile: Profile(),
                            now: Réel.export.date, rhythm: Rhythm(rate: 0.8))
        #expect(lent.cap! > sans.cap!)
    }
}
