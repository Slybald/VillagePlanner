import Foundation
import Security
import Testing
@testable import ChantierKit

// Client Claude, clé et budget (T19). Aucun test n'appelle le vrai service : le transport est simulé, l'attente aussi,
// et la clé est factice (elle n'a pas la forme d'une vraie clé).

private let cleFactice = "cle-factice-TEST-0000-aaaa-bbbb-cccc-9876"
private let paris: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Paris")!
    return c
}()
private func le(_ jour: Int, _ mois: Int = 11, _ heure: Int = 10, _ minute: Int = 0) -> Date {
    paris.date(from: DateComponents(year: 2026, month: mois, day: jour, hour: heure, minute: minute))!
}
private let maintenant = le(12)

// MARK: Doublures

/// Une réponse simulée du service.
enum Reponse: Sendable {
    case http(Int, [String: String] = [:], Data = Data())
    case panne(URLError.Code)

    /// Une réponse 200 de l'API Messages : un bloc `thinking` vide en tête, comme Haiku 5.5 peut en renvoyer.
    static func ok(_ texte: String? = #"{"ok":true}"#, stop: String = "end_turn", categorie: String? = nil,
                   entree: Int = 3_500, sortie: Int = 900, cacheLu: Int = 0, cacheEcrit: Int = 0) -> Reponse {
        var contenu: [[String: Any]] = [["type": "thinking", "thinking": "", "signature": "sig"]]
        if let texte { contenu.append(["type": "text", "text": texte]) }
        var json: [String: Any] = [
            "id": "msg_test", "type": "message", "role": "assistant", "model": "claude-haiku-5-5",
            "content": contenu, "stop_reason": stop,
            "usage": ["input_tokens": entree, "output_tokens": sortie,
                      "cache_read_input_tokens": cacheLu, "cache_creation_input_tokens": cacheEcrit],
        ]
        json["stop_details"] = stop == "refusal" ? ["type": "refusal", "category": categorie as Any, "explanation": "…"] : NSNull()
        return .http(200, [:], try! JSONSerialization.data(withJSONObject: json))
    }
}

actor FauxTransport: HTTPTransport {
    private var reponses: [Reponse]
    private(set) var requetes: [URLRequest] = []

    /// Une fois la liste épuisée, chaque envoi reçoit `Reponse.ok()`.
    init(_ reponses: [Reponse] = []) { self.reponses = reponses }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requetes.append(request)
        let r = reponses.isEmpty ? Reponse.ok() : reponses.removeFirst()
        switch r {
        case .panne(let code): throw URLError(code)
        case .http(let statut, let entetes, let corps):
            return (corps, HTTPURLResponse(url: request.url!, statusCode: statut, httpVersion: "HTTP/1.1", headerFields: entetes)!)
        }
    }
}

actor Attentes {
    private(set) var durees: [Duration] = []
    func noter(_ d: Duration) { durees.append(d) }
}

/// Un client neuf, avec ses préférences isolées.
private struct Banc {
    let client: ClaudeClient
    let transport: FauxTransport
    let attentes = Attentes()
    let defaults: UserDefaults
    let budget: BudgetStore

    init(cle: String? = cleFactice, budget depart: Budget = Budget(), reponses: [Reponse] = []) {
        defaults = UserDefaults(suiteName: "chantier-test-\(UUID().uuidString)")!
        budget = BudgetStore(defaults: defaults)
        budget.save(depart)
        transport = FauxTransport(reponses)
        let attentes = attentes
        client = ClaudeClient(keys: MemorySecretStore(cle), budget: budget, transport: transport, calendar: paris,
                              sleep: { await attentes.noter($0) })
    }

    struct Ok: Decodable { let ok: Bool }
    static let schema = #"{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"],"additionalProperties":false}"#

