import Foundation
import Testing
@testable import VillagePlannerKit
@testable import outils

// Les garde-fous du conseiller (T20, PLAN §6.2). Le modèle choisit des identifiants dans une liste fermée et écrit une raison ;
// l'app compose la consigne. G1 : aucun chiffre dans la raison. G2 : identifiants et noms du plan seulement. G3 : tout échec
// montre la consigne du moteur. Le plan est celui de l'export réel anonymisé `reel-hdv16` (tag factice #2PP).

private let reference = Réel.reference
private let espaceFine = "\u{202F}", insecable = "\u{00A0}"

/// Le plan réel une heure après la photo : Animalerie 9 (demain 7 h), Usine de sorts noirs 8 (même heure), Caserne 18 (demain 8 h 15).
private let complet = Complet()
private let resume = complet.resume
private let premier = resume.candidats[0], second = resume.candidats[1], troisieme = resume.candidats[2]

private func verdict(_ raison: String, premier: Int? = nil, ensuite: Int? = nil, dans resume: ResumeConseil = resume) -> Verdict {
    GardeFous.verifier(ReponseConseil(premier: premier ?? resume.candidats[0].id, raison: raison, ensuite: ensuite), resume: resume, reference: reference)
}

private func acceptee(_ raison: String, premier: Int? = nil, ensuite: Int? = nil, dans resume: ResumeConseil = resume) -> Bool {
    if case .acceptee = verdict(raison, premier: premier, ensuite: ensuite, dans: resume) { true } else { false }
}

private func id(_ nom: String) -> Int { reference.items.first { $0.name == nom }!.id }
private func simple(_ t: String) -> String { t.replacingOccurrences(of: insecable, with: " ") }

@Suite struct GardeFousTests {
    // MARK: - G1 : la table des formes reconnues (lues dans la raison, où aucune n'est permise)

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

    // MARK: - G1 : un chiffre, un nombre ou une date dans la raison fait rejeter la réponse

    @Test func G1_chiffreDansLaRaison_faitRejeterLaReponse() {
        #expect(acceptee("elle débloque d'autres améliorations"))
        #expect(verdict("elle coûte 29 M d'or") == .refusee(.nombre("2")))
        for raison in ["elle coûte 29 M", "prépare 29 M d'élixir", "passe au niveau 10", "c'est le 12e niveau", "à 7 h 30", "le 9 décembre", "29 %",
                       "deux ouvriers", "vingt-neuf millions", "douze niveaux d'un coup", "jeudi", "18 000 000", "elle compte pour un quart"] {
            if case .refusee(.nombre) = verdict(raison) {} else { Issue.record("« \(raison) » aurait dû être rejetée par G1 : \(verdict(raison))") }
        }
    }

    @Test func G1_chiffreDeguise_estRejete() {
        // Chiffres pleine chasse, cerclés, arabo-indiens, caché par un espace de largeur nulle : aucun ne passe.
        for raison in ["elle coûte ２９ M", "niveau ①", "٢٩ millions", "elle coûte 2\u{200B}9 M", "une dizaine de jours", "le double", "la moitié du coût"] {
            #expect(!acceptee(raison), "« \(raison) »")
        }
    }

    @Test func G1_aucuneValeurChiffreeNeVientDuModele_laConsigneEstComposeeParLApp() {
        // Quand, noms, niveaux et montants viennent du plan : la raison n'en change aucun.
        guard case .acceptee(let texte, let jusqua) = verdict("elle débloque d'autres améliorations", ensuite: second.id) else {
            Issue.record("réponse honnête refusée"); return
        }
        #expect(simple(texte) == "Demain 7 h, lance Animalerie 9 : elle débloque d'autres améliorations. Puis Usine de sorts noirs 8. Prépare 29 M d'élixir.")
        #expect(jusqua == premier.debut)
        guard case .acceptee(let autre, _) = verdict("c'est un héros") else { return }
        #expect(simple(autre) == "Demain 7 h, lance Animalerie 9 : c'est un héros. Prépare 11 M d'élixir.")
    }

