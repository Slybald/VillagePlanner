import Testing
@testable import VillagePlannerKit
@testable import outils

// Chemins des illustrations dans ClashKingAssets (règle de nommage de son README).
struct MajImagesTests {
    @Test func nomsNettoyes() {
        #expect(MajImages.nomNettoye("P.E.K.K.A") == "pekka")
        #expect(MajImages.nomNettoye("Builder's Hut") == "builder's_hut")
        #expect(MajImages.nomNettoye("X-Bow") == "x-bow")
        #expect(MajImages.nomNettoye("L.A.S.S.I") == "lassi")
    }

    @Test func unFichierParNiveauPourLesBatimentsUneIconeSinon() throws {
        let reference = try ReferenceData.load()
        let canon = try #require(reference.item(1000008))
        let f = MajImages.fichiers(canon)
        #expect(f.count == canon.levels.count)
        #expect(f.first?.local == "1000008_1.webp")
        #expect(f.first?.distant == "assets/buildings/home-village/cannon/level_1.webp")
        let roi = try #require(reference.item(28000000))
        #expect(MajImages.fichiers(roi).map(\.distant) == ["assets/heroes/barbarian_king/icon.webp"])
        // Hors avancement : aucune image.
        let horsAvancement = try #require(reference.items.first { $0.category == nil })
        #expect(MajImages.fichiers(horsAvancement).isEmpty)
    }
}
