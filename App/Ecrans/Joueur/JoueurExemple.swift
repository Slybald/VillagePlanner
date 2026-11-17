import VillagePlannerKit
import Foundation

#if DEBUG
/// Captures seulement (`-joueur-historique-exemple 1`) : un faux joueur `#2PP` et quatorze jours de lectures inventées,
/// écrits dans le dossier jetable des photos d'exemple. Rien ne part sur le réseau, aucune clé.
enum JoueurExemple {
    static func ecrire(dans historique: HistoriqueJoueur) {
        let debut = Date(timeIntervalSince1970: 1_794_000_000)
        let trophees = [4_812, 4_870, 4_835, 4_902, 4_951, 4_918, 4_980, 5_034, 5_007, 5_061, 5_112, 5_090, 5_143, 5_168]
        for (i, t) in trophees.enumerated() {
            historique.enregistrer(profil(trophees: t, guerre: 612 + i * 3 + i / 4, dons: 18_400 + i * 130), le: debut.addingTimeInterval(Double(i) * 86_400))
        }
    }

    static func profil(trophees: Int, guerre: Int, dons: Int) -> ProfilJoueur {
        ProfilJoueur(
            tag: "#2PP", name: "Exemple", expLevel: 214, townHallLevel: 16, trophies: trophees, bestTrophies: 5_231,
            attackWins: 3_412, defenseWins: 311, donations: dons, donationsReceived: 9_800, warStars: guerre,
            leagueTier: LigueJoueur(id: 105_000_021, name: "Champion 2"),
            achievements: (0..<40).map { SuccesJoueur(name: "Succès \($0)", stars: $0 < 22 ? 3 : $0 % 3) },
            heroes: [
                HeroJoueur(name: "Barbarian King", level: 95, maxLevel: 100,
                           equipment: [ItemJoueur(name: "Giant Gauntlet", level: 18), ItemJoueur(name: "Rage Vial", level: 16)]),
                HeroJoueur(name: "Archer Queen", level: 98, maxLevel: 100,
                           equipment: [ItemJoueur(name: "Archer Puppet", level: 14), ItemJoueur(name: "Frozen Arrow", level: 12)]),
                HeroJoueur(name: "Grand Warden", level: 72, maxLevel: 75,
                           equipment: [ItemJoueur(name: "Eternal Tome", level: 15), ItemJoueur(name: "Healing Tome", level: 11)]),
                HeroJoueur(name: "Royal Champion", level: 48, maxLevel: 50, equipment: [ItemJoueur(name: "Royal Gem", level: 10)]),
            ],
            heroEquipment: ["Giant Gauntlet", "Rage Vial", "Archer Puppet", "Frozen Arrow", "Eternal Tome", "Healing Tome", "Royal Gem",
                            "Barbarian Puppet", "Earthquake Boots"].map { ItemJoueur(name: $0, level: 5) })
    }
}
#endif
