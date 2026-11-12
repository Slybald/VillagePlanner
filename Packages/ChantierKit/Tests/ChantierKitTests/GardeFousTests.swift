import Foundation
import Testing
@testable import ChantierKit

// Les garde-fous du conseiller (T20, PLAN §6.2) : G1 (aucun chiffre inventé), G2 (aucun identifiant ni nom inventé),
// G3 (tout échec montre la consigne du moteur). Les résumés de ces tests sont écrits à la main, petits, pour que
// chaque nombre légitime soit visible ; `ConseillerTests` joue les mêmes garde-fous sur le résumé d'un vrai village.

private let reference = Réel.reference
private let espaceFine = "\u{202F}", insecable = "\u{00A0}"

/// L'identifiant d'un élément de la référence réelle, par son nom français.
private func id(_ nom: String) -> Int { reference.items.first { $0.name == nom }!.id }

private func resume(_ texte: String, _ ids: [Int] = []) -> ResumeConseil { ResumeConseil(texte: texte, identifiants: Set(ids)) }

private func verdict(_ texte: String, dans resume: ResumeConseil, ids: [Int] = []) -> Verdict {
    GardeFous.verifier(ReponseConseil(texte: texte, ids: ids), resume: resume, reference: reference)
}

private func acceptee(_ texte: String, dans resume: ResumeConseil, ids: [Int] = []) -> Bool {
    if case .acceptee = verdict(texte, dans: resume, ids: ids) { true } else { false }
}

/// Le résumé de base des tests G1 : un lancement demain 14 h de l'Arc-X 11 pour 18 M d'or, durée 3 j 4 h, un cap le 14 mars.
private let base = resume("""
    Hôtel de ville 16. Photo : le 11 novembre à 17 h 28. Maintenant : le 12 novembre à 9 h 30.
    Cap : hôtel de ville 16 terminé le 14 mars à 9 h, hors murs et équipements.
    Avancement : total 64 %, Défenses 71 %.
    Profil : orientation attaque, limite de héros en amélioration : 1, heures sans jeu de 23 h à 7 h, ouvriers : 2.
    - (id \(id("Arc-X"))) Arc-X 11 (niveau 10 → 11) : lancement demain 14 h, coût 18 M d'or, durée 3 j 4 h, ouvrier. Raison : défense clé.
    Ressources à réunir : 18 M d'or demain 14 h ; rythme 1,5 M d'or par jour.
    """, [id("Arc-X")])

// MARK: - G1 : la table des formes reconnues

@Suite struct GardeFousTests {