    @Test func G1_lePosteLibre_estAnnonceMaintenant() {
        let c = Complet(now: Réel.village.date.addingTimeInterval(20 * 3600))
        guard case .acceptee(let texte, let jusqua) = GardeFous.verifier(ReponseConseil(premier: c.resume.candidats[0].id, raison: "c'est un héros", ensuite: nil),
                                                                          resume: c.resume, reference: reference) else { Issue.record("refusée"); return }
        #expect(texte.hasPrefix("Maintenant, lance "))
        #expect(texte.contains("Il te faut "))
        #expect(jusqua == nil)
    }

    // MARK: - G2 : un identifiant ou un nom hors du plan fait rejeter la réponse

    @Test func G2_identifiantHorsDesTroisPremiers_faitRejeterLaReponse() {
        let hors = reference.items.first { !resume.identifiantsPermis.contains($0.id) && $0.category != nil }!.id
        #expect(verdict("c'est un héros", premier: hors) == .refusee(.identifiant(hors)))
        #expect(verdict("c'est un héros", premier: 42) == .refusee(.identifiant(42)))
        #expect(verdict("c'est un héros", premier: id("Hôtel de ville")) == .refusee(.identifiant(id("Hôtel de ville"))))
        #expect(verdict("c'est un héros", ensuite: 42) == .refusee(.identifiant(42)))
        #expect(verdict("c'est un héros", ensuite: hors) == .refusee(.identifiant(hors)))
        #expect(verdict("c'est un héros", ensuite: premier.id) == .refusee(.identifiant(premier.id)))      // ensuite ≠ premier
        #expect(acceptee("c'est un héros", premier: second.id, ensuite: premier.id))                        // même instant : permis
        // `premier` démarre au tout premier moment du plan ; `ensuite` en même temps ou après (cas de la relecture : Caserne 8 h 15, puis Animalerie 7 h).
        #expect(troisieme.debut > premier.debut)
        #expect(verdict("c'est un héros", premier: troisieme.id) == .refusee(.identifiant(troisieme.id)))
        #expect(verdict("c'est un héros", premier: troisieme.id, ensuite: premier.id) == .refusee(.identifiant(troisieme.id)))
        #expect(acceptee("c'est un héros", premier: premier.id, ensuite: troisieme.id))                     // plus tard : permis
    }

    @Test func G2_nomEtranger_faitRejeterLaReponse() {
        #expect(verdict("la Reine des archères en profite") == .refusee(.nom("reine des archeres")))
        #expect(verdict("le Roi des barbares en profite") == .refusee(.nom("roi des barbares")))
        #expect(verdict("la \(troisieme.nom) en profite") == .refusee(.nom(Nombres.replier(troisieme.nom))))       // choix non retenu
        #expect(acceptee("la \(troisieme.nom) en profite", ensuite: troisieme.id))                                  // retenu : permis
        #expect(acceptee("l'\(premier.nom) débloque d'autres améliorations"))
        #expect(acceptee("l'\(premier.nom.lowercased()) compte, comme l'\(second.nom.lowercased())", ensuite: second.id))   // casse libre
    }

    @Test func G2_leLaboratoireEtLeForgeron_sontPermisSeulementSiCEstLePosteDuPremierPas() {
        func pas(_ nom: String, _ poste: WorkerKind) -> ResumeConseil {
            let c = PasCandidat(id: id(nom), nom: nom, niveau: 2, copies: 1, debut: Réel.village.date, maintenant: true, couts: [], poste: poste)
            return ResumeConseil(texte: "", candidats: [c], maintenant: Réel.village.date, fuseau: TimeZone(identifier: "UTC")!)
        }
        let labo = pas("Cavalière sylvestre", .laboratory), forge = pas("Tonneau de serpents", .blacksmith)
        #expect(acceptee("le laboratoire en profite", dans: labo))
        #expect(acceptee("le forgeron en profite", dans: forge))
        #expect(!acceptee("le forgeron en profite", dans: labo))                  // rejeté, sans planter
        #expect(!acceptee("le laboratoire en profite", dans: forge))
        #expect(!acceptee("le laboratoire en profite"))                           // le premier du plan est un bâtiment d'ouvrier
        #expect(!acceptee("le forgeron en profite"))
    }

