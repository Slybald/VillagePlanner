import Foundation
import Testing
@testable import ChantierKit

// T26 : les échéances sont une fonction pure. Une notification par fin de minuteur de la photo, regroupées à moins de
// cinq minutes, reportées hors des heures sans jeu, au plus vingt ; rien d'inventé pour un minuteur illisible.

private typealias P = Prio
private typealias S = Sim
private let nom: @Sendable (Int) -> String = { P.names[$0] ?? "#\($0)" }

@Suite struct EcheancesTests {
    private let items = [P.item(P.cannon, .defenses, [S.lv(10), S.lv(300), S.lv(100)])]
    private var base: Plan { S.plan(items, ["buildings": [P.e(P.cannon, 1, timer: 3600)]]) }

    /// Le plan de base, avec un minuteur de la photo par fin donnée (secondes après la photo), un par couloir.
    private func plan(fins: [Int], origine: Date = Rest.date) -> Plan {
        let modele = base.steps[0]
        let pas = fins.enumerated().map { i, fin in
            ScheduledStep(step: modele.step, copy: 0, lane: i, start: origine, end: origine.addingTimeInterval(TimeInterval(fin)),
                          costs: [], reductionPercent: 0, fromSnapshot: true, reason: nil)
        }
        return Plan(now: origine, steps: pas)
    }

    @Test func aucuneFinAVenir_aucuneNotification() {
        #expect(Echeances.liste(plan: S.plan([], [:]), nom: nom, quietHours: nil, now: Rest.date).isEmpty)
        // Le minuteur est fini depuis la photo : rien à annoncer.
        #expect(Echeances.liste(plan: base, nom: nom, quietHours: nil, now: S.at(7200)).isEmpty)
    }

    @Test func uneNotificationParFin_avecLePosteEtLAmeliorationConseilleeEnsuite() {
        let e = Echeances.liste(plan: base, nom: nom, quietHours: nil, now: Rest.date)
        #expect(e == [Echeance(date: S.at(3600), titre: "Ouvrier 1 libre",
                               corps: "cannon niveau 2 terminé. Ensuite : cannon niveau 3.")])
    }

    @Test func sansSuite_laNotificationNeDitQueLaFin() {
        let seul = S.plan([P.item(P.cannon, .defenses, [S.lv(10), S.lv(300)])], ["buildings": [P.e(P.cannon, 1, timer: 3600)]])
        #expect(Echeances.liste(plan: seul, nom: nom, quietHours: nil, now: Rest.date).map(\.corps) == ["cannon niveau 2 terminé."])
    }

    @Test func deuxFinsAMoinsDeCinqMinutes_sontRegroupees_aLaDerniere() {
        let e = Echeances.liste(plan: plan(fins: [3600, 3600 + 299]), nom: nom, quietHours: nil, now: Rest.date)
        #expect(e.count == 1)
        #expect(e[0].titre == "2 postes libres" && e[0].date == S.at(3600 + 299))
        #expect(e[0].corps.split(separator: "\n").count == 2)
    }

    @Test func deuxFinsACinqMinutes_restentSeparees() {
        let e = Echeances.liste(plan: plan(fins: [3600, 3600 + 300]), nom: nom, quietHours: nil, now: Rest.date)
        #expect(e.map(\.date) == [S.at(3600), S.at(3900)])
    }

    @Test func plafondDeVingt_lesPlusProchesGardees() {
        let fins = (1...30).map { $0 * 600 }
        let e = Echeances.liste(plan: plan(fins: fins), nom: nom, quietHours: nil, now: Rest.date)
        #expect(e.count == Echeances.plafond)
        #expect(e.map(\.date) == (1...20).map { S.at($0 * 600) })
    }

    @Test func minuteurIllisible_pasDeNotificationInventee() {
        let illisible = S.plan(items, ["buildings": [ExportEntry(id: P.cannon, level: 1, extras: ["timer": .string("?")])]])
        #expect(illisible.unknownTimers == 1)
        #expect(Echeances.liste(plan: illisible, nom: nom, quietHours: nil, now: Rest.date).isEmpty)
    }

    @Test func heuresSansJeu_laNotificationEstReporteeALaFinDeLaPlage() {
        // La photo est à 13 h 46 UTC : le minuteur finit à 14 h 46, dans la plage 14 h → 16 h.
        let nuit = QuietHours(start: 14, end: 16, timeZone: S.utc)
        let e = Echeances.liste(plan: base, nom: nom, quietHours: nuit, now: Rest.date)
        let seize = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: S.utc, year: 1970, month: 1, day: 12, hour: 16))!
        #expect(e.map(\.date) == [seize])
    }

    @Test func heuresSansJeu_deuxFinsReporteesAuMemeInstantSontRegroupees() {
        let nuit = QuietHours(start: 14, end: 16, timeZone: S.utc)
        let e = Echeances.liste(plan: plan(fins: [3600, 4800]), nom: nom, quietHours: nuit, now: Rest.date)
        #expect(e.count == 1 && e[0].titre == "2 postes libres")
    }

    @Test func changementDHeure_laPlageSeLitDansLeFuseauDeLAppareil() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = paris
        func local(_ m: Int, _ j: Int, _ h: Int, _ min: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: m, day: j, hour: h, minute: min))!
        }
        let nuit = QuietHours(start: 22, end: 7, timeZone: paris)
        // Passage à l'heure d'été (29 mars) : 23 h 30 à Paris est à 22 h 30 UTC, 7 h 00 d'été à 05 h 00 UTC.
        let printemps = Echeances.liste(plan: plan(fins: [0], origine: local(3, 28, 23, 30)), nom: nom, quietHours: nuit,
                                        now: local(3, 28, 12))
        #expect(printemps.map(\.date) == [local(3, 29, 7)])
        #expect(printemps[0].date == Date(timeIntervalSince1970: local(3, 28, 23, 30).timeIntervalSince1970 + 6.5 * 3600))
        // Retour à l'heure d'hiver (25 octobre) : la nuit dure une heure de plus.
        let automne = Echeances.liste(plan: plan(fins: [0], origine: local(10, 24, 23, 30)), nom: nom, quietHours: nuit,
                                      now: local(10, 24, 12))
        #expect(automne[0].date == Date(timeIntervalSince1970: local(10, 24, 23, 30).timeIntervalSince1970 + 8.5 * 3600))
    }

    @Test func leTexteNeContientPasLeTag() {
        let e = Echeances.liste(plan: plan(fins: [3600, 9000]), nom: nom, quietHours: nil, now: Rest.date)
        #expect(!e.isEmpty && e.allSatisfy { !($0.titre + $0.corps).contains("#") })
    }
}
