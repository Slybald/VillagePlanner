import Foundation
import Testing
@testable import VillagePlannerKit

// T25 : les photos restent dans Application Support, que l'App Group existe ou non. Le seul code qui touche au conteneur
// partagé côté photos est un filet de sécurité qui COPIE. Dossiers temporaires seulement.

private func dossierTemporaire() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "villageplanner-stockage-\(UUID().uuidString)")
}

private func lister(_ racine: URL) -> [String: Data] {
    var sortie: [String: Data] = [:]
    let base = racine.resolvingSymlinksInPath()
    guard let sous = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return sortie }
    for case let url as URL in sous where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
        sortie[String(url.resolvingSymlinksInPath().path.dropFirst(base.path.count))] = try? Data(contentsOf: url)
    }
    return sortie
}

@Suite struct StockageTests {
    @Test func leGroupeVientDeLIdentifiantDeLApp_celuiDuWidgetDonneLeMeme() {
        #expect(Stockage.groupe(bundleID: "fr.slybald.chantier") == "group.fr.slybald.chantier")
        #expect(Stockage.groupe(bundleID: "fr.slybald.chantier.widget") == "group.fr.slybald.chantier")
        #expect(Stockage.conteneurPartage(bundleID: nil) == nil)     // (sur iOS, un groupe non accordé rend nil aussi)
    }

    @Test func lesPhotosEtLIndexSontToujoursDansApplicationSupport_avecOuSansConteneur() throws {
        // La racine de l'historique ne dépend pas de l'App Group : même dossier à YES et à NO.
        let support = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support) }
        for t in [1_794_414_482, 1_794_500_000] { try SnapshotStore(directory: support.appending(path: "Photos")).save(exportMinimal(t)) }
        let avant = lister(support)
        let historique = HistoryStore(root: support)
        #expect(historique.photos.list().count == 2)
        // Ouvrir le conteneur (YES) puis ne plus l'avoir (NO) ne touche à aucune photo.
        let partage = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: partage) }
        let etat = WidgetEtat(photo: Date(timeIntervalSince1970: 1_794_414_482), postes: [])
        #expect(etat.ecrire(dans: partage))
        #expect(lister(support) == avant)
        #expect(HistoryStore(root: support).photos.list().count == 2)
        #expect(lister(support) == avant)
    }

    @Test func filet_copieCeQuiManqueSansRienSupprimerNiEcraser() throws {
        let support = dossierTemporaire(), partage = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: partage) }
        // Une ancienne version de test avait déplacé 3 photos dans le conteneur ; 1 est déjà revenue dans Application Support.
        let dansPartage = SnapshotStore(directory: partage.appending(path: "Photos"))
        for t in [1_794_414_482, 1_794_500_000, 1_794_600_000] { try dansPartage.save(exportMinimal(t)) }
        try Data("{\"format\":1}".utf8).write(to: partage.appending(path: "joueur.json"))
        try SnapshotStore(directory: support.appending(path: "Photos")).save(exportMinimal(1_794_414_482))
        let avantPartage = lister(partage)

        let bilan = Stockage.recuperer(depuis: partage, vers: support)
        #expect(bilan.copies == 3 && bilan.conflits.isEmpty && bilan.echecs.isEmpty)   // 2 photos + joueur.json
        #expect(SnapshotStore(directory: support.appending(path: "Photos")).list() == dansPartage.list())
        #expect(lister(partage) == avantPartage)                    // le conteneur n'a perdu aucun fichier
        // Rejouer ne change rien.
        let avantSupport = lister(support)
        #expect(Stockage.recuperer(depuis: partage, vers: support) == Stockage.Recuperation())
        #expect(lister(support) == avantSupport)
    }

    @Test func filet_unConflitDeNomEstCopieSousUnAutreNom_sansEcraserLOriginal() throws {
        let support = dossierTemporaire(), partage = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: partage) }
        let nom = Snapshot(date: Date(timeIntervalSince1970: 1_794_414_482)).fileName
        for (racine, texte) in [(support, "celle d'Application Support"), (partage, "celle du conteneur")] {
            try FileManager.default.createDirectory(at: racine.appending(path: "Photos"), withIntermediateDirectories: true)
            try Data(texte.utf8).write(to: racine.appending(path: "Photos").appending(path: nom))
        }
        let bilan = Stockage.recuperer(depuis: partage, vers: support)
        #expect(bilan.conflits == ["Photos/" + nom])
        let conflit = nom + ".conflit"
        #expect(try String(contentsOf: support.appending(path: "Photos").appending(path: nom), encoding: .utf8) == "celle d'Application Support")
        #expect(try String(contentsOf: support.appending(path: "Photos").appending(path: conflit), encoding: .utf8) == "celle du conteneur")
        #expect(try String(contentsOf: partage.appending(path: "Photos").appending(path: nom), encoding: .utf8) == "celle du conteneur")
        // Le fichier « .conflit » n'est pas une photo pour l'app, mais il est gardé ; un second passage ne le signale plus.
        #expect(SnapshotStore(directory: support.appending(path: "Photos")).list().count == 1)
        #expect(Stockage.recuperer(depuis: partage, vers: support) == Stockage.Recuperation())
    }

    @Test func filet_sansConteneurOuSansPhotos_neFaitRienEtNeSupprimeRien() throws {
        let support = dossierTemporaire(), vide = dossierTemporaire(), absent = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: vide) }
        try SnapshotStore(directory: support.appending(path: "Photos")).save(exportMinimal(1_794_414_482))
        try FileManager.default.createDirectory(at: vide, withIntermediateDirectories: true)
        let avant = lister(support)
        #expect(Stockage.recuperer(depuis: vide, vers: support) == Stockage.Recuperation())
        #expect(Stockage.recuperer(depuis: absent, vers: support) == Stockage.Recuperation())
        #expect(lister(support) == avant)
    }

    @Test func filet_destinationImpossible_signaleEnEchec_sansRienPerdre() throws {
        let support = dossierTemporaire(), partage = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: partage) }
        try SnapshotStore(directory: partage.appending(path: "Photos")).save(exportMinimal(1_794_414_482))
        try Data("un fichier, pas un dossier".utf8).write(to: support)
        let avant = lister(partage)
        let bilan = Stockage.recuperer(depuis: partage, vers: support)
        #expect(bilan.copies == 0 && !bilan.echecs.isEmpty)
        #expect(lister(partage) == avant)
    }
}