    /// Chaque ligne : une écriture, et ce qu'elle veut dire. C'est la liste des formes reconnues (PLAN §6.2).
    static let formes: [(String, [Valeur])] = [
        // montants
        ("18 M", [.nombre("18000000")]), ("18M", [.nombre("18000000")]), ("18 millions", [.nombre("18000000")]),
        ("18 000 000", [.nombre("18000000")]), ("18\(espaceFine)000\(espaceFine)000", [.nombre("18000000")]),
        ("18\(insecable)000\(insecable)000", [.nombre("18000000")]), ("18000000", [.nombre("18000000")]),
        ("dix-huit millions", [.nombre("18000000")]), ("1,5 M", [.nombre("1500000")]), ("1,5\(insecable)M", [.nombre("1500000")]),
        ("1 500 000", [.nombre("1500000")]), ("un million et demi", [.nombre("1000000"), .vague("demi")]),
        ("1,64 Md", [.nombre("1640000000")]), ("2 milliards", [.nombre("2000000000")]), ("512 560", [.nombre("512560")]),
        ("18 k", [.nombre("18000")]), ("3,5", [.nombre("3.5")]), ("0", [.nombre("0")]),
        // nombres en lettres
        ("un ouvrier", [.nombre("1")]), ("une fois", [.nombre("1")]), ("deux ouvriers", [.nombre("2")]), ("trois niveaux", [.nombre("3")]),
        ("quatre", [.nombre("4")]), ("cinq", [.nombre("5")]), ("six", [.nombre("6")]), ("sept", [.nombre("7")]), ("huit", [.nombre("8")]),
        ("neuf", [.nombre("9")]), ("dix", [.nombre("10")]), ("onze", [.nombre("11")]), ("douze", [.nombre("12")]),
        ("quinze", [.nombre("15")]), ("dix-sept", [.nombre("17")]), ("vingt et un", [.nombre("21")]), ("vingt-deux", [.nombre("22")]),
        ("soixante-dix", [.nombre("70")]), ("soixante-dix-sept", [.nombre("77")]), ("quatre-vingts", [.nombre("80")]),
        ("quatre-vingt-dix-huit", [.nombre("98")]), ("deux cents", [.nombre("200")]), ("deux cent trois", [.nombre("203")]),
        ("mille", [.nombre("1000")]), ("deux mille deux cents", [.nombre("2200")]), ("deux trois", [.nombre("2"), .nombre("3")]),
        // « un » et « une » sont des articles sauf devant une unité
        ("lance un Arc-X", []), ("une amélioration", []), ("l'un des deux", [.nombre("2")]), ("aucun", []),
        // heures et durées
        ("7 h", [.duree("7", .heure)]), ("7h", [.duree("7", .heure)]), ("7 heures", [.duree("7", .heure)]),
        ("7 h 30", [.horaire(heure: 7, minute: 30)]), ("7h30", [.horaire(heure: 7, minute: 30)]), ("7:30", [.horaire(heure: 7, minute: 30)]),
        ("7\(insecable)h\(insecable)30", [.horaire(heure: 7, minute: 30)]), ("14 h 05", [.horaire(heure: 14, minute: 5)]),
        ("7 heures et 30 minutes", [.horaire(heure: 7, minute: 30)]), ("5 h 20 min", [.horaire(heure: 5, minute: 20)]),
        ("1,5 h", [.duree("1.5", .heure)]), ("20 min", [.duree("20", .minute)]), ("20 minutes", [.duree("20", .minute)]),
        ("3 j 4 h", [.duree("3", .jour), .duree("4", .heure)]), ("3 jours", [.duree("3", .jour)]), ("un jour", [.duree("1", .jour)]),
        ("2 semaines", [.duree("2", .semaine)]), ("deux mois", [.duree("2", .mois)]), ("1 an", [.duree("1", .an)]),
        ("demain 14 h", [.duree("14", .heure)]), ("jeudi 9 h", [.jourSemaine(4), .duree("9", .heure)]),
        // dates : le jour n'est pas un nombre à part
        ("le 9 décembre", [.date(jour: 9, mois: 12)]), ("9 décembre", [.date(jour: 9, mois: 12)]), ("le 14 mars", [.date(jour: 14, mois: 3)]),
        ("1er mars", [.date(jour: 1, mois: 3)]), ("le\(insecable)14\(insecable)mars à\(insecable)9\(insecable)h", [.date(jour: 14, mois: 3), .duree("9", .heure)]),
        ("le 14 mars 2027", [.date(jour: 14, mois: 3), .nombre("2027")]), ("le 31 août", [.date(jour: 31, mois: 8)]),
        // niveaux
        ("niveau 9", [.nombre("9")]), ("niveau 8 → 9", [.nombre("8"), .nombre("9")]), ("de 8 à 9", [.nombre("8"), .nombre("9")]),
        ("Arc-X 11", [.nombre("11")]), ("HDV 16", [.nombre("16")]), ("(×2)", [.nombre("2")]), ("canon 5 (×2)", [.nombre("5"), .nombre("2")]),
        // pourcentages
        ("64 %", [.pourcent("64")]), ("64\(espaceFine)%", [.pourcent("64")]), ("64%", [.pourcent("64")]), ("64 pour cent", [.pourcent("64")]),
        ("−20 %", [.pourcent("20")]),
        // un rang n'est pas une donnée
        ("la 2e amélioration", []), ("la deuxième amélioration", []), ("la première", []),
        // ce qui cache un nombre ne peut pas être vérifié
        ("une dizaine de jours", [.vague("dizaine")]), ("le double", [.vague("double")]),
        ("la moitié", [.vague("moitie")]), ("un quart", [.vague("quart")]), ("des milliers", [.vague("milliers")]),
    ]

    @Test func G1_tableDesFormesReconnues() {
        for (ecriture, attendu) in Self.formes {
            let lu = Nombres.lire(ecriture).map(\.valeur)
            // L'ordre de lecture n'est pas celui du texte pour les mots (jours, vagues) : on compare en ensembles et en nombre.
            #expect(Set(lu) == Set(attendu) && lu.count == attendu.count, "« \(ecriture) » lu \(lu), attendu \(attendu)")
        }
    }