    @Test func G2_leNomLePlusLongGagne_etLePlurielEstTolere() {
        #expect(GardeFous.nomsCites("le Canon à ricochet", reference: reference).values.contains("canon a ricochet"))
        #expect(!GardeFous.nomsCites("le Canon à ricochet", reference: reference).values.contains("canon"))
        #expect(GardeFous.nomsCites("les Canons", reference: reference).values.contains("canon"))
        #expect(GardeFous.nomsCites("un canonnier", reference: reference).isEmpty)
        for nom in ["Arc-X", "Roi des barbares", "Tour à bombes", "Hôtel de ville", "Château de clan", "Cabane d'ouvrier"] {
            #expect(reference.name(of: id(nom)) == nom)
            #expect(GardeFous.nomsCites("Lance \(nom) demain.", reference: reference)[id(nom)] != nil, "\(nom)")
        }
    }

    // MARK: - Forme de la raison

    @Test func forme_uneSeulePhrase_de140CaracteresAuPlus_sansListeNoire() {
        #expect(verdict("") == .refusee(.vide))
        #expect(verdict("   ") == .refusee(.vide))
        #expect(acceptee("elle débloque d'autres améliorations."))                         // un point final est toléré
        #expect(!acceptee("elle débloque tout. lance-la"))
        #expect(!acceptee("elle débloque tout; lance aussi"))
        #expect(!acceptee("elle débloque\ntout"))
        #expect(verdict(String(repeating: "elle débloque ", count: 12)) == .refusee(.trop(caracteres: 167)))
        for mot in ["utilise tes gemmes", "voir http", "ne lance pas ça", "n'attends rien", "jamais en retard", "d'abord celle-ci", "à faire avant", "plus de temps",
                    "moins de temps", "environ ça", "améliore tes murs", "libère un ouvrier", "avec de l'or"] {
            if case .refusee = verdict(mot) {} else { Issue.record("« \(mot) » aurait dû être refusée : \(verdict(mot))") }
        }
        #expect(acceptee("c'est un héros, il compte beaucoup pour ton profil"))
    }

    @Test func forme_lettresLatinesSeulement_ni_homoglyphe_ni_accentCombinant() {
        // Un « е » ou un « а » cyrillique cache « ne » et « pas » à la liste noire : seules les lettres latines passent.
        #expect(!acceptee("elle compte pour ton profil, nе lance pаs ça"))
        #expect(verdict("elle compte pour ton profil, nе lance pаs ça") == .refusee(.interdit("е")))
        #expect(!acceptee("elle compte pour ton profil, lаnce la vite"))
        #expect(!acceptee("elle compte pour ton profil, a\u{0308}\u{0301}"))             // accents combinants sans lettre précomposée
        #expect(!acceptee("elle compte pour ton profil, ελληνικά"))
        #expect(acceptee("elle débloque d'autres améliorations, c'est un bon début"))     // é, è, ç : latines
        #expect(acceptee("elle débloque d’autres améliorations"))                         // apostrophe typographique
        #expect(acceptee("elle d\u{0065}\u{0301}bloque d'autres améliorations"))         // é décomposé : recomposé avant le contrôle
    }

    @Test func forme_chiffresRomainsEtOrdinaux_sontRefuses() {
        for raison in ["passe au niveau XII", "l'\(premier.nom) IX débloque tout", "elle monte au niveau xii", "c'est le douzième niveau", "la deuxième de ta liste",
                       "elle est en seconde position", "la troisième amélioration", "année MMXXVI pour toi", "le niveau viii compte"] {
            #expect(!acceptee(raison), "« \(raison) »")
        }
        #expect(acceptee("c'est le bon choix pour ton profil"))        // « ici », « civil », « mi » : pas des chiffres romains
        #expect(acceptee("elle sert ici, comme un civil au village"))
    }

