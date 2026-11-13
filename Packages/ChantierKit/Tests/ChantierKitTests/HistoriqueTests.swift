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

// Index et différences (T22). Référence inventée : `Mini` (VillageTests.swift).

/// Un export à une date donnée. `batiments` : le contenu du tableau "buildings", en JSON.
func photoMini(_ t: Int, _ batiments: String, equipements: String = "") -> String {
    let eq = equipements.isEmpty ? "" : ##","equipment":[\##(equipements)]"##
    return ##"{"tag":"#2PP","timestamp":\##(t),"buildings":[{"data":1000001,"lvl":3},\##(batiments)]\##(eq)}"##
}
func canonMini(_ niveau: Int, cnt: Int = 1, timer: String? = nil) -> String {
    ##"{"data":1000008,"lvl":\##(niveau),"cnt":\##(cnt)\##(timer.map { ",\"timer\":" + $0 } ?? "")}"##
}
func villageMini(_ texte: String, _ ref: ReferenceData = Mini.reference) throws -> Village {
    Village(export: try VillageExport.parse(texte), reference: ref)
}
func ctxMini(_ ref: ReferenceData = Mini.reference) -> HistoryContext { HistoryContext(reference: ref) }
func diffMini(_ a: String, _ b: String, _ ref: ReferenceData = Mini.reference) throws -> PhotoDiff {
    PhotoDiff(old: try villageMini(a, ref), oldSummary: nil, new: try villageMini(b, ref), newSummary: nil)
}

@Suite struct HistoriqueIndexTests {
    // MARK: - Différences

    @Test func memePhotoDeuxFoisNeChangeRien() throws {
        let p = photoMini(1_000, canonMini(2, cnt: 2, timer: "50"))
        let d = try diffMini(p, p)
        #expect(d.isEmpty)
        #expect(!d.swapped)
    }

    @Test func niveauxGagnesLanceesEtTerminees() throws {
        // Canon 1 en cours vers 2 ; canon 3 au niveau 2. Ensuite : le premier est au 2, le second est lancé.
        let avant = photoMini(1_000, canonMini(1, timer: "50") + "," + canonMini(2))
        let apres = photoMini(2_000, canonMini(2) + "," + canonMini(2, timer: "99"))
        let d = try diffMini(avant, apres)
        #expect(d.levelsGained == [PhotoDiff.ItemCount(itemID: 1000008, count: 1)])
        #expect(d.finished == [PhotoDiff.ItemCount(itemID: 1000008, count: 1)])
        #expect(d.started == [PhotoDiff.ItemCount(itemID: 1000008, count: 1)])
        #expect(d.totalLevelsGained == 1)
    }

    @Test func amelioration_enchainee_compteTermineeEtLancee() throws {
        let d = try diffMini(photoMini(1_000, canonMini(1, timer: "50")), photoMini(2_000, canonMini(2, timer: "70")))
        #expect(d.finished.map(\.count) == [1])
        #expect(d.started.map(\.count) == [1])
        // Un minuteur qui continue n'est ni lancé ni terminé.
        let suite = try diffMini(photoMini(1_000, canonMini(1, timer: "50")), photoMini(2_000, canonMini(1, timer: "10")))
        #expect(suite.isEmpty)
    }

    @Test func photoPlusAncienneQueLaPrecedenteEstComparéeDansLOrdreDuTemps() throws {
        let a = photoMini(1_000, canonMini(1)), b = photoMini(2_000, canonMini(2))
        let droit = try diffMini(a, b), envers = try diffMini(b, a)
        #expect(envers.swapped)
        #expect(envers.from < envers.to)
        #expect(envers.levelsGained == droit.levelsGained)   // pas de niveau « perdu »
        #expect(envers.levelsGained.count == 1)
    }

