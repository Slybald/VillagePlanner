import Foundation
import Security
import Testing
@testable import ChantierKit

// Client de l'API officielle (T29). Aucun test n'appelle le vrai service : le transport est simulé (celui de T19), la clé est
// factice (elle n'a pas la forme d'une vraie clé), le tag est le tag factice `#2PP` et toutes les valeurs sont inventées.

private let cleJoueur = "cle-factice-JOUEUR-0000-aaaa-bbbb-cccc-4321"
private let t0 = Date(timeIntervalSince1970: 1_794_500_000)          // « maintenant » de tous les tests
private func apres(_ secondes: TimeInterval) -> Date { t0.addingTimeInterval(secondes) }

private func dateHTTP(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .gmt
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return f.string(from: date)
}

// MARK: Réponses du service

private func profil(_ json: String) -> Reponse { .http(200, [:], Data(json.utf8)) }

/// Un profil complet, avec des champs que l'app ne lit pas (`league`, `clan`, `troops`, un champ du futur).
private let profilComplet = """
{"tag":"#2PP","name":"Testeur","expLevel":210,"townHallLevel":16,"trophies":5421,"bestTrophies":5600,
 "attackWins":120,"defenseWins":7,"donations":1500,"donationsReceived":900,"warStars":812,
 "league":{"id":29000000,"name":"Unranked"},
 "leagueTier":{"id":105000030,"name":"Dragon League 30","iconUrls":{"small":"https://exemple.invalid/s.png"}},
 "clan":{"tag":"#2PP","name":"Clan test"},
 "achievements":[{"name":"Bigger & Better","stars":3,"value":16,"target":16,"info":"x","completionInfo":null,"village":"home"}],
 "heroes":[{"name":"Barbarian King","level":95,"maxLevel":95,"village":"home",
            "equipment":[{"name":"Giant Gauntlet","level":27,"maxLevel":27,"village":"home"}]},
           {"name":"Grand Warden","level":70,"maxLevel":75,"village":"home"}],
 "heroEquipment":[{"name":"Giant Gauntlet","level":27,"maxLevel":27,"village":"home"},{"name":"Rage Vial","level":18,"maxLevel":18,"village":"home"}],
 "troops":[{"name":"Barbarian","level":12}],"champDuFutur":{"a":[1,2,3]}}
"""

private let attenduComplet = ProfilJoueur(
    tag: "#2PP", name: "Testeur", expLevel: 210, townHallLevel: 16, trophies: 5421, bestTrophies: 5600,
    attackWins: 120, defenseWins: 7, donations: 1500, donationsReceived: 900, warStars: 812,
    leagueTier: LigueJoueur(id: 105000030, name: "Dragon League 30"),
    achievements: [SuccesJoueur(name: "Bigger & Better", stars: 3, value: 16, target: 16, village: "home")],
    heroes: [HeroJoueur(name: "Barbarian King", level: 95, maxLevel: 95, village: "home",
                        equipment: [ItemJoueur(name: "Giant Gauntlet", level: 27, maxLevel: 27, village: "home")]),
             HeroJoueur(name: "Grand Warden", level: 70, maxLevel: 75, village: "home")],
    heroEquipment: [ItemJoueur(name: "Giant Gauntlet", level: 27, maxLevel: 27, village: "home"),
                    ItemJoueur(name: "Rage Vial", level: 18, maxLevel: 18, village: "home")])

// MARK: Doublures

/// Un Trousseau qui ne répond pas (appareil verrouillé).
private struct StoreMuet: SecretStore {
    func read() throws(KeyStoreError) -> String? { throw .keychain(status: -25308) }
    func save(_ secret: String) throws(KeyStoreError) { throw .keychain(status: -25308) }
    func delete() throws(KeyStoreError) { throw .keychain(status: -25308) }
}

/// Un banc neuf : préférences isolées, Trousseau en mémoire, faux transport. `ouverture()` donne un client neuf sur les mêmes
/// préférences : c'est une nouvelle ouverture de l'app.
private struct Banc: @unchecked Sendable {
    let defaults = UserDefaults(suiteName: "chantier-test-joueur-\(UUID().uuidString)")!
    let cadence: CadenceStore
    let transport: FauxTransport
    let cles: any SecretStore

    init(cle: String? = cleJoueur, cles: (any SecretStore)? = nil, reponses: [Reponse] = []) {
        cadence = CadenceStore(defaults: defaults)
        transport = FauxTransport(reponses)
        self.cles = cles ?? MemorySecretStore(cle)
    }

