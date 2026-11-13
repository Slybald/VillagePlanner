import Foundation
import Testing
@testable import ChantierKit

// Historique du joueur (T30) : chaque lecture est gardée avec sa date, le fichier abîmé est toléré, rien n'est écrit
// hors d'un dossier temporaire. Le tag est le tag factice #2PP.

@Suite struct HistoriqueJoueurTests {
    static func profil(_ trophees: Int, dons: Int = 100, guerre: Int = 50) -> ProfilJoueur {
        ProfilJoueur(tag: "#2PP", name: "Essai", trophies: trophees, bestTrophies: trophees + 40, attackWins: 7, defenseWins: 2,
                     donations: dons, warStars: guerre, leagueTier: LigueJoueur(id: 1, name: "Or 2"),
                     achievements: [SuccesJoueur(name: "a", stars: 3), SuccesJoueur(name: "b", stars: 1)],
                     heroes: [HeroJoueur(name: "Barbarian King", equipment: [ItemJoueur(name: "Rage Vial")])],
                     heroEquipment: [ItemJoueur(name: "Rage Vial"), ItemJoueur(name: "Barbarian Puppet")])
    }
    static func t(_ s: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + s) }

    @Test func chaqueLectureEstGardeeAvecSaDate() throws {
        let d = DossierTemporaire(); defer { d.supprimer() }
        let h = HistoriqueJoueur(root: d.url)
        #expect(h.lectures().isEmpty)
        #expect(h.enregistrer(Self.profil(5000), le: Self.t(7200)))
        #expect(h.enregistrer(Self.profil(4900), le: Self.t(0)))                   // plus ancienne : s'insère à sa place
        let l = HistoriqueJoueur(root: d.url).lectures()                           // relue par un autre exemplaire
        #expect(l.map(\.date) == [Self.t(0), Self.t(7200)])
        #expect(l.last == LectureJoueur(date: Self.t(7200), trophees: 5000, record: 5040, ligue: "Or 2", victoiresAttaque: 7,
                                        victoiresDefense: 2, dons: 100, etoilesGuerre: 50, etoilesSucces: 4, succesTermines: 1))
    }

    @Test func memeSeconde_uneSeuleLecture_etSerie() {
        let d = DossierTemporaire(); defer { d.supprimer() }
        let h = HistoriqueJoueur(root: d.url)
        h.enregistrer(Self.profil(1), le: Self.t(0)); h.enregistrer(Self.profil(2), le: Self.t(0.4))
        h.enregistrer(ProfilJoueur(tag: "#2PP"), le: Self.t(3600)); h.enregistrer(Self.profil(3), le: Self.t(7200))
        let l = h.lectures()
        #expect(l.count == 3 && l[0].trophees == 2)
        let s = LectureJoueur.serie(l, \.trophees)                                  // la lecture sans trophées n'est pas un point
        #expect(s.map(\.valeur) == [2, 3] && s.map(\.date) == [Self.t(0.4), Self.t(7200)])
    }

    @Test func fichierAbime_misDeCote_pasEfface() throws {
        let d = DossierTemporaire(); defer { d.supprimer() }
        try FileManager.default.createDirectory(at: d.url, withIntermediateDirectories: true)
        let h = HistoriqueJoueur(root: d.url)
        try Data("{\"format\":1,\"lectures\":".utf8).write(to: h.url)
        #expect(h.lectures().isEmpty && h.equipes().isEmpty)
        #expect(h.enregistrer(Self.profil(10), le: Self.t(0)))
        #expect(h.lectures().count == 1)
        #expect(FileManager.default.fileExists(atPath: h.urlAbime.path))            // l'ancien contenu reste
    }

    @Test func uneLectureIllisible_ecarteeSansEmporterLesAutres() throws {
        let d = DossierTemporaire(); defer { d.supprimer() }
        try FileManager.default.createDirectory(at: d.url, withIntermediateDirectories: true)
        let h = HistoriqueJoueur(root: d.url)
        try Data(#"{"format":1,"lectures":[{"date":"hier"},{"date":1800000000,"trophees":42}],"equipes":"non"}"#.utf8).write(to: h.url)
        #expect(h.lectures().map(\.trophees) == [42])
        #expect(h.equipes().isEmpty)
        try Data(#"{"format":99,"lectures":[]}"#.utf8).write(to: h.url)              // autre version : tenu pour abîmé
        #expect(h.lectures().isEmpty)
    }

    @Test func racineIllisible_pasDeCrash_ecritureRefusee() {
        let h = HistoriqueJoueur(root: URL(filePath: "/proc/inexistant/chantier"))
        #expect(!h.enregistrer(Self.profil(1), le: Self.t(0)))
        #expect(h.lectures().isEmpty)
    }

    @Test func equipements_relusParLaReference_equipeEstPossede() throws {
        let d = DossierTemporaire(); defer { d.supprimer() }
        let h = HistoriqueJoueur(root: d.url)
        #expect(h.equipements(reference: Réel.reference) == nil)                    // avant toute lecture : rien ne change
        h.enregistrer(Self.profil(1), le: Self.t(0))
        let e = try #require(h.equipements(reference: Réel.reference))
        let id = { (n: String) in Réel.reference.items.first { $0.names["en"] == n }!.id }
        #expect(e.equipes == [id("Rage Vial")] && e.possedes == [id("Rage Vial"), id("Barbarian Puppet")])
        #expect(h.equipes() == [HerosEquipe(heros: "Barbarian King", equipements: ["Rage Vial"])])
    }

    @Test func lectureSansEquipement_viderLaListe() {
        let d = DossierTemporaire(); defer { d.supprimer() }
        let h = HistoriqueJoueur(root: d.url)
        h.enregistrer(Self.profil(1), le: Self.t(0))
        h.enregistrer(ProfilJoueur(tag: "#2PP", trophies: 3), le: Self.t(3600))
        #expect(h.equipements(reference: Réel.reference) == nil)                    // l'API ne donne plus rien : retour à la règle V4
        #expect(h.lectures().count == 2)
    }
}