    @Test func elementNouveauEtElementDisparu() throws {
        // Un équipement au niveau 1 est tenu pour non possédé (V4) : il sort du village.
        let sans = photoMini(1_000, canonMini(1))
        let avec = photoMini(2_000, canonMini(1), equipements: ##"{"data":90000000,"lvl":2}"##)
        let avecAvant = photoMini(500, canonMini(1), equipements: ##"{"data":90000000,"lvl":2}"##)
        let ajout = try diffMini(sans, avec)
        #expect(ajout.added == [90000000])
        #expect(ajout.levelsGained.contains(PhotoDiff.ItemCount(itemID: 90000000, count: 2)))
        let retrait = try diffMini(avecAvant, sans)
        #expect(retrait.removed == [90000000])
        #expect(retrait.totalLevelsGained == 0)
    }

    @Test func fusionCanonRicochetNEstPasUnNiveauPerdu() throws {
        let canonId = 1000008, ricochet = 1000085
        let r = ReferenceData(items: [
            Mini.item(Mini.th, "buildings", .economy, counts: [0, 1, 1, 1], max: [0, 1, 2, 3], weights: [0, 100, 200]),
            Mini.item(canonId, "buildings", .defenses, counts: [0, 1, 4, 4], max: [0, 1, 2, 3], weights: [10, 20, 30]),
            Mini.item(ricochet, "buildings", .defenses, counts: [0, 0, 0, 1], max: [0, 0, 0, 2], weights: [40, 50],
                      mergedFrom: [Requirement(itemID: canonId, level: 3), Requirement(itemID: canonId, level: 3)]),
        ], maxTownHall: 3)
        let avant = photoMini(1_000, canonMini(3, cnt: 4))
        let apres = photoMini(2_000, canonMini(3, cnt: 2) + ##",{"data":1000085,"lvl":1}"##)
        let d = try diffMini(avant, apres, r)
        #expect(d.levelsGained == [PhotoDiff.ItemCount(itemID: ricochet, count: 1)])
        #expect(d.removed.isEmpty)
        #expect(d.finished.isEmpty)
        // La fusion a consommé le canon le plus haut : le rang des canons restants baisse, ce n'est pas une perte.
        let inegaux = try diffMini(photoMini(1_000, canonMini(3) + "," + canonMini(2)),
                                   photoMini(2_000, canonMini(2) + ##",{"data":1000085,"lvl":1}"##), r)
        #expect(inegaux.levelsGained == [PhotoDiff.ItemCount(itemID: ricochet, count: 1)])
        #expect(inegaux.totalLevelsGained == 1)
    }

    @Test func minuteurIllisibleCompteCommeEnCours() throws {
        let illisible = ##""bientôt""##
        let lance = try diffMini(photoMini(1_000, canonMini(1)), photoMini(2_000, canonMini(1, timer: illisible)))
        #expect(lance.started.map(\.count) == [1])
        let fini = try diffMini(photoMini(1_000, canonMini(1, timer: illisible)), photoMini(2_000, canonMini(2)))
        #expect(fini.finished.map(\.count) == [1])
        let toujours = try diffMini(photoMini(1_000, canonMini(1, timer: illisible)), photoMini(2_000, canonMini(1, timer: illisible)))
        #expect(toujours.isEmpty)
    }

    // MARK: - Index

    func remplir(_ h: HistoryStore, _ dates: [Int], _ ctx: HistoryContext) throws {
        for (i, t) in dates.enumerated() { try h.add(photoMini(t, canonMini(min(3, 1 + i % 3))), context: ctx) }
    }

    @Test func indexSupprimeEstReconstruitAIdentique() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        try remplir(h, [3_000, 1_000, 2_000, 5_000], ctx)
        let avant = try Data(contentsOf: h.indexURL)
        let listing = h.refresh(ctx)
        try FileManager.default.removeItem(at: h.indexURL)
        let apres = h.refresh(ctx)
        #expect(apres == listing)
        #expect(try Data(contentsOf: h.indexURL) == avant)
        #expect(apres.entries.map(\.timestamp) == [1_000, 2_000, 3_000, 5_000])
    }

    @Test func indexAbimeEstReconstruitSansErreur() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        try remplir(h, [1_000, 2_000], ctx)
        let bon = try Data(contentsOf: h.indexURL)
        for abime in ["pas du json", "{\"format\":99,\"key\":\"\",\"entries\":[]}", ""] {
            try Data(abime.utf8).write(to: h.indexURL)
            #expect(h.refresh(ctx).entries.count == 2)
            #expect(try Data(contentsOf: h.indexURL) == bon)
        }
    }

    @Test func changementDeVersionDeLaReferenceRecalculeLesResumes() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url)
        let v1 = Mini.reference
        // Même items, autre version de source, durée du niveau 3 du canon différente.
        var items = Mini.items
        items[1] = Mini.item(Mini.cannon, "buildings", .defenses, counts: [0, 1, 2, 2], max: [0, 1, 2, 3], weights: [10, 20, 300])
        let v2 = ReferenceData(items: items, source: ReferenceSource(commit: "v2", date: "2027-01-01"), maxTownHall: 3)
        try h.add(photoMini(1_000, canonMini(1) + "," + canonMini(3)), context: ctxMini(v1))
        let totalV1 = h.refresh(ctxMini(v1)).entries[0].total
        let listing2 = h.refresh(ctxMini(v2))
        #expect(listing2.entries[0].total != totalV1)
        // Identique à un calcul tout neuf avec la nouvelle référence.
        let neuf = DossierTemporaire(); defer { neuf.supprimer() }
        try HistoryStore(root: neuf.url).add(photoMini(1_000, canonMini(1) + "," + canonMini(3)), context: ctxMini(v2))
        // (Les dates des fichiers diffèrent d'un dossier à l'autre : on compare le contenu calculé.)
        let temoin = HistoryStore(root: neuf.url).refresh(ctxMini(v2)).entries
        #expect(listing2.entries.map(\.total) == temoin.map(\.total))
        #expect(listing2.entries.map(\.categories) == temoin.map(\.categories))
        #expect(listing2.entries.map(\.capTimestamp) == temoin.map(\.capTimestamp))
    }

    @Test func changementDeProfilRecalculeAussi() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url)
        try h.add(photoMini(1_000, canonMini(1)), context: ctxMini())
        var profil = Profile()
        profil.heroLimit = 0
        let autre = HistoryContext(reference: Mini.reference, profile: profil)
        #expect(ctxMini().key != autre.key)
    }

    @Test func photoIllisibleEstSignaleeEtJamaisSupprimee() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        try remplir(h, [1_000, 3_000], ctx)
        let abimee = Snapshot(date: Date(timeIntervalSince1970: 2_000))
        let url = h.photos.directory.appending(path: abimee.fileName)
        try Data("abîmé".utf8).write(to: url)
        let listing = h.refresh(ctx)
        #expect(listing.unreadable == [abimee])
        #expect(listing.entries.map(\.timestamp) == [1_000, 3_000])
        #expect(FileManager.default.fileExists(atPath: url.path))
        // Après d'autres opérations aussi.
        try h.add(photoMini(4_000, canonMini(2)), context: ctx)
        _ = try h.delete(Snapshot(date: Date(timeIntervalSince1970: 1_000)), context: ctx)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try String(contentsOf: url, encoding: .utf8) == "abîmé")
        #expect(h.ticket(for: abimee, context: ctx) == nil)
    }

    @Test func photoPlusAncienneSInsereASaPlace() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        try remplir(h, [1_000, 3_000], ctx)
        let milieu = try h.add(photoMini(2_000, canonMini(2)), context: ctx)
        #expect(milieu.listing.entries.map(\.timestamp) == [1_000, 2_000, 3_000])
        // Même résultat qu'un ordre d'arrivée différent.
        let autre = DossierTemporaire(); defer { autre.supprimer() }
        let h2 = HistoryStore(root: autre.url)
        try h2.add(photoMini(2_000, canonMini(2)), context: ctx)
        try h2.add(photoMini(3_000, canonMini(min(3, 1 + 1))), context: ctx)
        try h2.add(photoMini(1_000, canonMini(1)), context: ctx)
        #expect(h2.refresh(ctx).entries.map(\.timestamp) == [1_000, 2_000, 3_000])
    }

    @Test func suppressionMetLIndexAJour() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        try remplir(h, [1_000, 2_000, 3_000], ctx)
        let s = Snapshot(date: Date(timeIntervalSince1970: 2_000))
        let listing = try h.delete(s, context: ctx)
        #expect(listing.entries.map(\.timestamp) == [1_000, 3_000])
        #expect(h.photos.list().count == 2)
        #expect(!FileManager.default.fileExists(atPath: h.photos.directory.appending(path: s.fileName).path))
        // L'index sur disque est à jour (relu sans recalcul).
        #expect(try JSONDecoder().decode(HistoryIndex.self, from: Data(contentsOf: h.indexURL)).entries.map(\.timestamp) == [1_000, 3_000])
        #expect(throws: HistoryStore.HistoryError.cannotDelete) { try h.delete(s, context: ctx) }
    }

    @Test func capCalculeALaDateDeLaPhoto() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        let texte = photoMini(1_000, canonMini(1, timer: "500"))
        let export = try VillageExport.parse(texte)
        let plan = makePlan(for: Village(export: export, reference: Mini.reference), reference: Mini.reference,
                            advice: AdviceData(), profile: Profile(), now: export.date, boosts: export.boosts,
                            assistants: Assistants(export: export, reference: Mini.reference))
        let cap = try #require(plan.cap)
        let resume = try #require(h.add(texte, context: ctx).listing.entries.first)
        #expect(resume.cap == Date(timeIntervalSince1970: cap.timeIntervalSince1970.rounded(.down)))
        #expect(resume.cap! >= Date(timeIntervalSince1970: 1_500))
    }

    @Test func ticketCompareALaPhotoLisiblePrecedente() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        try h.add(photoMini(1_000, canonMini(1, timer: "50")), context: ctx)
        try h.add(photoMini(2_000, canonMini(2, timer: "5000")), context: ctx)
        let premiere = Snapshot(date: Date(timeIntervalSince1970: 1_000))
        let seconde = Snapshot(date: Date(timeIntervalSince1970: 2_000))
        #expect(h.ticket(for: premiere, context: ctx) == nil)
        let t = try #require(h.ticket(for: seconde, context: ctx))
        #expect(t.finished.map(\.count) == [1])
        #expect(t.capShift != nil)
        #expect(t.totalChange != nil)
        #expect(h.difference(from: premiere, to: seconde, context: ctx) == t)
    }

    // MARK: - Corrections de relecture

    func refFusion() -> ReferenceData {
        ReferenceData(items: [
            Mini.item(Mini.th, "buildings", .economy, counts: [0, 1, 1, 1], max: [0, 1, 2, 3], weights: [0, 100, 200]),
            Mini.item(1000008, "buildings", .defenses, counts: [0, 1, 4, 4], max: [0, 1, 2, 3], weights: [10, 20, 30]),
            Mini.item(1000085, "buildings", .defenses, counts: [0, 0, 0, 1], max: [0, 0, 0, 2], weights: [40, 50],
                      mergedFrom: [Requirement(itemID: 1000008, level: 3), Requirement(itemID: 1000008, level: 3)]),
        ], maxTownHall: 3)
    }

    @Test func fusionNInventePasUneAmeliorationLancee() throws {
        let ricochet = ##",{"data":1000085,"lvl":1}"##
        let d = try diffMini(photoMini(1_000, canonMini(3, cnt: 3) + "," + canonMini(2, timer: "500")),
                             photoMini(2_000, canonMini(3) + "," + canonMini(2, timer: "400") + ricochet), refFusion())
        #expect(d.started.isEmpty)
        #expect(d.finished.isEmpty)
    }

    @Test func fusionNeMasquePasUnVraiTermine() throws {
        let ricochet = ##",{"data":1000085,"lvl":1}"##
        // Le canon 2 en cours finit (niveau 3), deux canons au repos sont consommés par la fusion.
        let d = try diffMini(photoMini(1_000, canonMini(3, cnt: 2) + "," + canonMini(2, timer: "500")),
                             photoMini(2_000, canonMini(3) + ricochet), refFusion())
        #expect(d.finished == [PhotoDiff.ItemCount(itemID: 1000008, count: 1)])
        #expect(d.started.isEmpty)
    }

    @Test func photoDevenueIllisibleApresIndexationEstSignalee() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        try remplir(h, [1_000, 2_000], ctx)
        let s = Snapshot(date: Date(timeIntervalSince1970: 2_000))
        let url = h.photos.directory.appending(path: s.fileName)
        try Data("abîmé".utf8).write(to: url)
        let listing = h.refresh(ctx)
        #expect(listing.unreadable == [s])
        #expect(listing.entries.map(\.timestamp) == [1_000])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func versionDuCalculDansLaCleEtResumesPerimesRecalcules() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let h = HistoryStore(root: dossier.url), ctx = ctxMini()
        #expect(ctx.key.hasPrefix("calcul\(HistoryContext.calculationVersion)|"))
        try remplir(h, [1_000], ctx)
        let bon = h.refresh(ctx)
        var index = try JSONDecoder().decode(HistoryIndex.self, from: Data(contentsOf: h.indexURL))
        index.key = index.key.replacingOccurrences(of: "calcul\(HistoryContext.calculationVersion)|", with: "calcul0|")
        try JSONEncoder().encode(index).write(to: h.indexURL)
        #expect(h.refresh(ctx) == bon)
        #expect(try JSONDecoder().decode(HistoryIndex.self, from: Data(contentsOf: h.indexURL)).key == ctx.key)
    }
}
