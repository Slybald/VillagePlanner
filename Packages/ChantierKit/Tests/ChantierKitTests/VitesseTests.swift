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
    /// Reconstruction de l'index (T22) : 365 photos réelles, un an à raison d'une par jour. Temps réel, tous les cœurs.
    @Test func reconstructionDeLIndexDe365PhotosEnMoinsDe60s() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url)
        let ctx = HistoryContext(reference: Réel.reference, advice: Réel.advice)
        let texte = try Fixtures.texte("reel-hdv16")
        for jour in 0..<365 {
            let t = texte.replacingOccurrences(of: "\"timestamp\":1794414482", with: "\"timestamp\":\(1_794_414_482 + jour * 86_400)")
            try h.photos.save(t)
        }
        let debut = ContinuousClock.now
        let listing = h.refresh(ctx)
        let duree = ContinuousClock.now - debut
        print("index de 365 photos : \(duree)")
        #expect(listing.entries.count == 365)
        #expect(duree < .seconds(60))
        // Un index à jour se relit sans recalcul.
        let debut2 = ContinuousClock.now
        _ = h.refresh(ctx)
        #expect(ContinuousClock.now - debut2 < .seconds(1))
    }
}
