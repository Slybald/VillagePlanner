import Foundation
import Testing
@testable import ChantierKit
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
}