    @Test func G2_toutMotAMajuscule_horsDebutDePhrase_estUnNomPermisOuUnRejet() {
        #expect(verdict("elle sert pour la Tour d'archère") == .refusee(.nom("Tour")))
        #expect(!acceptee("elle sert pour la Forteresse des ombres"))
        #expect(!acceptee("elle sert pour le Grand Gardien"))
        #expect(!acceptee("elle sert à ton HDV"))
        #expect(acceptee("L'\(premier.nom) débloque d'autres améliorations"))                // début de phrase, nom du premier
        #expect(acceptee("elle sert pour l'\(premier.nom), c'est un bon choix"))               // nom du premier, au milieu
        #expect(acceptee("Elle débloque d'autres améliorations"))
        #expect(acceptee("C'est un bon choix pour ton profil"))                            // « C' » n'est pas un chiffre romain
    }

    @Test func forme_troisMotsAuMoins_dontUnMotOutilFrancais() {
        for raison in ["ok", "bof", "do not launch this one", "skip it and wait", "just wait it out", "bon choix", "lance maintenant"] {
            #expect(!acceptee(raison), "« \(raison) »")
        }
        #expect(verdict("ok") == .refusee(.interdit("phrase")))
        #expect(acceptee("c'est un bon choix"))
    }

    @Test func forme_listeNoireElargie() {
        for raison in ["elle est inutile pour toi", "elle est facultative pour toi", "tu peux sauter celle-ci pour toi", "ignore celle-ci pour ton profil",
                       "reporte celle-ci pour ton profil", "c'est la dernière de ton plan", "elle est secondaire pour ton profil", "elle est dangereuse pour toi",
                       "elle est gratuite pour toi", "elle est terminée pour toi", "à faire tout de suite pour toi", "avant midi pour ton profil", "elle sert pour l'année"] {
            #expect(!acceptee(raison), "« \(raison) »")
        }
    }

    @Test func faussesPositifs_plusHorsNombre_hotelDeVilleEnPrerequis_pointDExclamation() {
        #expect(acceptee("c'est la plus utile pour ton profil"))
        #expect(acceptee("elle est plus forte que les autres"))
        #expect(!acceptee("elle demande plus de temps pour ton profil"))          // « plus de » reste refusé
        #expect(acceptee("elle débloque d'autres améliorations!"))
        #expect(!acceptee("elle débloque d'autres améliorations!!"))
        // L'hôtel de ville : permis quand c'est le prérequis (ou l'élément lui-même) du premier ou du second, sinon refusé.
        let hdv = id("Hôtel de ville")
        let avec = PasCandidat(id: premier.id, nom: premier.nom, niveau: premier.niveau, copies: 1, debut: premier.debut, maintenant: false, couts: [],
                               poste: .builder, prerequis: [hdv])
        let sans = PasCandidat(id: premier.id, nom: premier.nom, niveau: premier.niveau, copies: 1, debut: premier.debut, maintenant: false, couts: [], poste: .builder)
        func r(_ c: PasCandidat) -> ResumeConseil { ResumeConseil(texte: "", candidats: [c], maintenant: Réel.village.date, fuseau: TimeZone(identifier: "UTC")!) }
        #expect(acceptee("elle demande ton hôtel de ville pour progresser", dans: r(avec)))
        #expect(!acceptee("elle demande ton hôtel de ville pour progresser", dans: r(sans)))
    }

    @Test func attaques_aucuneReponseFausseAcceptee_etLesContrôlesHonnetesPassent() {
        let attaques = Attaques.attaques(resume: resume, reference: reference)
        #expect(attaques.count >= 57, "\(attaques.count) attaques")
        for a in attaques {
            if case .acceptee(let texte, _) = GardeFous.verifier(a.reponse, resume: resume, reference: reference) {
                Issue.record("attaque acceptée : \(a.nom) → \(texte)")
            }
        }
        let controles = Attaques.controles(resume: resume)
        #expect(controles.count >= 6)
        for c in controles {
            if case .refusee(let m) = GardeFous.verifier(c.reponse, resume: resume, reference: reference) { Issue.record("\(c.nom) refusé : \(m)") }
        }
    }

