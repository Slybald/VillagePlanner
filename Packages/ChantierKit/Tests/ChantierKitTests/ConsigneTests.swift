import Foundation
import Testing
@testable import ChantierKit

// La consigne du moteur (T16) : les cinq cas de la tâche et les dates en français, listés en tête de Consigne.swift.
// Villages inventés à l'HDV 3 (aides `Prio`, `Sim`). La photo est `Rest.date` : lundi 12 janvier 1970, 13 h 46 min 40 s
// en UTC (l'heure s'écrit donc « 13 h 47 », arrondie à la minute supérieure). Un niveau coûte 100 d'or.

enum Cons {
    typealias P = Prio
    typealias S = Sim
    static let utc = TimeZone(identifier: "UTC")!
    static let h = 3600, jour = 86_400
    static let noms = ["1000008": "Canon", "28000000": "Roi", "4000000": "Troupe", "1000007": "Labo"]

    static let canon = P.item(P.cannon, .defenses, [S.lv(10), S.lv(h), S.lv(h)])
    static let roi = P.item(P.king, .heroes, section: "heroes", [S.lv(10), S.lv(h), S.lv(h)])
    static let troupe = P.item(P.troopA, .laboratory, section: "units", worker: .laboratory,
                               [P.lv(nil, 0), P.lv(300, h), P.lv(300, h)])
    static let labo = P.item(P.lab, .economy, [S.lv(10)])