    @Test func G1_ecrituresEquivalentes_donnentLaMemeValeur() {
        let ecritures = ["18 M", "18M", "18 millions", "18 000 000", "18\(espaceFine)000\(espaceFine)000", "18\(insecable)000\(insecable)000",
                         "dix-huit millions", "18000000", "18 000 k"]
        #expect(Set(ecritures.flatMap { Nombres.lire($0).map(\.valeur) }) == [.nombre("18000000")])
    }

    @Test func G1_uneEcritureDifferente_neDonnePasLaMemeValeur() {
        #expect(Nombres.lire("18 M") != Nombres.lire("19 M"))
        #expect(Nombres.lire("7 h") != Nombres.lire("7 h 30"))
        #expect(Nombres.lire("le 9 décembre") != Nombres.lire("le 19 décembre"))
        #expect(Nombres.lire("64 %") != Nombres.lire("64"))
        #expect(Nombres.lire("1,5 M") != Nombres.lire("15 M"))
    }

    // MARK: - G1 : un nombre absent du résumé fait rejeter la réponse

    @Test func G1_nombreAbsentDuResume_faitRejeterLaReponse() {
        #expect(!acceptee("Demain 14 h, lance Arc-X 11 : prépare 19 M d'or.", dans: base))
        #expect(verdict("Demain 14 h, lance Arc-X 11 : prépare 19 M d'or.", dans: base) == .refusee(.nombre("19 m")))
        #expect(acceptee("Demain 14 h, lance Arc-X 11 : prépare 18 M d'or.", dans: base))
    }

    @Test func G1_chaqueEcritureDUnNombreDuResume_estAcceptee() {
        for ecriture in ["18 M d'or", "18 000 000 d'or", "18\(espaceFine)000\(espaceFine)000 d'or", "18\(insecable)000\(insecable)000 d'or",
                         "18 millions d'or", "dix-huit millions d'or", "18M d'or"] {
            #expect(acceptee("Prépare \(ecriture).", dans: base), "\(ecriture)")
        }
    }

    @Test func G1_nombreInventeDeguise_estRejete() {
        // Un nombre calculé, arrondi, converti ou écrit en lettres hors du résumé : chacun est absent.
        for texte in ["Il reste 76 heures.", "Prépare dix-neuf millions d'or.", "Il faut une dizaine de jours.", "Ça prend le double de temps.",
                      "Prépare 18,5 M d'or.", "Prépare dix-huit millions et demi d'or.", "Compte quinze jours.", "Prépare 17 999 999 d'or.",
                      "Il reste cinq jours.", "Lance-le à 14 h 30.", "Termine le 15 mars.", "Compte vingt-cinq pour cent de plus.",
                      "Arc-X 12 ensuite.", "Il y a quatre ouvriers.", "Dans 2 jours.", "Rythme de 15 M d'or par jour."] {
            #expect(!acceptee(texte, dans: base), "« \(texte) » aurait dû être rejeté")
        }
    }

    @Test func G1_pasDeFauxPositif_surLesFormesDuResume() {
        for texte in ["Demain 14 h, lance Arc-X 11.", "Prépare 18 M d'or, durée 3 j 4 h.", "Ton cap est le 14 mars à 9 h.",
                      "Avancement total à 64 %, défenses à 71 %.", "Tu as deux ouvriers.", "Passe de niveau 10 à niveau 11.",
                      "Rythme de 1,5 M d'or par jour.", "Rythme de 1 500 000 d'or par jour.", "Une seule limite de héros : 1.",
                      "Tes heures sans jeu vont de 23 h à 7 h.", "La photo date du 11 novembre à 17 h 28."] {
            // « un ouvrier » demande « 1 » : le résumé le contient (limite de héros : 1), l'article « une » est ignoré.
            #expect(acceptee(texte, dans: base), "« \(texte) » aurait dû être accepté : \(verdict(texte, dans: base))")
        }
    }

    @Test func G1_leJourDUneDate_n_estPasUnNombreAPart() {
        // Le résumé connaît le 9 décembre, pas le nombre 9 : « le 9 décembre » passe, « 9 ouvriers » non.
        let r = resume("Cap : le 9 décembre à 14 h.")
        #expect(acceptee("Ton cap est le 9 décembre.", dans: r))
        #expect(acceptee("Ton cap est le 9 décembre à 14 h.", dans: r))
        #expect(!acceptee("Ton cap est le 19 décembre.", dans: r))
        #expect(!acceptee("Ton cap est le 9 novembre.", dans: r))
        #expect(!acceptee("Il te faut 9 ouvriers.", dans: r))
        #expect(!acceptee("Ton cap est le 9.", dans: r))
    }