    // MARK: - Le schéma impose la liste fermée

    @Test func schema_premierEtEnsuite_sontDesEnumerationsDesIdentifiantsDuPlan() throws {
        let attendu = resume.identifiantsPermis, premiers = resume.premiersPermis
        #expect(attendu.count >= 2 && attendu.count <= ResumeConseil.choixMax && !premiers.isEmpty && premiers.count < attendu.count + 1)
        let json = try #require(JSONSerialization.jsonObject(with: Data(resume.schema.utf8)) as? [String: Any])
        let props = try #require(json["properties"] as? [String: Any])
        #expect((props["premier"] as? [String: Any])?["enum"] as? [Int] == premiers)        // les pas du tout premier moment
        let anyOf = try #require((props["ensuite"] as? [String: Any])?["anyOf"] as? [[String: Any]])
        #expect(anyOf[0]["enum"] as? [Int] == attendu && anyOf[1]["type"] as? String == "null")
        #expect(json["required"] as? [String] == ["premier", "raison", "ensuite"] && json["additionalProperties"] as? Bool == false)
    }

    @Test func schema_estCeluiQuiPartAuService() async throws {
        let banc = BancConseiller(reponses: [Self.ok(premier.id, "c'est un héros", nil)])
        _ = await banc.conseiller.obtenir(resume: resume, cle: "k", reference: reference, now: BancConseiller.maintenant)
        let corps = try #require(await banc.transport.requetes.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: corps) as? [String: Any])
        let format = try #require(((json["output_config"] as? [String: Any])?["format"]) as? [String: Any])
        let schema = try #require(format["schema"] as? [String: Any])
        let premierEnum = ((schema["properties"] as? [String: Any])?["premier"] as? [String: Any])?["enum"] as? [Int]
        #expect(premierEnum == resume.premiersPermis)
    }

    // MARK: - G3 : tout échec montre la consigne du moteur, sans alerte

    static func json(_ premier: Int, _ raison: String, _ ensuite: Int?) -> String {
        let e: Any = ensuite.map { $0 as Any } ?? NSNull()
        return String(decoding: try! JSONSerialization.data(withJSONObject: ["premier": premier, "raison": raison, "ensuite": e]), as: UTF8.self)
    }
    static func ok(_ premier: Int, _ raison: String, _ ensuite: Int?) -> Reponse { .ok(json(premier, raison, ensuite)) }