    /// Le plan et la consigne `after` secondes après la photo (`now`), photo à `Rest.date` sauf `photo`.
    static func texte(_ items: [ReferenceItem], _ sections: [String: [ExportEntry]], huts: Int = 1,
                         now: Int = 0, photo: Date = Rest.date) -> String {
        let (v, r0) = S.village(items, sections, huts: huts)
        let r = r0.withFrenchNames(noms)
        let date = Rest.date.addingTimeInterval(TimeInterval(now))
        let plan = makePlan(for: v, reference: r, advice: AdviceData(), profile: S.free, now: date)
        // Espaces insécables et fines : les phrases se comparent avec des espaces ordinaires.
        return ChantierKit.consigne(of: plan, photo: photo, reference: r, timeZone: utc)
            .replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    static func lisible(_ f: (Date, Date, TimeZone) -> String, _ d: Int, now: Int = 0) -> String {
        f(Rest.date.addingTimeInterval(TimeInterval(d)), Rest.date.addingTimeInterval(TimeInterval(now)), utc)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}

@Suite struct ConsigneTests {
    typealias C = Cons
    typealias P = Prio
    typealias S = Sim

    // MARK: - Les cinq cas

    @Test func C3_unPosteDejaLibre_dit_quoiLancerEtCombienReunir() {
        // Le minuteur du canon (1 h) a fini il y a une heure : l'ouvrier est libre maintenant.
        let texte = C.texte([C.canon], ["buildings": [P.e(P.cannon, 1, timer: C.h)]], now: 2 * C.h)
        #expect(texte == "Un ouvrier est libre : lance Canon 3. Il te faut 100 d'or.")
    }

    @Test func C3_plusieursPostesLibresEnMemeTemps_uneSeulePhrase() {
        // Roi et canon finis tous les deux, deux ouvriers : ils sont libres ensemble ; le roi (héros) passe avant.
        let texte = C.texte([C.canon, C.roi], ["buildings": [P.e(P.cannon, 1, timer: C.h)],
                                                  "heroes": [P.e(P.king, 1, timer: C.h)]], huts: 2, now: 2 * C.h)
        #expect(texte == "Deux ouvriers sont libres : lance Roi 3 et Canon 3. Il te faut 200 d'or.")
    }

    @Test func C4_ouvrierEtLaboSeLiberentEnMemeTemps_sontNommesTousLesDeux() {
        // Canon et troupe finissent à 2 h : à 15 h 47, un ouvrier et le labo se libèrent ; 100 + 300 d'or à réunir.
        let texte = C.texte([C.canon, C.troupe, C.labo],
                               ["buildings": [P.e(P.cannon, 1, timer: 2 * C.h), P.e(P.lab, 1)], "units": [P.e(P.troopA, 1, timer: 2 * C.h)]])
        #expect(texte == "Aujourd'hui 15 h 47, un ouvrier et le labo se libèrent : lance Canon 3 et Troupe 3. Prépare 400 d'or.")
    }

    @Test func C4_leProchainLancementDemain_estEcritDemainAvecSonHeure() {
        // Minuteur de 20 h : l'ouvrier se libère demain à 9 h 46 min 40 s, soit 9 h 47.
        let texte = C.texte([C.canon], ["buildings": [P.e(P.cannon, 1, timer: 20 * C.h)]])
        #expect(texte == "Demain 9 h 47, un ouvrier se libère : lance Canon 3. Prépare 100 d'or.")
    }

    @Test func C5_rienAvant24h_dit_quandEtCeQuiPartira() {
        // Minuteur de trois jours : rien ne part avant jeudi 15 janvier.
        let texte = C.texte([C.canon], ["buildings": [P.e(P.cannon, 1, timer: 3 * C.jour)]])
        #expect(texte == "Rien à lancer avant jeudi 13 h 47. Ce jour-là, un ouvrier se libère : lance Canon 3. Prépare 100 d'or.")
    }

    @Test func C5_pileVingtQuatreHeures_resteUneConsigneNormale() {
        // 24 h pile ne dépasse pas l'horizon : « demain », pas « rien avant ».
        let texte = C.texte([C.canon], ["buildings": [P.e(P.cannon, 1, timer: 24 * C.h)]])
        #expect(texte.hasPrefix("Demain 13 h 47, un ouvrier se libère"))
    }

    @Test func C2_toutEstTermine_ditQuePlusRienNeReste() {
        // Le dernier niveau du canon (en cours) a fini avant `now` : plus de cap, plus rien à lancer.
        let texte = C.texte([P.item(P.cannon, .defenses, [S.lv(10), S.lv(C.h)])],
                               ["buildings": [P.e(P.cannon, 1, timer: C.h)]], now: 2 * C.h)
        #expect(texte == "Tout est terminé à ton HDV : plus rien à améliorer, hors murs et équipements.")
    }

    @Test func C2_ilNeResteQueDesMinuteursEnCours_ladernierefinitQuand() {
        // Canon au dernier niveau : rien à lancer, le minuteur de 5 h court encore.
        let texte = C.texte([P.item(P.cannon, .defenses, [S.lv(10), S.lv(5 * C.h)])],
                               ["buildings": [P.e(P.cannon, 1, timer: 5 * C.h)]])
        #expect(texte == "Rien d'autre à lancer : il ne reste que les améliorations en cours. La dernière finit aujourd'hui 18 h 47.")
    }

    @Test func C2_ilNeResteQueDesAmeliorationsBloquees_ledit() {
        // Le niveau 2 du canon exige un labo 5 qui n'existe pas : bloqué (S7), rien ne part.
        let canon = P.item(P.cannon, .defenses, [S.lv(10), S.lv(C.h, [Requirement(itemID: P.lab, level: 5)])])
        let texte = C.texte([canon, C.labo], ["buildings": [P.e(P.cannon, 1), P.e(P.lab, 1)]])
        #expect(texte == "Plus rien ne peut partir : 1 amélioration est bloquée.")
    }

    @Test func C1_photoDePlusDeSeptJours_demandeUnNouvelExport() {
        let texte = C.texte([C.canon], ["buildings": [P.e(P.cannon, 1, timer: C.h)]], now: 8 * C.jour)
        #expect(texte == "Ta photo date de 8 jours : les minuteurs ont fini depuis et le plan ne vaut plus. Copie un nouvel export depuis le jeu.")
    }

    @Test func C1_septJoursPile_laPhotoCompteEncore() {
        // 7 jours exactement : pas plus de sept ; une seconde de plus, si.
        let sections = ["buildings": [P.e(P.cannon, 1, timer: C.h)]]
        #expect(C.texte([C.canon], sections, now: 7 * C.jour).hasPrefix("Un ouvrier est libre"))
        #expect(C.texte([C.canon], sections, now: 7 * C.jour + 1).hasPrefix("Ta photo date de 7 jours"))
    }

    // MARK: - Dates en français

    @Test func dates_aujourdhuiDemainUnJourDeLaSemaineEtLeJourLeMois() {
        // Lundi 12 janvier 1970, 13 h 46 min 40 s.
        #expect(C.lisible(Lisible.moment, 3 * C.h) == "aujourd'hui 16 h 47")
        #expect(C.lisible(Lisible.moment, 0) == "aujourd'hui 13 h 47")
        #expect(C.lisible(Lisible.moment, 20 * C.h + 14 * 60) == "demain 10 h 01")      // 10 h 00 min 40 s, arrondi à 10 h 01
        #expect(C.lisible(Lisible.moment, 4 * C.jour) == "vendredi 13 h 47")
        #expect(C.lisible(Lisible.moment, 6 * C.jour) == "dimanche 13 h 47")
        #expect(C.lisible(Lisible.moment, 7 * C.jour) == "le 19 janvier à 13 h 47")      // pas « lundi » : ce serait aujourd'hui
        #expect(C.lisible(Lisible.moment, 20 * C.jour) == "le 1er février à 13 h 47")
        #expect(C.lisible(Lisible.moment, 365 * C.jour) == "le 12 janvier 1971 à 13 h 47")
    }

    @Test func dates_aucunArrondiPileALHeure_etMinuitSEcritZeroHeure() {
        // 13 h 46 min 40 s + 10 h 13 min 20 s = 0 h 00 le lendemain.
        #expect(C.lisible(Lisible.moment, 10 * 3600 + 13 * 60 + 20) == "demain 0 h")
        // 13 h 46 min 40 s + 13 min 20 s = 14 h pile : pas d'arrondi.
        #expect(C.lisible(Lisible.moment, 13 * 60 + 20) == "aujourd'hui 14 h")
    }

    @Test func dates_libreDepuis() {
        let now = 8 * C.h                                                      // 21 h 46 min 40 s
        #expect(C.lisible(Lisible.depuis, 5 * C.h, now: now) == "18 h 47")
        #expect(C.lisible(Lisible.depuis, -14 * C.h, now: now) == "hier 23 h 47")
        #expect(C.lisible(Lisible.depuis, -3 * C.jour, now: 0) == "vendredi 13 h 47")      // 9 janvier 1970
        #expect(C.lisible(Lisible.depuis, -9 * C.jour, now: 0) == "le 3 janvier")
    }
}
