import Foundation
import Testing
@testable import ChantierKit

// T25 : la chronologie du widget est une fonction pure. Une entrée par fin de minuteur, « photo à refaire » après le dernier.

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func h(_ heures: Double) -> Date { t0.addingTimeInterval(heures * 3600) }

private func poste(_ genre: WorkerKind = .builder, _ numero: Int, fin: Date?, nom: String = "Canon", niveau: Int = 5) -> WidgetEtat.Poste {
    WidgetEtat.Poste(genre: genre, numero: numero, imageLibre: "1000015_5.png",
                     travail: fin.map { WidgetEtat.Travail(nom: nom, niveau: niveau, fin: $0, image: "1000008_\(niveau).png") })
}

private func lignes(_ entree: WidgetEntree) -> [WidgetLigne] {
    guard case .postes(let l) = entree.contenu else { Issue.record("pas de postes : \(entree.contenu)"); return [] }
    return l
}

@Suite struct WidgetChronologieTests {
    private let etat = WidgetEtat(photo: t0, postes: [
        poste(.builder, 0, fin: h(2)), poste(.builder, 1, fin: h(5)), poste(.builder, 2, fin: h(9)),
        poste(.laboratory, 0, fin: nil),
    ])

    @Test func sansPhoto_leWidgetInviteAOuvrirLApp() {
        let e = WidgetChronologie.entrees(etat: nil, maintenant: h(1))
        #expect(e == [WidgetEntree(date: h(1), contenu: .ouvrirApp)])
    }

    @Test func uneEntreeParFinDeMinuteur_etPhotoARefaireALaFinDuDernier() {
        let e = WidgetChronologie.entrees(etat: etat, maintenant: h(1))
        #expect(e.map(\.date) == [h(1), h(2), h(5), h(9)])
        #expect(lignes(e[0]).libres.map(\.titre) == ["Labo"])
        #expect(lignes(e[1]).libres.map(\.titre) == ["Ouvrier 1", "Labo"])
        #expect(lignes(e[2]).libres.map(\.titre) == ["Ouvrier 1", "Ouvrier 2", "Labo"])
        #expect(e[3].contenu == .photoARefaire)
    }

    @Test func leProchainPosteLibreEstCeluiQuiFinitLePremier() {
        let e = WidgetChronologie.entrees(etat: etat, maintenant: h(1))
        #expect(lignes(e[0]).prochain?.titre == "Ouvrier 1")
        #expect(lignes(e[1]).prochain?.titre == "Ouvrier 2")      // le 1er est libre, le suivant prend la place
    }

    @Test func aLInstantExactDeLaFin_lePosteEstLibre_etLeCompteAReboursNeDepasseJamaisZero() {
        let e = WidgetChronologie.entrees(etat: etat, maintenant: h(1))
        #expect(lignes(e[1]).first { $0.titre == "Ouvrier 1" }?.travail == nil)
        // Aucune entrée ne porte un minuteur déjà fini : le texte animé ne compte jamais au-delà de zéro.
        for entree in e {
            guard case .postes(let l) = entree.contenu else { continue }
            #expect(l.allSatisfy { $0.travail.map { $0.fin > entree.date } ?? true })
        }
    }

    @Test func unMinuteurDejaFiniALInstantDuCalcul_laisseSonPosteLibre() {
        let e = WidgetChronologie.entrees(etat: etat, maintenant: h(3))
        #expect(e.map(\.date) == [h(3), h(5), h(9)])
        #expect(lignes(e[0]).libres.map(\.titre) == ["Ouvrier 1", "Labo"])
    }

    @Test func deuxFinsALaMemeSeconde_uneSeuleEntree() {
        let deux = WidgetEtat(photo: t0, postes: [poste(.builder, 0, fin: h(2)), poste(.builder, 1, fin: h(2)), poste(.builder, 2, fin: h(4))])
        let e = WidgetChronologie.entrees(etat: deux, maintenant: h(1))
        #expect(e.map(\.date) == [h(1), h(2), h(4)])
        #expect(lignes(e[1]).libres.count == 2)
    }