    @Test func G3_toutEchec_montreLaConsigneDuMoteur_sansAlerte() async throws {
        let moteur = "Demain 7 h, deux ouvriers se libèrent : lance Animalerie 9 et Usine de sorts noirs 8. Prépare 29 M d'élixir."
        let p = premier.id
        // Chaque ligne : la réponse du service (ou son absence), et pourquoi l'écran montre le moteur.
        let cas: [(String, String?, [Reponse])] = [
            ("pas de clé", nil, [Self.ok(p, "c'est un héros", nil)]),
            ("clé refusée (401)", BancConseiller.cle, [.http(401)]),
            ("trop de requêtes (429 deux fois)", BancConseiller.cle, [.http(429, ["retry-after": "1"]), .http(429, ["retry-after": "1"])]),
            ("erreur du service (500)", BancConseiller.cle, [.http(500)]),
            ("hors ligne", BancConseiller.cle, [.panne(.notConnectedToInternet)]),
            ("délai dépassé", BancConseiller.cle, [.panne(.timedOut)]),
            ("refus du modèle", BancConseiller.cle, [.ok(nil, stop: "refusal", categorie: "cyber")]),
            ("hors schéma : pas du JSON", BancConseiller.cle, [.ok("pas du json")]),
            ("hors schéma : un champ manque", BancConseiller.cle, [.ok(#"{"premier":1}"#)]),
            ("tronquée (max_tokens)", BancConseiller.cle, [.ok(Self.json(p, "c'est un héros", nil), stop: "max_tokens")]),
            ("G1 : chiffre dans la raison", BancConseiller.cle, [Self.ok(p, "elle coûte 19 M d'or", nil)]),
            ("G1 : nombre en lettres", BancConseiller.cle, [Self.ok(p, "dix-neuf millions", nil)]),
            ("G2 : identifiant hors des trois premiers", BancConseiller.cle, [Self.ok(id("Canon"), "c'est un héros", nil)]),
            ("G2 : nom inventé", BancConseiller.cle, [Self.ok(p, "la Tour à bombes en profite", nil)]),
            ("liste noire", BancConseiller.cle, [Self.ok(p, "ne lance pas ça", nil)]),
            ("trop long", BancConseiller.cle, [Self.ok(p, String(repeating: "elle compte ", count: 20), nil)]),
        ]
        for (nom, cle, reponses) in cas {
            let banc = BancConseiller(cle: cle, reponses: reponses)
            let issue = await banc.conseiller.obtenir(resume: resume, cle: "k", reference: reference, now: BancConseiller.maintenant)
            #expect(!issue.estConseil, "\(nom) : un conseil a été montré")
            #expect(issue.texte(repli: moteur) == moteur, "\(nom) : l'écran ne montre pas la consigne du moteur")
        }
        // Et le cas de réussite : la consigne composée remplace le moteur.
        let banc = BancConseiller(cle: BancConseiller.cle, reponses: [Self.ok(p, "c'est un héros", nil)])
        let issue = await banc.conseiller.obtenir(resume: resume, cle: "k", reference: reference, now: BancConseiller.maintenant)
        #expect(issue.estConseil && issue.texte(repli: moteur) != moteur)
    }

    @Test func G3_plafondAtteint_aucunAppel_laConsigneDuMoteurResteAffichee() async {
        var b = Budget()
        for _ in 0..<Budget.callsPerDay { b.recordCall(at: BancConseiller.maintenant, calendar: BancConseiller.calendrier) }
        let banc = BancConseiller(cle: BancConseiller.cle, budget: b, reponses: [Self.ok(premier.id, "c'est un héros", nil)])
        let issue = await banc.conseiller.obtenir(resume: resume, cle: "k", reference: reference, now: BancConseiller.maintenant)
        #expect(issue == .repli(.erreur(.budgetReached(.daily))))
        #expect(issue.texte(repli: "moteur") == "moteur")
        #expect(await banc.transport.requetes.isEmpty)
    }

    @Test func G3_leTrousseauFerme_laConsigneDuMoteurResteAffichee() async {
        let banc = BancConseiller(coffre: CoffreEnPanne(), reponses: [])
        let issue = await banc.conseiller.obtenir(resume: resume, cle: "k", reference: reference, now: BancConseiller.maintenant)
        #expect(issue.texte(repli: "moteur") == "moteur")
        #expect(await banc.transport.requetes.isEmpty)
    }

    @Test func G3_photoPerimee_ouRienAChoisir_aucunAppel() async {
        let vieux = Complet(now: Réel.village.date.addingTimeInterval(9 * 86_400))
        #expect(vieux.resume.candidats.isEmpty)
        let banc = BancConseiller(reponses: [Self.ok(premier.id, "c'est un héros", nil)])
        let issue = await banc.conseiller.obtenir(resume: vieux.resume, cle: "k", reference: reference, now: BancConseiller.maintenant)
        #expect(issue == .repli(.rienAChoisir))
        #expect(await banc.transport.requetes.isEmpty)
    }
}

// MARK: - Banc des tests du conseiller (partagé avec ConseillerTests)

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
        let defaults = PreferencesDeTest.neuves()
        let budgetStore = BudgetStore(defaults: defaults)
        budgetStore.save(budget)
        transport = FauxTransport(reponses)
        store = PreferencesConseil(defaults: defaults)
        let client = ClaudeClient(keys: coffre ?? MemorySecretStore(cle), budget: budgetStore, transport: transport,
                                  calendar: Self.calendrier, sleep: { _ in })
        conseiller = Conseiller(client: client, store: store)
    }
}