    func ouverture() -> ClientJoueur { ClientJoueur(keys: cles, cadence: cadence, transport: transport) }

    func lire(tag: String? = "#2PP", now: Date = t0, avec client: ClientJoueur? = nil) async -> Result<ProfilJoueur, JoueurError> {
        do throws(JoueurError) { return .success(try await (client ?? ouverture()).lire(tag: tag, now: now)) } catch { return .failure(error) }
    }
}

// MARK: Table des cas

struct CasJoueur: Sendable, CustomTestStringConvertible {
    let nom: String
    var cle: String? = cleJoueur
    var tag: String? = "#2PP"
    /// Une lecture partie à t0 + ce décalage (négatif : dans le passé).
    var derniereLecture: TimeInterval?
    var now = t0
    var reponses: [Reponse] = []
    let attendu: Result<ProfilJoueur, JoueurError>
    /// Nombre de requêtes parties vers le relais.
    let envois: Int
    var testDescription: String { nom }

    static let minimal = ProfilJoueur(tag: "#2PP")

    static let table: [CasJoueur] = [
        // Acceptés
        CasJoueur(nom: "200 complet : tous les champs lus, ceux que l'app ignore aussi", reponses: [profil(profilComplet)],
                  attendu: .success(attenduComplet), envois: 1),
        CasJoueur(nom: "200 réduit au tag : tout le reste absent, toléré", reponses: [profil(##"{"tag":"#2PP"}"##)],
                  attendu: .success(minimal), envois: 1),
        CasJoueur(nom: "200 avec champs nuls ou d'un autre type : écartés, les autres gardés",
                  reponses: [profil(##"{"tag":"#2PP","trophies":"beaucoup","bestTrophies":null,"warStars":12.5,"donations":9,"leagueTier":"aucune","heroes":"non"}"##)],
                  attendu: .success(ProfilJoueur(tag: "#2PP", donations: 9)), envois: 1),
        CasJoueur(nom: "200, héros sans nom, succès illisible et équipement nul : seuls les éléments lisibles restent",
                  reponses: [profil(##"{"tag":"#2PP","heroes":[{"level":3},{"name":"Archer Queen","level":"x","equipment":[null,{"name":"Frozen Arrow"},5]},7],"achievements":[null,{"name":"A","stars":"1"}]}"##)],
                  attendu: .success(ProfilJoueur(tag: "#2PP", achievements: [SuccesJoueur(name: "A")],
                                                 heroes: [HeroJoueur(name: "Archer Queen", equipment: [ItemJoueur(name: "Frozen Arrow")])])),
                  envois: 1),
        CasJoueur(nom: "tag en minuscules, sans dièse, avec O : lu comme #2PP", tag: " 2pp ", reponses: [profil(##"{"tag":"#2PP"}"##)],
                  attendu: .success(minimal), envois: 1),
        // Erreurs du service
        CasJoueur(nom: "403 : clé refusée", reponses: [.http(403, [:], Data(##"{"reason":"accessDenied.invalidIp"}"##.utf8))],
                  attendu: .failure(.rejectedKey), envois: 1),
        CasJoueur(nom: "404 : joueur introuvable", reponses: [.http(404)], attendu: .failure(.notFound), envois: 1),
        CasJoueur(nom: "429 : trop de requêtes, aucune nouvelle tentative", reponses: [.http(429, ["retry-after": "1"])],
                  attendu: .failure(.rateLimited), envois: 1),
        CasJoueur(nom: "503 : maintenance", reponses: [.http(503)], attendu: .failure(.maintenance), envois: 1),
        CasJoueur(nom: "502 : relais en panne", reponses: [.http(502)], attendu: .failure(.serverError(status: 502)), envois: 1),
        CasJoueur(nom: "400 : requête refusée", reponses: [.http(400)], attendu: .failure(.rejected(status: 400)), envois: 1),
        CasJoueur(nom: "hors ligne", reponses: [.panne(.notConnectedToInternet)], attendu: .failure(.offline), envois: 1),
        CasJoueur(nom: "hôte injoignable : hors ligne", reponses: [.panne(.cannotFindHost)], attendu: .failure(.offline), envois: 1),
        CasJoueur(nom: "connexion coupée en route : hors ligne", reponses: [.panne(.networkConnectionLost)], attendu: .failure(.offline), envois: 1),
        CasJoueur(nom: "délai dépassé", reponses: [.panne(.timedOut)], attendu: .failure(.timeout), envois: 1),
        CasJoueur(nom: "tâche annulée : délai", reponses: [.annulee], attendu: .failure(.timeout), envois: 1),
        // Hors schéma
        CasJoueur(nom: "hors schéma : objet sans tag", reponses: [profil(##"{"reason":"notFound"}"##)], attendu: .failure(.invalidResponse), envois: 1),
        CasJoueur(nom: "hors schéma : tag qui n'est pas du texte", reponses: [profil(##"{"tag":2}"##)], attendu: .failure(.invalidResponse), envois: 1),
        CasJoueur(nom: "hors schéma : liste JSON", reponses: [profil(##"[{"tag":"#2PP"}]"##)], attendu: .failure(.invalidResponse), envois: 1),
        CasJoueur(nom: "hors schéma : page HTML", reponses: [profil("<html>Just a moment…</html>")], attendu: .failure(.invalidResponse), envois: 1),
        CasJoueur(nom: "hors schéma : corps vide", reponses: [.http(200)], attendu: .failure(.invalidResponse), envois: 1),
        CasJoueur(nom: "hors schéma : JSON tronqué", reponses: [profil(##"{"tag":"#2PP","trophies":54"##)], attendu: .failure(.invalidResponse), envois: 1),
        CasJoueur(nom: "réponse au-delà de la limite du transport", reponses: [.trop], attendu: .failure(.invalidResponse), envois: 1),
        // Avant l'envoi
        CasJoueur(nom: "pas de clé : rien ne part", cle: nil, attendu: .failure(.noKey), envois: 0),
        CasJoueur(nom: "clé faite d'espaces : rien ne part", cle: "  \n", attendu: .failure(.noKey), envois: 0),
        CasJoueur(nom: "pas de tag (aucune photo) : rien ne part", tag: nil, attendu: .failure(.noTag), envois: 0),
        CasJoueur(nom: "tag vide : rien ne part", tag: "", attendu: .failure(.invalidTag), envois: 0),
        CasJoueur(nom: "tag avec des lettres hors alphabet : rien ne part", tag: "#2PZ", attendu: .failure(.invalidTag), envois: 0),
        CasJoueur(nom: "tag qui tente de sortir du chemin : rien ne part", tag: "#2PP/../../x?k=1", attendu: .failure(.invalidTag), envois: 0),
        CasJoueur(nom: "tag avec retour à la ligne au milieu : rien ne part", tag: "#2P\nP", attendu: .failure(.invalidTag), envois: 0),
        // Cadence : une heure entre deux lectures
        CasJoueur(nom: "dernière lecture il y a 61 min : permise", derniereLecture: -3_660, reponses: [profil(##"{"tag":"#2PP"}"##)],
                  attendu: .success(minimal), envois: 1),
        CasJoueur(nom: "dernière lecture il y a exactement 60 min : permise", derniereLecture: -3_600, reponses: [profil(##"{"tag":"#2PP"}"##)],
                  attendu: .success(minimal), envois: 1),
        CasJoueur(nom: "dernière lecture il y a 59 min : refusée, rien ne part", derniereLecture: -3_540,
                  attendu: .failure(.tooSoon(.hourly(until: apres(60)))), envois: 0),
        CasJoueur(nom: "dernière lecture à l'instant : refusée, rien ne part", derniereLecture: 0,
                  attendu: .failure(.tooSoon(.hourly(until: apres(3_600)))), envois: 0),
        CasJoueur(nom: "dernière lecture il y a 10 min, l'horloge recule de 5 min : refusée",
                  derniereLecture: -600, now: apres(-300), attendu: .failure(.tooSoon(.hourly(until: apres(3_000)))), envois: 0),
        CasJoueur(nom: "dernière lecture à t0, l'horloge recule de 2 h : refusée, rien ne part",
                  derniereLecture: 0, now: apres(-7_200), attendu: .failure(.tooSoon(.hourly(until: apres(3_600)))), envois: 0),
        CasJoueur(nom: "horloge avancée de 2 jours puis remise à l'heure, le service donne sa date : recalée, une heure à partir de cette date",
                  derniereLecture: 172_800, reponses: [.http(200, ["Date": dateHTTP(t0)])],
                  attendu: .failure(.tooSoon(.hourly(until: apres(3_600)))), envois: 1),
        CasJoueur(nom: "horloge avancée de 2 jours puis remise à l'heure, le service ne répond pas : refusée, seule la sonde part",
                  derniereLecture: 172_800, reponses: [.panne(.notConnectedToInternet)],
                  attendu: .failure(.tooSoon(.hourly(until: apres(172_800 + 3_600)))), envois: 1),
    ]
}

@Suite struct JoueurTests {

    @Test(arguments: CasJoueur.table)
    func tableDesCas(_ cas: CasJoueur) async {
        let banc = Banc(cle: cas.cle, reponses: cas.reponses)
        if let d = cas.derniereLecture { _ = banc.cadence.reserver(at: apres(d)) }
        let resultat = await banc.lire(tag: cas.tag, now: cas.now)
        #expect(resultat == cas.attendu)
        #expect(await banc.transport.requetes.count == cas.envois)
        // La requête de lecture est partie vers l'hôte fixe, en HTTPS ; la sonde d'horloge ne porte pas la clé.
        for r in await banc.transport.requetes {
            #expect(r.url?.scheme == "https" && r.url?.host == "cocproxy.royaleapi.dev")
            if r.httpMethod == "HEAD" { #expect(r.value(forHTTPHeaderField: "authorization") == nil) }
        }
        // Aucune erreur ne contient la clé.
        if case .failure(let e) = resultat {
            for texte in [String(describing: e), String(reflecting: e), e.localizedDescription] {
                #expect(!texte.contains("cle-factice"))
            }
        }
    }

    // MARK: Requête

    @Test func requete_getHttpsVersLHoteFixe_tagEncode_cleDansLEnTeteSeulement() async throws {
        let banc = Banc(reponses: [profil(##"{"tag":"#2PP"}"##)])
        _ = await banc.lire()
        let r = try #require(await banc.transport.requetes.first)
        let url = try #require(r.url)
        #expect(url.absoluteString == "https://cocproxy.royaleapi.dev/v1/players/%232PP")
        #expect(url.fragment == nil && url.query == nil)               // le dièse non encodé ouvrirait un fragment
        #expect(r.httpMethod == "GET")
        #expect(r.value(forHTTPHeaderField: "authorization") == "Bearer \(cleJoueur)")
        #expect(r.value(forHTTPHeaderField: "accept") == "application/json")
        #expect(!url.absoluteString.contains(cleJoueur) && r.httpBody == nil)
        #expect(r.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func tag_normalise() {
        #expect(ClientJoueur.normalizedTag("#2PP") == "#2PP")
        #expect(ClientJoueur.normalizedTag("2pp") == "#2PP")
        #expect(ClientJoueur.normalizedTag("#2pO") == "#2P0")          // le jeu lit O comme 0
        #expect(ClientJoueur.normalizedTag("##2PP") == nil)
        #expect(ClientJoueur.normalizedTag("#") == nil)
        #expect(ClientJoueur.normalizedTag(String(repeating: "P", count: 16)) == nil)
    }

    // MARK: Une lecture par ouverture, une par heure

    @Test func uneSeuleLectureParOuverture_laSecondeNePartPas() async {
        let banc = Banc(reponses: [profil(##"{"tag":"#2PP"}"##)])
        let client = banc.ouverture()
        #expect(await banc.lire(avec: client) == .success(CasJoueur.minimal))
        #expect(await banc.lire(now: apres(7_200), avec: client) == .failure(.tooSoon(.thisLaunch)))   // même 2 h plus tard
        #expect(await banc.transport.requetes.count == 1)
    }

    @Test func deuxOuverturesDansLHeure_laSecondeNePartPas_uneHeureApresElleEstPermise() async {
        let banc = Banc(reponses: [profil(##"{"tag":"#2PP"}"##), profil(##"{"tag":"#2PP"}"##)])
        #expect(await banc.lire() == .success(CasJoueur.minimal))
        #expect(await banc.lire(now: apres(1_800)) == .failure(.tooSoon(.hourly(until: apres(3_600)))))
        #expect(await banc.lire(now: apres(3_599)) == .failure(.tooSoon(.hourly(until: apres(3_600)))))
        #expect(await banc.transport.requetes.count == 1)
        #expect(await banc.lire(now: apres(3_600)) == .success(CasJoueur.minimal))
        #expect(await banc.transport.requetes.count == 2)
    }

    @Test func uneLectureRefuseeParLeServiceCompte_ellePorteUneHeure() async {
        let banc = Banc(reponses: [.http(403)])
        #expect(await banc.lire() == .failure(.rejectedKey))
        #expect(await banc.lire(now: apres(60)) == .failure(.tooSoon(.hourly(until: apres(3_600)))))
        #expect(await banc.transport.requetes.count == 1)
    }

    @Test func pasDeReseau_laLectureNeComptePas_onPeutReessayerAussitot() async {
        let banc = Banc(reponses: [.panne(.notConnectedToInternet), profil(##"{"tag":"#2PP"}"##)])
        let client = banc.ouverture()
        #expect(await banc.lire(avec: client) == .failure(.offline))
        #expect(await banc.lire(now: apres(5), avec: client) == .success(CasJoueur.minimal))
        #expect(await banc.transport.requetes.count == 2)
    }

    @Test func delaiDepasse_laLectureCompte() async {
        let banc = Banc(reponses: [.panne(.timedOut)])
        #expect(await banc.lire() == .failure(.timeout))
        #expect(await banc.lire(now: apres(5)) == .failure(.tooSoon(.hourly(until: apres(3_600)))))
    }

    @Test func deuxLecturesEnMemeTemps_uneSeuleParte() async {
        let banc = Banc(reponses: [profil(##"{"tag":"#2PP"}"##)])
        let client = banc.ouverture()
        async let a = banc.lire(avec: client)
        async let b = banc.lire(avec: client)
        let resultats = await [a, b]
        #expect(resultats.filter { $0 == .success(CasJoueur.minimal) }.count == 1)
        #expect(resultats.contains(.failure(.tooSoon(.thisLaunch))))
        #expect(await banc.transport.requetes.count == 1)
    }

    @Test func horlogeAvanceeEtRemise_apresRecalage_laLectureRepartUneHeureApresLaDateDuService() async {
        let banc = Banc(reponses: [.http(200, ["Date": dateHTTP(t0)]), profil(##"{"tag":"#2PP"}"##)])
        _ = banc.cadence.reserver(at: apres(172_800))
        #expect(await banc.lire() == .failure(.tooSoon(.hourly(until: apres(3_600)))))
        #expect(await banc.lire(now: apres(3_600)) == .success(CasJoueur.minimal))
    }

    @Test func troussauMuet_cleInconnue_rienNePart() async {
        let banc = Banc(cles: StoreMuet())
        #expect(await banc.lire() == .failure(.keychainUnavailable))
        #expect(await banc.transport.requetes.isEmpty)
        #expect(banc.cadence.load().dernierAppel == nil)                 // et la cadence n'est pas entamée
    }

    @Test func sansCleOuSansTag_laCadenceNEstPasEntamee() async {
        let sansCle = Banc(cle: nil)
        _ = await sansCle.lire()
        #expect(sansCle.cadence.load().dernierAppel == nil)
        let sansTag = Banc()
        _ = await sansTag.lire(tag: nil)
        #expect(sansTag.cadence.load().dernierAppel == nil)
    }

    // MARK: Secret

    @Test func cle_jamaisDansLesPreferences_ni_standard_ni_celles_de_la_cadence() async {
        let banc = Banc(reponses: [profil(##"{"tag":"#2PP"}"##), .http(403)])
        _ = await banc.lire()
        _ = await banc.lire(now: apres(4_000))
        for defaults in [banc.defaults, UserDefaults.standard] {
            for (nom, valeur) in defaults.dictionaryRepresentation() {
                let texte = (valeur as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "\(valeur)"
                #expect(!texte.contains("cle-factice") && !nom.contains("cle-factice"), "clé dans les préférences (\(nom))")
            }
        }
    }

    @Test func trousseau_autreCompteQueLeConseiller_surCetAppareilSeulement() {
        let a = KeychainStoreJoueur.attributes(for: cleJoueur)
        #expect(a[kSecClass as String] as! CFString == kSecClassGenericPassword)
        #expect(a[kSecAttrAccessible as String] as! CFString == kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        #expect(a[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(a[kSecValueData as String] as? Data == Data(cleJoueur.utf8))
        #expect(KeychainStoreJoueur.query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(KeychainStoreJoueur.service != KeychainStore.service && KeychainStoreJoueur.account != KeychainStore.account)
    }

    @Test func cleSupercell_unJetonJwtEstAcceptee_unTexteAvecEspaceNon() {
        #expect(APIKey.normalized("eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl") != nil)
        #expect(APIKey.normalized("Bearer eyJ.x.y") == nil)
    }
}
