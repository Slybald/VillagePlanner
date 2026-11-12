import Foundation
import Testing
@testable import ChantierKit

/// Seuils de vitesse du cahier des charges, en temps processeur. Ignorés par défaut : sous charge
/// (suite parallèle, CI) ils deviennent instables. Lancer : `CHANTIER_VITESSE=1 swift test --filter Vitesse --no-parallel`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CHANTIER_VITESSE"] == "1"))
struct VitesseTests {
    @Test func lectureDeReelHdv16EnMoinsDe50ms() throws {
        let texte = try Fixtures.texte("reel-hdv16")
        let mediane = medianeCPU(passages: 21) { _ = try? VillageExport.parse(texte) }
        print("lecture reel-hdv16 : médiane \(mediane) ms de temps processeur sur 21 passages")
        #expect(mediane < 50)
    }

    @Test func chargementEmbarqueEnMoinsDe100ms() throws {
        let mediane = try medianeCPU { _ = try ReferenceData.load() }
        #expect(mediane < 100, "chargement en \(mediane) ms de temps processeur")
    }

    @Test func makePlanSurReelHdv16EnMoinsDe200msDeTempsProcesseur() {
        _ = Réel.plan
        let runs = (0..<5).map { _ -> Double in
            let debut = tempsCPUFilCourant()
            _ = makePlan(for: Réel.village, reference: Réel.reference, advice: Réel.advice, profile: Profile(), now: Réel.export.date)
            return tempsCPUFilCourant() - debut
        }.sorted()
        print("makePlan reel-hdv16 : médiane \(runs[2]) ms de processeur, max \(runs[4]) ms sur 5 passages")
        #expect(runs[2] < 200)
    }
}