    @Test func G1_unEtUne_sontDesArticlesSaufDevantUneUnite() {
        let sansUn = resume("Lancement demain 14 h : Arc-X 11, deux ouvriers.")
        #expect(acceptee("Lance un Arc-X 11 demain 14 h.", dans: sansUn))
        #expect(!acceptee("Un ouvrier est libre.", dans: sansUn))
        #expect(!acceptee("Dans un jour.", dans: sansUn))
        #expect(acceptee("Deux ouvriers se libèrent.", dans: sansUn))
    }

    @Test func G1_nombresEnLettres_deUnADouze() {
        let mots = ["un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix", "onze", "douze"]
        for (i, mot) in mots.enumerated() {
            let n = i + 1
            #expect(acceptee("Tu as \(mot) ouvriers.", dans: resume("Ouvriers : \(n) ouvriers.")), "\(mot)")
            let autre = n == 12 ? 1 : n + 1
            #expect(!acceptee("Tu as \(mot) ouvriers.", dans: resume("Ouvriers : \(autre) ouvriers.")), "\(mot) contre \(autre)")
        }
    }

    @Test func G1_lesHeures_sontComparees_avecLeursMinutes() {
        #expect(acceptee("Lance à 7 h.", dans: resume("Lancement demain 7 h.")))
        #expect(!acceptee("Lance à 7 h 30.", dans: resume("Lancement demain 7 h.")))
        #expect(!acceptee("Lance à 7 h.", dans: resume("Lancement demain 7 h 30.")))
        #expect(acceptee("Lance à 7 h 30.", dans: resume("Lancement demain 7 h 30.")))
        #expect(acceptee("Lance à 7h30.", dans: resume("Lancement demain 7 h 30.")))
        #expect(acceptee("Lance à 7:30.", dans: resume("Lancement demain 7 h 30.")))
        #expect(acceptee("Compte 20 minutes.", dans: resume("Durée 5 h 20 min.")))
    }

    @Test func G1_lesJoursDeLaSemaine_sontVerifies() {
        #expect(acceptee("Lance jeudi 9 h.", dans: resume("Lancement jeudi 9 h.")))
        #expect(!acceptee("Lance vendredi 9 h.", dans: resume("Lancement jeudi 9 h.")))
    }

    @Test func G1_niveaux() {
        let r = resume("Arc-X 11 (niveau 10 → 11).")
        #expect(acceptee("Passe l'Arc-X du niveau 10 au niveau 11.", dans: r))
        #expect(acceptee("Arc-X 10 → 11.", dans: r))
        #expect(!acceptee("Passe l'Arc-X au niveau 12.", dans: r))
        #expect(!acceptee("Arc-X 9 → 10.", dans: r))
    }

    // MARK: - G2 : un identifiant ou un nom absent du résumé fait rejeter la réponse

    @Test func G2_identifiantAbsentDuResume_faitRejeterLaReponse() {
        let arc = id("Arc-X")
        #expect(acceptee("Lance Arc-X 11.", dans: base, ids: [arc]))
        #expect(verdict("Lance Arc-X 11.", dans: base, ids: [arc, id("Canon")]) == .refusee(.identifiant(id("Canon"))))
        #expect(verdict("Lance Arc-X 11.", dans: base, ids: [42]) == .refusee(.identifiant(42)))
        // Un identifiant qui existe dans la référence mais pas dans le résumé est rejeté aussi.
        let canon = id("Canon")
        #expect(verdict("Lance Arc-X 11.", dans: base, ids: [canon]) == .refusee(.identifiant(canon)))
        #expect(acceptee("Lance Arc-X 11.", dans: base, ids: []))
    }

