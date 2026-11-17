import Foundation
import Testing
@testable import VillagePlannerKit

// Enregistrement du profil de jeu (T17) : relecture, décodage tolérant, réduction expirée, recalcul du cap.

@Suite struct ProfilStoreTests {
    /// Des préférences neuves pour chaque test.
    private func neuf() -> (ProfilStore, UserDefaults) {
        let d = PreferencesDeTest.neuves()
        return (ProfilStore(defaults: d), d)
    }

    private func decoder(_ json: String) throws -> Profile {
        try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
    }

    @Test func enregistrementEtRelecture_tousLesReglagesSontRetrouves() {
        let (store, _) = neuf()
        let profil = Profile(builderReduction: Reduction(percent: 20, endsAt: Sim.at(5000)),
                             laboratoryReduction: Reduction(percent: 10, endsAt: Sim.at(9000)),
                             orientation: .attack, heroLimit: 2, pinned: [1000001, 1000007],
                             nextTownHallThreshold: .heroesAndLab,
                             quietHours: QuietHours(start: 22, end: 6, timeZone: Sim.utc))
        store.save(profil)
        #expect(store.load() == profil)
    }

    @Test func aucunEnregistrement_donneLeProfilParDefaut() {
        #expect(neuf().0.load() == Profile())
    }

    @Test func pasDHeuresSansJeu_nilSeRelitNilEtNonLeDefaut() {
        let (store, _) = neuf()
        store.save(Profile(quietHours: nil))
        #expect(store.load().quietHours == nil)
    }

    @Test func decodageTolerant_unChampIllisibleNeTouchePasLesAutres() throws {
        // Orientation inconnue (version plus récente), limite de héros d'un mauvais type : défauts ; le reste est gardé.
        let p = try decoder(#"{"orientation":"cyclone","heroLimit":"deux","pinned":[3,4],"builderReduction":{"percent":30,"endsAt":1000}}"#)
        #expect(p.orientation == .balanced)
        #expect(p.heroLimit == nil)
        #expect(p.pinned == [3, 4])
        #expect(p.builderReduction == Reduction(percent: 30, endsAt: Date(timeIntervalSinceReferenceDate: 1000)))
    }

    @Test func decodageTolerant_profilDUneVersionAncienne_champsAbsentsAuDefaut() throws {
        let ancien = try decoder(#"{"orientation":"defense","heroLimit":1}"#)
        #expect(ancien == Profile(orientation: .defense, heroLimit: 1))
        #expect(try decoder("{}") == Profile())
    }

    @Test func decodageTolerant_reductionIncomplete_estIgnoreeSansEffacerLeReste() throws {
        let p = try decoder(#"{"laboratoryReduction":{"percent":10},"pinned":[9]}"#)
        #expect(p.laboratoryReduction == nil)
        #expect(p.pinned == [9])
    }

    @Test func decodageTolerant_blobAbimeDansLesPreferences_defautSansRienEffacer() {
        let (store, d) = neuf()
        let abime = Data("pas du json".utf8)
        d.set(abime, forKey: "profil")
        #expect(store.load() == Profile())
        #expect(d.data(forKey: "profil") == abime)
    }

    @Test func reductionExpiree_neSAppliquePlusApresRelecture() {
        let (store, _) = neuf()
        store.save(Profile(builderReduction: Reduction(percent: 50, endsAt: Sim.at(100))))
        let relu = store.load()
        #expect(relu.reductionPercent(for: .builder, at: Sim.at(99)) == 50)
        #expect(relu.reductionPercent(for: .builder, at: Sim.at(100)) == 0)
        // Elle reste enregistrée : les Réglages peuvent dire qu'elle est finie.
        #expect(relu.builderReduction?.percent == 50)
    }

    @Test func changerLaReduction_changeLeCapDuPlan() {
        let items = [Prio.item(Prio.cannon, .defenses, [Sim.lv(1000), Sim.lv(1000), Sim.lv(1000)])]
        let sections = ["buildings": [Prio.e(Prio.cannon, 1)]]
        func cap(_ r: Reduction?) -> Int {
            Sim.offset(Sim.plan(items, sections, profile: Profile(builderReduction: r, quietHours: nil)).cap!)
        }
        #expect(cap(nil) == 2000)
        #expect(cap(Reduction(percent: 50, endsAt: .distantFuture)) == 1000)
        #expect(cap(Reduction(percent: 50, endsAt: Sim.at(-1))) == 2000)   // expirée : comme sans réduction
    }

    @Test func reductionDeLExemple_seJugeALaDateDAffichage_pasALaDateDExport() {
        let export = Date(timeIntervalSince1970: 1_000_000), aujourdhui = Date(timeIntervalSince1970: 5_000_000)
        let finie = Reduction(percent: 20, endsAt: aujourdhui.addingTimeInterval(-1))
        let enCours = Reduction(percent: 30, endsAt: aujourdhui.addingTimeInterval(3 * 86_400))
        let p = Profile(builderReduction: finie, laboratoryReduction: enCours).affiche(le: aujourdhui, calcule: export)
        #expect(p.builderReduction == nil)      // finie aujourd'hui, même si active à la date de l'export
        #expect(p.laboratoryReduction == Reduction(percent: 30, endsAt: export.addingTimeInterval(3 * 86_400)))
    }
}
