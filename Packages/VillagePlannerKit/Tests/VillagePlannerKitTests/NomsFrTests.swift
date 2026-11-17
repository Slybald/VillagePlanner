import Foundation
import Testing
@testable import VillagePlannerKit
@testable import outils

/// Chaque élément qui compte dans l'avancement a un nom français (T33).
@Suite struct NomsFrTests {
    @Test func chaqueElementAvecCategorieAUnNomFrancais() throws {
        let noms = try NomsFr.lire()
        let reference = try ReferenceData.load(from: NomsFr.fichier
            .deletingLastPathComponent().appendingPathComponent("reference.json"))
        let sansNom = reference.items.filter { $0.category != nil && noms[String($0.id)] == nil }.map(\.id)
        #expect(sansNom.isEmpty, "sans nom français : \(sansNom)")
    }

    @Test func fusionSignaleUnElementSansNom() throws {
        let reference = try ReferenceData.load(from: NomsFr.fichier
            .deletingLastPathComponent().appendingPathComponent("reference.json"))
        let (nomme, sansNom) = NomsFr.fusionner(reference, noms: [:])
        #expect(sansNom.count == reference.items.filter { $0.category != nil }.count)
        #expect(nomme.items.allSatisfy { $0.names["fr"] == nil })
    }

    /// Le chargement embarqué rend le nom du jeu en français, et l'anglais si le nom manque.
    @Test func chargementRendLeNomFrancaisDuCanon() throws {
        let reference = try ReferenceData.load()
        #expect(reference.name(of: 1000008) == "Canon")
        #expect(reference.name(of: 1000009) == "Tour d'archères")
        #expect(reference.name(of: -1) == nil)
        let sans = reference.withFrenchNames([:])
        #expect(sans.item(1000009)?.names["fr"] == reference.item(1000009)?.names["fr"])
        let anglais = ReferenceData(items: [ReferenceItem(id: 7, names: ["en": "Cannon"], section: "buildings",
            category: nil, exclusion: nil, worker: .builder, levels: [], countByTownHall: [], maxLevelByTownHall: [],
            mergedFrom: [])])
        #expect(anglais.name(of: 7) == "Cannon")
    }

    @Test func chaqueElementAvecCategorieAUnNomFrancaisApresChargement() throws {
        let sansNom = try ReferenceData.load().items.filter { $0.category != nil && $0.names["fr"] == nil }.map(\.id)
        #expect(sansNom.isEmpty, "sans nom français : \(sansNom)")
    }
}
