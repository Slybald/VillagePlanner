import Foundation
import Testing
@testable import ChantierKit

// T25 : les photos passent dans le conteneur partagé, une seule fois, sans perte. Dossiers temporaires seulement.

private func dossierTemporaire() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "chantier-stockage-\(UUID().uuidString)")
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
    }

    @Test func sansConteneurPartage_toutResteDansApplicationSupport_sansErreur() throws {
        let support = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support) }
        let photos = SnapshotStore(directory: support.appending(path: "Photos"))
        try photos.save(exportMinimal(1_794_414_482))
        let avant = lister(support)
        #expect(Stockage.racine(support: support, partage: nil) == support)
        #expect(lister(support) == avant)
        #expect(Stockage.conteneurPartage(bundleID: nil) == nil)     // (sur iOS, un groupe non accordé rend nil aussi)
    }

    @Test func migrationSansPerte_chaquePhotoSeRetrouveOctetPourOctet_puisLAncienEstSupprime() throws {
        let support = dossierTemporaire(), partage = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: partage) }
        let photos = SnapshotStore(directory: support.appending(path: "Photos"))
        for t in [1_794_414_482, 1_794_500_000, 1_794_600_000] { try photos.save(exportMinimal(t)) }
        let reference = try ReferenceData.load()
        _ = HistoryStore(root: support).refresh(HistoryContext(reference: reference))     // écrit index.json
        try Data("{\"format\":1}".utf8).write(to: support.appending(path: "joueur.json"))
        try Data("{}".utf8).write(to: support.appending(path: "joueur-abime-1794000000.json"))
        try Data("autre chose".utf8).write(to: support.appending(path: "etranger.txt"))      // pas à nous : reste
        let avant = lister(support)
        #expect(avant.keys.contains("/index.json"))
        let listeAvant = SnapshotStore(directory: support.appending(path: "Photos")).list()

        #expect(Stockage.racine(support: support, partage: partage) == partage)

        let apres = lister(partage)
        for (nom, donnees) in avant where nom != "/etranger.txt" { #expect(apres[nom] == donnees, "\(nom) perdu ou changé") }
        #expect(apres.count == avant.count - 1)
        #expect(SnapshotStore(directory: partage.appending(path: "Photos")).list() == listeAvant)
        // L'ancien est supprimé après vérification, sauf ce qui n'est pas à nous.
        #expect(lister(support).keys.sorted() == ["/etranger.txt"])
        #expect(!FileManager.default.fileExists(atPath: support.appending(path: "Photos").path))
    }

    @Test func migrationUneSeuleFois_unSecondPassageNeCopieRienEtNeTouchePasLesNouvellesPhotos() throws {
        let support = dossierTemporaire(), partage = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: partage) }
        try SnapshotStore(directory: support.appending(path: "Photos")).save(exportMinimal(1_794_414_482))
        #expect(Stockage.migrer(de: support, vers: partage).copies == 1)
        try SnapshotStore(directory: partage.appending(path: "Photos")).save(exportMinimal(1_794_500_000))
        let avant = lister(partage)
        #expect(Stockage.migrer(de: support, vers: partage) == Stockage.Migration())
        #expect(lister(partage) == avant)
    }

    @Test func migrationReprise_unFichierDejaCopieAvecLeMemeContenuEstReconnu() throws {
        let support = dossierTemporaire(), partage = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: partage) }
        for racine in [support, partage] { try SnapshotStore(directory: racine.appending(path: "Photos")).save(exportMinimal(1_794_414_482)) }
        try SnapshotStore(directory: support.appending(path: "Photos")).save(exportMinimal(1_794_500_000))
        let bilan = Stockage.migrer(de: support, vers: partage)
        #expect(bilan.dejaLa == 1 && bilan.copies == 1 && bilan.estComplete && bilan.conflits.isEmpty)
        #expect(SnapshotStore(directory: partage.appending(path: "Photos")).list().count == 2)
        #expect(lister(support).isEmpty)
    }

    @Test func fichierDeMemeNomMaisDeContenuDifferent_jamaisEcrase_l_originalResteOuIlEst() throws {
        let support = dossierTemporaire(), partage = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: partage) }
        let nom = Snapshot(date: Date(timeIntervalSince1970: 1_794_414_482)).fileName
        for (racine, texte) in [(support, "ancien"), (partage, "autre")] {
            try FileManager.default.createDirectory(at: racine.appending(path: "Photos"), withIntermediateDirectories: true)
            try Data(texte.utf8).write(to: racine.appending(path: "Photos").appending(path: nom))
        }
        let bilan = Stockage.migrer(de: support, vers: partage)
        #expect(bilan.conflits == ["Photos/" + nom])
        #expect(try String(contentsOf: partage.appending(path: "Photos").appending(path: nom), encoding: .utf8) == "autre")
        #expect(try String(contentsOf: support.appending(path: "Photos").appending(path: nom), encoding: .utf8) == "ancien")
    }

    @Test func copieImpossible_rienNEstSupprime_etLaRacineResteApplicationSupport() throws {
        let support = dossierTemporaire(), faux = dossierTemporaire()
        defer { try? FileManager.default.removeItem(at: support); try? FileManager.default.removeItem(at: faux) }
        try SnapshotStore(directory: support.appending(path: "Photos")).save(exportMinimal(1_794_414_482))
        try Data("je suis un fichier, pas un dossier".utf8).write(to: faux)     // la destination ne peut pas recevoir de dossier
        let avant = lister(support)
        let bilan = Stockage.migrer(de: support, vers: faux)
        #expect(!bilan.estComplete && bilan.copies == 0)
        #expect(lister(support) == avant)
        #expect(Stockage.racine(support: support, partage: faux) == support)
    }
}