    @Test func G2_nomAbsentDuResume_faitRejeterLaReponse() {
        #expect(verdict("Lance la Tour à bombes demain 14 h.", dans: base) == .refusee(.nom("tour a bombes")))
        #expect(verdict("Lance le Canon demain 14 h.", dans: base) == .refusee(.nom("canon")))
        #expect(verdict("Lance le Roi des barbares demain 14 h.", dans: base) == .refusee(.nom("roi des barbares")))
        #expect(acceptee("Lance l'Arc-X 11 demain 14 h.", dans: base))
        #expect(acceptee("Lance l'arc-x 11 demain 14 h.", dans: base))        // casse et accents libres
    }

    @Test func G2_leNomLePlusLongGagne() {
        let r = resume("Canon à ricochet 5 : lancement demain 14 h. (id \(id("Canon à ricochet")))", [id("Canon à ricochet")])
        #expect(acceptee("Lance le Canon à ricochet 5 demain 14 h.", dans: r))
        #expect(!acceptee("Lance le Canon 5 demain 14 h.", dans: r))             // « Canon » n'est pas « Canon à ricochet »
        let r2 = resume("Canon 5 : lancement demain 14 h.", [id("Canon")])
        #expect(!acceptee("Lance le Canon à ricochet 5 demain 14 h.", dans: r2))
    }

    @Test func G2_lePluriel_etLesMotsDansUnAutreMot() {
        let r = resume("Canon 5 : lancement demain 14 h.", [id("Canon")])
        #expect(acceptee("Lance les Canons 5 demain 14 h.", dans: r))
        #expect(acceptee("Lance le canon 5 demain 14 h, canonnier ou pas.", dans: r))    // « canonnier » n'est pas un nom du jeu
        #expect(!acceptee("Lance le Dragon 5 demain 14 h.", dans: r))
    }

    @Test func G2_lesNomsDuResumeSontLesNomsFrancaisDeLaReference() {
        // `ReferenceData.name(of:)` : le nom que l'écran affiche est celui que le garde-fou reconnaît.
        for nom in ["Arc-X", "Roi des barbares", "Tour à bombes", "Hôtel de ville", "Château de clan", "Cabane d'ouvrier"] {
            let i = id(nom)
            #expect(reference.name(of: i) == nom)
            #expect(GardeFous.nomsCites("Lance \(nom) demain.", reference: reference)[i] != nil, "\(nom)")
        }
    }

    // MARK: - Forme

    @Test func forme_troisPhrasesAuPlus_etPasDeTexteVide() {
        #expect(verdict("   ", dans: base) == .refusee(.vide))
        #expect(acceptee("Lance Arc-X 11. Prépare 18 M d'or. Demain 14 h.", dans: base))
        #expect(verdict("Lance Arc-X 11. Prépare 18 M d'or. Demain 14 h. Bonne chance !", dans: base) == .refusee(.trop(phrases: 4)))
        #expect(GardeFous.nombreDePhrases("Rythme de 1.5 M d'or par jour. Fini.") == 2)
        #expect(verdict(String(repeating: "Lance Arc-X 11 ", count: 40), dans: base) == .refusee(.trop(phrases: 1)))
    }

    // MARK: - G3 : tout échec montre la consigne du moteur, sans alerte

