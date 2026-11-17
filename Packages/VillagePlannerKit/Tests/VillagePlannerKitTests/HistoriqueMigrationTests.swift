import Foundation
import Testing
@testable import VillagePlannerKit

// T23 : l'app passe de `SnapshotStore.save` à `HistoryStore.add`. Les photos déjà là ne doivent ni bouger ni se perdre.

@Suite struct HistoriqueMigrationTests {
    @Test func photoDeLAncienCheminRelueParLeNouveauSansEtreDeplacee() throws {
        let racine = FileManager.default.temporaryDirectory.appending(path: "villageplanner-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: racine) }
        // Ancien chemin : l'app écrivait dans `<racine>/Photos`.
        let ancien = SnapshotStore(directory: racine.appending(path: "Photos"))
        let texte = exportMinimal(1_794_414_482)
        guard case .created(let photo) = try ancien.save(texte) else { Issue.record("pas créée"); return }
        let avant = try FileManager.default.contentsOfDirectory(atPath: ancien.directory.path)

        let historique = HistoryStore(root: racine)
        #expect(historique.photos.directory == ancien.directory)
        #expect(historique.photos.list() == [photo])
        #expect(historique.photos.text(of: photo) == texte)
        // Une nouvelle photo s'ajoute à côté, l'ancienne reste où elle est, octet pour octet.
        let (_, listing) = try historique.add(exportMinimal(1_794_500_000), context: HistoryContext(reference: try ReferenceData.load()))
        #expect(listing.entries.count == 2)
        #expect(try String(contentsOf: ancien.directory.appending(path: photo.fileName), encoding: .utf8) == texte)
        #expect(avant.allSatisfy { FileManager.default.fileExists(atPath: ancien.directory.appending(path: $0).path) })
    }

    @Test func lesPhotosDeLAppRestentDansApplicationSupportPhotos() {
        #expect(HistoryStore(root: .applicationSupportDirectory).photos.directory
                == URL.applicationSupportDirectory.appending(path: "Photos"))
    }
}