    func demander(now: Date = maintenant) async -> Result<Bool, ClaudeError> {
        do throws(ClaudeError) {
            return .success(try await client.ask(system: "consigne", prompt: "résumé", schema: Self.schema, as: Ok.self, now: now).ok)
        } catch { return .failure(error) }
    }
}

private func depart(appels: Int = 0, depense: Int = 0, le date: Date = maintenant) -> Budget {
    var b = Budget()
    for _ in 0..<appels { b.recordCall(at: date, calendar: paris) }
    b.recordCost(depense, at: date, calendar: paris)
    return b
}

// MARK: Table des cas refusés et acceptés

/// Un cas de la table : l'état de départ, ce que répond le service, ce qui doit en sortir.
struct Cas: Sendable, CustomTestStringConvertible {
    let nom: String
    var cle: String? = cleFactice
    var budget = Budget()
    var now = maintenant
    var reponses: [Reponse] = []
    let attendu: Result<Bool, ClaudeError>
    /// Nombre de requêtes parties vers le service.
    let envois: Int
    var attentes: [Duration] = []
    var testDescription: String { nom }

    static let table: [Cas] = [
        // Accepté
        Cas(nom: "réponse conforme, bloc thinking en tête : acceptée", attendu: .success(true), envois: 1),
        // Erreurs
        Cas(nom: "pas de clé : refusé, rien ne part", cle: nil, attendu: .failure(.noKey), envois: 0),
        Cas(nom: "clé vide (espaces) : refusé, rien ne part", cle: "   \n", attendu: .failure(.noKey), envois: 0),
        Cas(nom: "401 clé refusée : refusé, pas de nouvelle tentative", reponses: [.http(401)], attendu: .failure(.unauthorized), envois: 1),
        Cas(nom: "429 puis 200 : une nouvelle tentative après retry-after, acceptée",
            reponses: [.http(429, ["retry-after": "3"]), .ok()], attendu: .success(true), envois: 2, attentes: [.seconds(3)]),
        Cas(nom: "429 sans retry-after puis 200 : attente d'une seconde, acceptée",
            reponses: [.http(429), .ok()], attendu: .success(true), envois: 2, attentes: [.seconds(1)]),
        Cas(nom: "429 deux fois : une seule nouvelle tentative, refusé",
            reponses: [.http(429, ["retry-after": "2"]), .http(429, ["retry-after": "2"])],
            attendu: .failure(.rateLimited), envois: 2, attentes: [.seconds(2)]),
        Cas(nom: "429 avec retry-after de 60 s : pas d'attente, refusé",
            reponses: [.http(429, ["retry-after": "60"])], attendu: .failure(.rateLimited), envois: 1),
        Cas(nom: "429 avec retry-after démesuré (1e300) : pas de plantage, refusé",
            reponses: [.http(429, ["retry-after": "1e300"])], attendu: .failure(.rateLimited), envois: 1),
        Cas(nom: "500 : erreur du service, pas de nouvelle tentative", reponses: [.http(500)],
            attendu: .failure(.serviceUnavailable(status: 500)), envois: 1),
        Cas(nom: "529 surcharge : erreur du service", reponses: [.http(529)],
            attendu: .failure(.serviceUnavailable(status: 529)), envois: 1),
        Cas(nom: "400 requête refusée", reponses: [.http(400)], attendu: .failure(.rejected(status: 400)), envois: 1),
        Cas(nom: "hors ligne", reponses: [.panne(.notConnectedToInternet)], attendu: .failure(.offline), envois: 1),
        Cas(nom: "hôte injoignable : hors ligne", reponses: [.panne(.cannotConnectToHost)], attendu: .failure(.offline), envois: 1),
        Cas(nom: "délai dépassé", reponses: [.panne(.timedOut)], attendu: .failure(.timeout), envois: 1),
        Cas(nom: "hors schéma : champ manquant", reponses: [.ok(#"{"autre":1}"#)], attendu: .failure(.invalidResponse), envois: 1),
        Cas(nom: "hors schéma : texte qui n'est pas du JSON", reponses: [.ok("Bien sûr !")], attendu: .failure(.invalidResponse), envois: 1),
        Cas(nom: "hors schéma : aucun bloc texte", reponses: [.ok(nil)], attendu: .failure(.invalidResponse), envois: 1),
        Cas(nom: "sortie tronquée (max_tokens)", reponses: [.ok(#"{"ok":tr"#, stop: "max_tokens")], attendu: .failure(.invalidResponse), envois: 1),
        Cas(nom: "corps illisible", reponses: [.http(200, [:], Data("<html>".utf8))], attendu: .failure(.invalidResponse), envois: 1),
        Cas(nom: "refus du modèle, catégorie lue avant le contenu", reponses: [.ok(#"{"ok":true}"#, stop: "refusal", categorie: "cyber")],
            attendu: .failure(.refusal(category: "cyber")), envois: 1),
        // Budget
        Cas(nom: "29 appels aujourd'hui : le 30e part", budget: depart(appels: 29), attendu: .success(true), envois: 1),
        Cas(nom: "30 appels aujourd'hui : refusé, rien ne part", budget: depart(appels: 30),
            attendu: .failure(.budgetReached(.daily)), envois: 0),
        Cas(nom: "30 appels hier : nouveau jour, accepté", budget: depart(appels: 30, le: le(11)), attendu: .success(true), envois: 1),
        Cas(nom: "30 appels à 23 h 30 la veille, il est 0 h 30 à Paris (23 h 30 UTC) : nouveau jour de l'appareil",
            budget: depart(appels: 30, le: le(11, 11, 23, 30)), now: le(12, 11, 0, 30), attendu: .success(true), envois: 1),
        Cas(nom: "30 appels à 0 h 10, il est 23 h 50 le même jour : refusé",
            budget: depart(appels: 30, le: le(12, 11, 0, 10)), now: le(12, 11, 23, 50), attendu: .failure(.budgetReached(.daily)), envois: 0),
        Cas(nom: "0,999999999 $ ce mois : accepté", budget: depart(depense: 999_999_999), attendu: .success(true), envois: 1),
        Cas(nom: "1 $ ce mois : refusé, rien ne part", budget: depart(depense: 1_000_000_000),
            attendu: .failure(.budgetReached(.monthly)), envois: 0),
        Cas(nom: "1 $ le mois dernier : nouveau mois, accepté", budget: depart(depense: 1_000_000_000, le: le(31, 10)),
            attendu: .success(true), envois: 1),
        Cas(nom: "429 au 30e appel : la nouvelle tentative serait le 31e, elle ne part pas",
            budget: depart(appels: 29), reponses: [.http(429, ["retry-after": "1"])],
            attendu: .failure(.budgetReached(.daily)), envois: 1, attentes: [.seconds(1)]),
    ]
}

@Suite struct ConseilClientTests {

    @Test(arguments: Cas.table)
    func tableDesCas(_ cas: Cas) async {
        let banc = Banc(cle: cas.cle, budget: cas.budget, reponses: cas.reponses)
        let resultat = await banc.demander(now: cas.now)
        #expect(resultat == cas.attendu)
        #expect(await banc.transport.requetes.count == cas.envois)
        #expect(await banc.attentes.durees == cas.attentes)
    }

    // MARK: Requête

    @Test func requete_httpsVersLApiMessages_enTetesExacts_haiku55EffortLowSchema() async throws {
        let banc = Banc()
        _ = await banc.demander()
        let r = try #require(await banc.transport.requetes.first)
        #expect(r.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(r.httpMethod == "POST")
        #expect(r.timeoutInterval == 20)
        #expect(r.allHTTPHeaderFields?.count == 3)
        #expect(r.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(r.value(forHTTPHeaderField: "x-api-key") == cleFactice)
        #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        let corps = try #require(JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: Any])
        #expect(Set(corps.keys) == ["model", "max_tokens", "system", "messages", "output_config"])   // ni temperature ni thinking
        #expect(corps["model"] as? String == "claude-haiku-5-5")
        let config = try #require(corps["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "low")
        let format = try #require(config["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect((format["schema"] as? [String: Any])?["additionalProperties"] as? Bool == false)
        let messages = try #require(corps["messages"] as? [[String: Any]])
        #expect(messages.last?["role"] as? String == "user")                                        // pas de préremplissage
    }

    @Test func httpsSeulement_versApiAnthropicCom() {
        #expect(ClaudeClient.endpoint.scheme == "https")
        #expect(ClaudeClient.endpoint.host == "api.anthropic.com")
    }

    @Test func cleColleeAvecRetourALaLigne_partNettoyee() async throws {
        let banc = Banc(cle: "  \(cleFactice)\n")
        _ = await banc.demander()
        #expect(try #require(await banc.transport.requetes.first).value(forHTTPHeaderField: "x-api-key") == cleFactice)
    }

    @Test func verificationDeLaCle_unPetitAppelQuiCompte() async throws {
        let banc = Banc()
        try await banc.client.checkKey(now: maintenant)
        #expect(banc.budget.load().at(maintenant, calendar: paris).callsToday == 1)
        let envoi = try #require(await banc.transport.requetes.first?.httpBody)
        let corps = try #require(JSONSerialization.jsonObject(with: envoi) as? [String: Any])
        #expect(corps["max_tokens"] as? Int == 512)
    }

    // MARK: Budget

    @Test func budget_depenseCompteeSurUsage() async {
        let banc = Banc(reponses: [.ok(entree: 3_500, sortie: 900)])
        _ = await banc.demander()
        let b = banc.budget.load()
        #expect(b.callsToday == 1)
        #expect(b.spentThisMonth == 3_500 * 100 + 900 * 500)          // 0,0008 $ (PLAN §6.3)
        #expect(b.spentDollars == 0.0008)
    }

    @Test func budget_refusDuModeleEtHorsSchema_sontFactures() async {
        let banc = Banc(reponses: [.ok(stop: "refusal", entree: 1_000, sortie: 10), .ok("pas du JSON", entree: 1_000, sortie: 10)])
        _ = await banc.demander()
        _ = await banc.demander()
        #expect(banc.budget.load().spentThisMonth == 2 * (1_000 * 100 + 10 * 500))
    }

    @Test func budget_usageIllisible_compteAuPire() async throws {
        let banc = Banc(reponses: [.http(200, [:], Data("{}".utf8))])
        _ = await banc.demander()
        let envoye = try #require(await banc.transport.requetes.first?.httpBody).count
        #expect(banc.budget.load().spentThisMonth == 4_096 * 500 + envoye * 100)
    }

    @Test func budget_tarifLongAuDelaDe100000Tokens() {
        #expect(Pricing.haiku55Cost(of: Usage(inputTokens: 100_000, outputTokens: 1_000)) == 100_000 * 100 + 1_000 * 500)
        #expect(Pricing.haiku55Cost(of: Usage(inputTokens: 100_001, outputTokens: 1_000)) == 100_001 * 500 + 1_000 * 2_500)
        // Le cache compte dans la taille de la requête.
        #expect(Pricing.haiku55Cost(of: Usage(inputTokens: 1, outputTokens: 0, cacheCreationInputTokens: 50_000, cacheReadInputTokens: 50_000))
                == 1 * 500 + 50_000 * 1_000 + 50_000 * 50)
    }

    @Test func budget_cacheLuEtEcrit() {
        #expect(Pricing.haiku55Cost(of: Usage(inputTokens: 10, outputTokens: 0, cacheCreationInputTokens: 1_000, cacheReadInputTokens: 2_000))
                == 10 * 100 + 1_000 * 200 + 2_000 * 10)
    }

    @Test func budget_lesEchecsComptentAussi_uneBoucleDe401SArreteA30() async {
        let banc = Banc(reponses: Array(repeating: .http(401), count: 40))
        for _ in 0..<35 { _ = await banc.demander() }
        #expect(await banc.transport.requetes.count == 30)
        #expect(await banc.demander() == .failure(.budgetReached(.daily)))
    }

    @Test func budget_appelsSimultanes_jamaisPlusDe30() async {
        let banc = Banc()
        await withTaskGroup(of: Void.self) { groupe in
            let client = banc.client
            for _ in 0..<40 {
                groupe.addTask { _ = try? await client.ask(system: "", prompt: "", schema: Banc.schema, as: Banc.Ok.self, now: maintenant) }
            }
        }
        #expect(await banc.transport.requetes.count == 30)
    }

    @Test func budget_deuxClientsSimultanes_surLeMemeBudget_jamaisPlusDe30() async {
        let defaults = UserDefaults(suiteName: "chantier-test-\(UUID().uuidString)")!
        let transport = FauxTransport()
        let clients = (0..<2).map { _ in
            ClaudeClient(keys: MemorySecretStore(cleFactice), budget: BudgetStore(defaults: defaults), transport: transport,
                         calendar: paris, sleep: { _ in })
        }
        await withTaskGroup(of: Void.self) { groupe in
            for i in 0..<40 {
                let client = clients[i % 2]
                groupe.addTask { _ = try? await client.ask(system: "", prompt: "", schema: Banc.schema, as: Banc.Ok.self, now: maintenant) }
            }
        }
        #expect(await transport.requetes.count == 30)
    }

    @Test func trousseauEnPanne_distinctDePasDeCle_rienNePart() async {
        struct CoffreEnPanne: SecretStore {
            func read() throws(KeyStoreError) -> String? { throw .keychain(status: -25308) }   // errSecInteractionNotAllowed
            func save(_ secret: String) throws(KeyStoreError) {}
            func delete() throws(KeyStoreError) {}
        }
        let transport = FauxTransport()
        let client = ClaudeClient(keys: CoffreEnPanne(), budget: BudgetStore(defaults: UserDefaults(suiteName: "chantier-test-\(UUID().uuidString)")!),
                                  transport: transport, calendar: paris, sleep: { _ in })
        await #expect(throws: ClaudeError.keychainUnavailable) { try await client.checkKey(now: maintenant) }
        #expect(await transport.requetes.isEmpty)
    }

    @Test func budget_nouveauMois_remetLaDepenseAZero_nouveauJour_lesAppels() {
        let b = depart(appels: 30, depense: 500_000_000, le: le(31, 10, 23, 0))
        let jourSuivant = b.at(le(1, 11, 9, 0), calendar: paris)
        #expect(jourSuivant.callsToday == 0 && jourSuivant.spentThisMonth == 0)
        let memeMois = depart(appels: 30, depense: 500_000_000, le: le(3)).at(le(4), calendar: paris)
        #expect(memeMois.callsToday == 0 && memeMois.spentThisMonth == 500_000_000)
    }

    @Test func budget_relitCeQuIlAEnregistre() {
        let d = UserDefaults(suiteName: "chantier-test-\(UUID().uuidString)")!
        let b = depart(appels: 7, depense: 12_345)
        BudgetStore(defaults: d).save(b)
        #expect(BudgetStore(defaults: d).load() == b)
    }

    // MARK: Clé

    @Test func cle_jamaisDansLesPreferences() async {
        let banc = Banc(reponses: [.ok(), .http(401), .http(429), .ok(), .panne(.timedOut)])
        for _ in 0..<5 { _ = await banc.demander() }
        for (cle, valeur) in banc.defaults.dictionaryRepresentation() {
            let texte = (valeur as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "\(valeur)"
            #expect(!texte.contains(cleFactice) && !cle.contains(cleFactice), "clé trouvée sous \(cle)")
        }
    }

    @Test func cle_absenteDeToutesLesDescriptionsDErreur() async {
        var erreurs: [ClaudeError] = [.noKey, .keychainUnavailable, .rateLimited, .offline, .timeout, .invalidResponse, .refusal(category: nil),
                                      .budgetReached(.daily), .budgetReached(.monthly)]
        for cas in Cas.table where cas.cle != nil {
            if case .failure(let e) = await Banc(cle: cas.cle, budget: cas.budget, reponses: cas.reponses).demander(now: cas.now) {
                erreurs.append(e)
            }
        }
        for e in erreurs {
            for texte in [String(describing: e), String(reflecting: e), e.localizedDescription, "\(e as any Error)"] {
                #expect(!texte.contains(cleFactice) && !texte.contains("cle-factice"))
            }
        }
    }

    @Test func trousseau_surCetAppareilSeulement_sansSynchronisation() {
        let a = KeychainStore.attributes(for: cleFactice)
        #expect(a[kSecClass as String] as! CFString == kSecClassGenericPassword)
        #expect(a[kSecAttrAccessible as String] as! CFString == kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        #expect(a[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(a[kSecValueData as String] as? Data == Data(cleFactice.utf8))
        #expect(KeychainStore.query[kSecAttrSynchronizable as String] as? Bool == false)   // lecture et effacement aussi
    }

    @Test func cle_colleeEstNettoyee_lesTextesQuiNeSontPasDesClesSontRefuses() {
        #expect(APIKey.normalized("  abc-DEF_123\n") == "abc-DEF_123")
        for mauvaise in ["", "   ", "abc def", "abc\ndef", "abc\r\nX-Autre: 1", "clé-accentuée", "abc\u{200B}def"] {
            #expect(APIKey.normalized(mauvaise) == nil, "« \(mauvaise) » accepté")
        }
    }

    @Test func cle_masquee_seulsLesQuatreDerniersCaracteres() {
        let m = APIKey.masked(cleFactice)
        #expect(m == "••••••••9876")
        #expect(!m.contains("cle-factice"))
        #expect(APIKey.masked("courte") == "••••••••")
    }

    @Test func cle_effacee_plusAucunAppel() async throws {
        let cles = MemorySecretStore(cleFactice)
        try cles.delete()
        #expect(try cles.read() == nil)
        let transport = FauxTransport()
        let client = ClaudeClient(keys: cles, budget: BudgetStore(defaults: UserDefaults(suiteName: "chantier-test-\(UUID().uuidString)")!),
                                  transport: transport, calendar: paris, sleep: { _ in })
        await #expect(throws: ClaudeError.noKey) { try await client.checkKey(now: maintenant) }
        #expect(await transport.requetes.isEmpty)
        #expect(throws: KeyStoreError.invalidKey) { try cles.save("  ") }
    }

    // MARK: Journaux

    /// Aucun `print`, `NSLog`, `os_log` ni `Logger` dans le conseiller et sa section des Réglages.
    @Test func aucunJournal_niRequeteNiReponseNiCle() throws {
        let ici = URL(filePath: #filePath).deletingLastPathComponent()
        let dossiers = [ici.appending(path: "../../Sources/ChantierKit/Conseil"), ici.appending(path: "../../../../App/Ecrans/Reglages")]
        var lus = 0
        for dossier in dossiers {
            for nom in try FileManager.default.contentsOfDirectory(atPath: dossier.path(percentEncoded: false)) where nom.hasSuffix(".swift") {
                let texte = try String(contentsOf: dossier.appending(path: nom), encoding: .utf8)
                lus += 1
                for interdit in ["print(", "debugPrint(", "dump(", "NSLog(", "os_log(", "Logger(", "import os"] {
                    #expect(!texte.contains(interdit), "\(interdit) dans \(nom)")
                }
            }
        }
        #expect(lus >= 4)
    }
}
