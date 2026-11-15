import Foundation
import Testing
@testable import ChantierKit

// Action « Importer un export » (T27) : le chemin d'import est celui de l'app ; aucun texte ne le fait planter.

@Suite struct ImportTexteTests {
    /// Un import avec un compteur d'`actualiser` (widget, notifications) ; dossier jetable.
    private func importer(_ texte: String, dans dossier: DossierTemporaire, compteur: Compteur = Compteur()) -> (ResultatImport, Int) {
        let r = ResultatImport.importer(texte, dans: HistoryStore(root: dossier.url), context: ctxMini()) { _, _ in compteur.n += 1 }
        return (r, compteur.n)
    }
    final class Compteur: @unchecked Sendable { var n = 0 }

    private let fuseau = TimeZone(identifier: "Europe/Paris")!
    private let cap = Date(timeIntervalSince1970: 1_773_500_000)   // 14 mars 2026

    @Test func exportValide_estEnregistre_etActualiseUneFois() throws {
        let d = DossierTemporaire(); defer { d.supprimer() }
        let (r, n) = importer(exportMinimal(1_794_414_482), dans: d)
        guard case .enregistree(let photo, true) = r else { Issue.record("\(r)"); return }
        #expect(n == 1)
        #expect(HistoryStore(root: d.url).photos.list() == [photo])
    }

    @Test func memeExportDeuxFois_dejaPresente_sansDoublon() throws {
        let d = DossierTemporaire(); defer { d.supprimer() }
        let c = Compteur()
        _ = importer(exportMinimal(1_794_414_482), dans: d, compteur: c)
        let (r, _) = importer(exportMinimal(1_794_414_482), dans: d, compteur: c)
        #expect(r == .dejaPresente)
        #expect(HistoryStore(root: d.url).photos.list().count == 1)
        #expect(r.phrase(cap: cap, now: cap, timeZone: fuseau) == "Cet export est déjà dans tes photos")
    }

    @Test func photoPlusAncienne_estGardee_maisPasAffichee() throws {
        let d = DossierTemporaire(); defer { d.supprimer() }
        _ = importer(exportMinimal(1_794_414_482), dans: d)
        let (r, _) = importer(exportMinimal(1_794_000_000), dans: d)
        guard case .enregistree(_, false) = r else { Issue.record("\(r)"); return }
        #expect(HistoryStore(root: d.url).photos.list().count == 2)
    }

    @Test func nImporteQuelTexte_neChangeRien_neActualisePas_etNePlantePas() throws {
        let d = DossierTemporaire(); defer { d.supprimer() }
        let c = Compteur()
        let cinqMo = String(repeating: "a", count: 5 * 1024 * 1024)
        let binaire = String(decoding: (0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) }, as: UTF8.self) + "\u{0}\u{FFFD}"
        let textes = ["", "   \n", "bonjour", "{\"a\":1}", "[]", "null", "{\"timestamp\":", "{\"timestamp\":1,\"buildings\":\"x\"}",
                      cinqMo, "{\"x\":\"\(cinqMo)\"}", binaire, try Fixtures.texte("abime-02-tronque"), try Fixtures.texte("abime-08-5mo")]
        for t in textes {
            let (r, n) = importer(t, dans: d, compteur: c)
            guard case .refuse = r else { Issue.record("accepté : \(t.prefix(20))"); continue }
            #expect(n == 0)
            #expect(!r.phrase(cap: nil, now: cap, timeZone: fuseau).isEmpty)
        }
        #expect(HistoryStore(root: d.url).photos.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: d.url.path))   // même le dossier n'est pas créé
    }

    @Test func phrases_enFrancais() throws {
        let photo = Snapshot(date: Date(timeIntervalSince1970: 1_794_414_482))
        #expect(ResultatImport.enregistree(photo, plusRecente: true).phrase(cap: cap, now: cap, timeZone: fuseau)
                == "Photo enregistrée, cap au 14\u{00A0}mars")
        #expect(ResultatImport.enregistree(photo, plusRecente: true).phrase(cap: nil, now: cap, timeZone: fuseau) == "Photo enregistrée")
        #expect(ResultatImport.refuse(.invalid(.notJSON)).phrase(cap: nil, now: cap, timeZone: fuseau) == "Ce n'est pas un export")
        #expect(ResultatImport.refuse(.invalid(.empty)).phrase(cap: nil, now: cap, timeZone: fuseau) == "Le texte est vide")
    }
}