    @Test func apresLeDernierMinuteur_photoARefaire() {
        #expect(WidgetChronologie.entrees(etat: etat, maintenant: h(9)) == [WidgetEntree(date: h(9), contenu: .photoARefaire)])
        #expect(WidgetChronologie.entrees(etat: etat, maintenant: h(300)) == [WidgetEntree(date: h(300), contenu: .photoARefaire)])
    }

    @Test func photoSansAucunMinuteur_toutEstLibrePendantUnJour_puisPhotoARefaire() {
        let vide = WidgetEtat(photo: t0, postes: [poste(.builder, 0, fin: nil), poste(.builder, 1, fin: nil)])
        let e = WidgetChronologie.entrees(etat: vide, maintenant: h(1))
        #expect(e.map(\.date) == [h(1), h(24)])
        #expect(lignes(e[0]).libres.count == 2)
        #expect(e[1].contenu == .photoARefaire)
        #expect(WidgetChronologie.entrees(etat: vide, maintenant: h(25)).first?.contenu == .photoARefaire)
    }

    @Test func lesPostesGardentLImageDeLElementEnCours_puisCelleDuPosteQuandIlSeLibere() {
        let e = WidgetChronologie.entrees(etat: etat, maintenant: h(1))
        #expect(lignes(e[0]).first?.image == "1000008_5.png")
        #expect(lignes(e[1]).first?.image == "1000015_5.png")
    }

    @Test func compteAReboursExactSousUnJour_enJoursAuDela() {
        #expect(WidgetChronologie.compteAReboursExact(fin: h(23.9), depuis: t0))
        #expect(!WidgetChronologie.compteAReboursExact(fin: h(24), depuis: t0))
        #expect(!WidgetChronologie.compteAReboursExact(fin: h(100), depuis: t0))
    }

    @Test func lEtatSeRelitTelQuilEstEcrit_unFichierAbimeOuAbsentDonneNil() throws {
        let racine = FileManager.default.temporaryDirectory.appending(path: "chantier-widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: racine) }
        #expect(WidgetEtat.lire(dans: racine) == nil)
        #expect(etat.ecrire(dans: racine))
        #expect(WidgetEtat.lire(dans: racine) == etat)
        try "{\"photo\":".write(to: WidgetEtat.fichier(dans: racine), atomically: true, encoding: .utf8)
        #expect(WidgetEtat.lire(dans: racine) == nil)
        #expect(etat.ecrire(dans: racine))
        WidgetEtat.effacer(dans: racine)
        #expect(WidgetEtat.lire(dans: racine) == nil)
    }

    @Test func autreFormat_neSeLitPas() throws {
        let racine = FileManager.default.temporaryDirectory.appending(path: "chantier-widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: racine) }
        var futur = etat
        futur.format = WidgetEtat.format + 1
        #expect(futur.ecrire(dans: racine))
        #expect(WidgetEtat.lire(dans: racine) == nil)
    }
}

// Le widget n'appelle aucun réseau : ses sources ne contiennent aucun appel réseau. Le contrôle est éprouvé sur un faux défaut.
@Suite struct WidgetSansReseauTests {
    static let interdits = ["URLSession", "URLRequest", "URL(string", "http://", "https://", "NWConnection", "CFNetwork"]

    static func appelsReseau(dans texte: String) -> [String] { interdits.filter { texte.contains($0) } }

    @Test func leControleTrouveUnDefautInjecte() {
        #expect(Self.appelsReseau(dans: "let (d, _) = try await URLSession.shared.data(from: u)") == ["URLSession"])
        #expect(Self.appelsReseau(dans: "Text(\"bonjour\")").isEmpty)
    }

    @Test func lesSourcesDuWidgetNAppellentAucunReseau() throws {
        let depot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dossiers = [depot.appending(path: "Widget"), depot.appending(path: "Packages/ChantierKit/Sources/ChantierKit/Widget")]
        var lus = 0
        for dossier in dossiers {
            let fichiers = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path))?.filter { $0.hasSuffix(".swift") } ?? []
            for nom in fichiers {
                let texte = try String(contentsOf: dossier.appending(path: nom), encoding: .utf8)
                #expect(Self.appelsReseau(dans: texte).isEmpty, "\(nom) appelle le réseau")
                lus += 1
            }
        }
        #expect(lus >= 3, "les sources du widget n'ont pas été trouvées")
    }
}