    @Test func G3_toutEchec_montreLaConsigneDuMoteur_sansAlerte() async throws {
        let moteur = "Demain 14 h, deux ouvriers se libèrent : lance Arc-X 11. Prépare 18 M d'or."
        let ok = Reponse.ok(Self.json("Demain 14 h, lance Arc-X 11 : prépare 18 M d'or.", [id("Arc-X")]))
        // Chaque ligne : la réponse du service (ou son absence), et pourquoi l'écran montre le moteur.
        let cas: [(String, String?, [Reponse])] = [
            ("pas de clé", nil, [ok]),
            ("clé refusée (401)", BancConseiller.cle, [.http(401)]),
            ("trop de requêtes (429 deux fois)", BancConseiller.cle, [.http(429, ["retry-after": "1"]), .http(429, ["retry-after": "1"])]),
            ("erreur du service (500)", BancConseiller.cle, [.http(500)]),
            ("hors ligne", BancConseiller.cle, [.panne(.notConnectedToInternet)]),
            ("délai dépassé", BancConseiller.cle, [.panne(.timedOut)]),
            ("refus du modèle", BancConseiller.cle, [.ok(nil, stop: "refusal", categorie: "cyber")]),
            ("hors schéma : pas du JSON", BancConseiller.cle, [.ok("pas du json")]),
            ("hors schéma : un champ manque", BancConseiller.cle, [.ok(#"{"texte":"Lance Arc-X 11."}"#)]),
            ("tronquée (max_tokens)", BancConseiller.cle, [.ok(Self.json("Lance", []), stop: "max_tokens")]),
            ("G1 : nombre inventé", BancConseiller.cle, [.ok(Self.json("Demain 14 h, lance Arc-X 11 : prépare 19 M d'or.", [id("Arc-X")]))]),
            ("G1 : nombre en lettres inventé", BancConseiller.cle, [.ok(Self.json("Prépare dix-neuf millions d'or.", []))]),
            ("G2 : identifiant inventé", BancConseiller.cle, [.ok(Self.json("Lance Arc-X 11.", [id("Canon")]))]),
            ("G2 : nom inventé", BancConseiller.cle, [.ok(Self.json("Lance la Tour à bombes demain 14 h.", []))]),
            ("trop long", BancConseiller.cle, [.ok(Self.json("Lance Arc-X 11. Prépare 18 M d'or. Demain 14 h. Courage.", []))]),
        ]
        for (nom, cle, reponses) in cas {
            let banc = BancConseiller(cle: cle, reponses: reponses)
            let issue = await banc.conseiller.obtenir(resume: base, cle: "k", reference: reference, now: BancConseiller.maintenant)
            #expect(!issue.estConseil, "\(nom) : un conseil a été montré")
            #expect(issue.texte(repli: moteur) == moteur, "\(nom) : l'écran ne montre pas la consigne du moteur")
        }
        // Et le cas de réussite : le conseil remplace le moteur.
        let banc = BancConseiller(cle: BancConseiller.cle, reponses: [ok])
        let issue = await banc.conseiller.obtenir(resume: base, cle: "k", reference: reference, now: BancConseiller.maintenant)
        #expect(issue == .conseil("Demain 14 h, lance Arc-X 11 : prépare 18 M d'or."))
        #expect(issue.texte(repli: moteur) != moteur)
    }

    @Test func G3_plafondAtteint_aucunAppel_laConsigneDuMoteurResteAffichee() async {
        var b = Budget()
        for _ in 0..<Budget.callsPerDay { b.recordCall(at: BancConseiller.maintenant, calendar: BancConseiller.calendrier) }
        let banc = BancConseiller(cle: BancConseiller.cle, budget: b, reponses: [.ok(Self.json("Lance Arc-X 11.", []))])
        let issue = await banc.conseiller.obtenir(resume: base, cle: "k", reference: reference, now: BancConseiller.maintenant)
        #expect(issue == .repli(.erreur(.budgetReached(.daily))))
        #expect(issue.texte(repli: "moteur") == "moteur")
        #expect(await banc.transport.requetes.isEmpty)
    }

    @Test func G3_leTrousseauFerme_laConsigneDuMoteurResteAffichee() async {
        let banc = BancConseiller(coffre: CoffreEnPanne(), reponses: [])
        let issue = await banc.conseiller.obtenir(resume: base, cle: "k", reference: reference, now: BancConseiller.maintenant)
        #expect(issue.texte(repli: "moteur") == "moteur")
        #expect(await banc.transport.requetes.isEmpty)
    }

    static func json(_ texte: String, _ ids: [Int]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: ["texte": texte, "ids": ids]), as: UTF8.self)
    }
}

// MARK: - BancConseiller des tests du conseiller (partagé avec ConseillerTests)

struct BancConseiller {
    static let cle = "cle-factice-TEST-0000-aaaa-bbbb-cccc-9876"
    static let calendrier: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()
    static let maintenant = Réel.village.date.addingTimeInterval(3600)

    let conseiller: Conseiller
    let transport: FauxTransport
    let store: PreferencesConseil

    init(cle: String? = BancConseiller.cle, coffre: (any SecretStore)? = nil, budget: Budget = Budget(), reponses: [Reponse]) {
        let defaults = UserDefaults(suiteName: "chantier-test-\(UUID().uuidString)")!
        let budgetStore = BudgetStore(defaults: defaults)
        budgetStore.save(budget)
        transport = FauxTransport(reponses)
        store = PreferencesConseil(defaults: defaults)
        let client = ClaudeClient(keys: coffre ?? MemorySecretStore(cle), budget: budgetStore, transport: transport,
                                  calendar: Self.calendrier, sleep: { _ in })
        conseiller = Conseiller(client: client, store: store)
    }
}
