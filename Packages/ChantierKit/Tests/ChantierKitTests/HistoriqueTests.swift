import Foundation
import Testing
@testable import ChantierKit

// Historique (T07) : photos enregistrées tel quel, une seule par `timestamp`, relues du plus récent au plus ancien.

/// Un dossier neuf par test, supprimé à la fin.
struct DossierTemporaire {
    let url = FileManager.default.temporaryDirectory.appending(path: "chantier-test-\(UUID().uuidString)")
    var store: SnapshotStore { SnapshotStore(directory: url) }
    func supprimer() { try? FileManager.default.removeItem(at: url) }
}

/// Un export minimal valide : seul le `timestamp` change d'un export à l'autre.
func exportMinimal(_ timestamp: Int, niveauHDV: Int = 1) -> String {
    ##"{"tag":"#2PP","timestamp":\##(timestamp),"buildings":[{"data":1000001,"lvl":\##(niveauHDV)}]}"##
}

@Suite struct HistoriqueTests {
    @Test func deuxImportsDuMemeTimestampFontUneSeulePhoto() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = dossier.store
        let premier = try store.save(exportMinimal(1_794_414_482))
        // Même timestamp, contenu différent : la première photo est gardée, rien n'est écrasé.
        let second = try store.save(exportMinimal(1_794_414_482, niveauHDV: 2))
        guard case .created(let photo) = premier else { Issue.record("première : \(premier)"); return }
        #expect(second == .alreadyStored(photo))
        #expect(store.list() == [photo])
        #expect(store.text(of: photo) == exportMinimal(1_794_414_482))
    }

    @Test func exportEnregistreTelQuelDansUnFichierNommeParSaDate() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        // Espaces et ordre des clés bizarres : le texte doit ressortir à l'octet près.
        let texte = " {\n \"timestamp\" : 1794414482 ,\"tag\":\"#2PP\", \"buildings\":[ ]}\n"
        try dossier.store.save(texte)
        let noms = try FileManager.default.contentsOfDirectory(atPath: dossier.url.path)
        #expect(noms == ["20261111T162802Z.json"])
        let relu = try String(contentsOf: dossier.url.appending(path: noms[0]), encoding: .utf8)
        #expect(relu == texte)
    }

    @Test func untexteQuiNestPasUnExportNeChangeRien() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = dossier.store
        try store.save(exportMinimal(1_000))
        for (texte, erreur) in [("", ExportError.empty), ("bonjour", .notJSON), ("{\"a\":1}", .notAVillageExport),
                                (try Fixtures.texte("abime-02-tronque"), .notJSON)] {
            #expect(throws: SnapshotStore.SaveError.invalid(erreur)) { try store.save(texte) }
        }
        #expect(store.list().count == 1)
    }

    @Test func listeEnOrdreDuTempsEtRelitLaPlusRecente() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = dossier.store
        #expect(store.latest() == nil)
        for t in [3_000, 1_000, 2_000] { try store.save(exportMinimal(t)) }
        #expect(store.list().map(\.date.timeIntervalSince1970) == [1_000, 2_000, 3_000])
        #expect(store.latest()?.snapshot.date == Date(timeIntervalSince1970: 3_000))
        #expect(store.latest()?.export.date == Date(timeIntervalSince1970: 3_000))
    }

    @Test func photoAbimeeEstSauteEtLaPrecedenteSert() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = dossier.store
        try store.save(exportMinimal(1_000))
        try Data("abîmé".utf8).write(to: dossier.url.appending(path: Snapshot(date: Date(timeIntervalSince1970: 2_000)).fileName))
        #expect(store.latest()?.snapshot.date == Date(timeIntervalSince1970: 1_000))
    }

    @Test func fichierAbimeDeLaMemeDateEstReecritParLExportValide() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = dossier.store
        let photo = Snapshot(date: Date(timeIntervalSince1970: 1_794_414_482))
        try FileManager.default.createDirectory(at: dossier.url, withIntermediateDirectories: true)
        try Data("abîmé".utf8).write(to: dossier.url.appending(path: photo.fileName))
        #expect(try store.save(exportMinimal(1_794_414_482)) == .created(photo))
        #expect(store.text(of: photo) == exportMinimal(1_794_414_482))
        #expect(store.latest()?.snapshot == photo)
    }

    @Test func fichiersEtrangersDuDossierSontIgnores() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = dossier.store
        try store.save(exportMinimal(1_000))
        try Data().write(to: dossier.url.appending(path: ".DS_Store"))
        try Data().write(to: dossier.url.appending(path: "notes.json"))
        #expect(store.list().count == 1)
    }

    @Test func nomDeFichierFaitLAllerRetour() {
        let snapshot = Snapshot(date: Date(timeIntervalSince1970: 1_794_414_482.9))
        #expect(snapshot.fileName == "20261111T162802Z.json")
        #expect(Snapshot(fileName: snapshot.fileName) == snapshot)
    }

    // MARK: Âge de la photo

    private static let paris: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    /// 12 novembre 2026, 10 h 00 à Paris (UTC+1).
    private static let maintenant = Date(timeIntervalSince1970: 1_794_474_000)

    private func age(_ jours: Int, _ heure: Int, _ minute: Int) -> String {
        let jour = Self.paris.date(byAdding: .day, value: -jours, to: Self.maintenant)!
        let date = Self.paris.date(bySettingHour: heure, minute: minute, second: 0, of: jour)!
        return Snapshot(date: date).ageDescription(now: Self.maintenant, calendar: Self.paris)
    }

    @Test func ageDeLaPhotoEnFrancais() {
        #expect(age(0, 9, 5) == "photo d'aujourd'hui, 9\u{A0}h\u{A0}05")
        #expect(age(1, 17, 28) == "photo d'hier, 17\u{A0}h\u{A0}28")
        #expect(age(2, 8, 0) == "photo de mardi, 8\u{A0}h\u{A0}00")     // le 10 novembre 2026 est un mardi
        #expect(age(6, 23, 59) == "photo de vendredi, 23\u{A0}h\u{A0}59")
        #expect(age(7, 12, 0) == "photo du 5 novembre, 12\u{A0}h\u{A0}00")
        #expect(age(400, 12, 0) == "photo du 8 octobre 2025, 12\u{A0}h\u{A0}00")
    }

    @Test func photoDuFuturResteDAujourdhui() {
        let date = Self.maintenant.addingTimeInterval(3_600)
        #expect(Snapshot(date: date).ageDescription(now: Self.maintenant, calendar: Self.paris)
                == "photo d'aujourd'hui, 11\u{A0}h\u{A0}00")
    }

    // MARK: Du fichier à l'écran (trois exports « version future »)

    /// Enregistre, relit, calcule : ce que fait l'écran Cap.
    private func calculer(_ nom: String) throws -> (Village, ProgressReport) {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        try dossier.store.save(Fixtures.texte(nom))
        let export = try #require(dossier.store.latest()).export
        let reference = try ReferenceData.load()
        let village = Village(export: export, reference: reference)
        return (village, progress(of: village, reference: reference))
    }

    @Test func villageNormalAffichePourcentageSansBandeau() throws {
        let (village, rapport) = try calculer("reel-hdv16")
        #expect(village.status == .ok)
        #expect(rapport.total != nil)
        #expect(rapport.categories.count == Category.allCases.count)
    }

    @Test func futur01SectionInconnueDonneLeBandeauEtGardeLesPourcentages() throws {
        let (village, rapport) = try calculer("futur-01-section-inconnue")
        #expect(village.status == .staleReference)
        #expect(rapport.total != nil)
    }

    @Test func futur05NiveauAuDessusDuMaximumDonneLeBandeauEtGardeLesPourcentages() throws {
        let (village, rapport) = try calculer("futur-05-niveau-999")
        #expect(village.status == .staleReference)
        #expect(rapport.total != nil)
    }

    @Test func futur04HdvInconnuNeDonneAucunPourcentageMaisLInventaire() throws {
        let (village, rapport) = try calculer("futur-04-hdv-99")
        #expect(village.status == .unknownTownHall)
        #expect(village.townHall == 99)
        #expect(rapport.total == nil)
        #expect(rapport.categories.isEmpty)
        #expect(!village.elements.isEmpty)       // l'inventaire de la photo reste lisible
    }
}
