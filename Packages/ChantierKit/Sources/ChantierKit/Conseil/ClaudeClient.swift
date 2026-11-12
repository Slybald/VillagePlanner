import Foundation

// Le client Claude (PLAN §6.3, skill `claude-api`, fichiers cURL) : pas de SDK officiel pour Swift, donc une requête
// HTTPS directe à l'API Messages. Haiku 5.5, effort `low`, sortie structurée par schéma, pas de préremplissage.
// Aucun texte de requête ou de réponse n'est journalisé, et la clé ne figure dans aucune erreur.

/// Ce qui envoie la requête : `URLSession` dans l'app, une fausse réponse dans les tests (jamais le réseau).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

/// `URLSession` éphémère : ni cache disque, ni cookies, délai total borné, aucune redirection suivie
/// (la clé ne part que vers `api.anthropic.com`).
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: Duration = ClaudeClient.timeout) {
        let config = URLSessionConfiguration.ephemeral
        let seconds = Double(timeout.components.seconds)
        config.timeoutIntervalForRequest = seconds
        config.timeoutIntervalForResource = seconds
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: config)
    }

    /// Au-delà, la réponse n'est pas lue (une réponse attendue tient en quelques kilo-octets).
    public static let responseLimit = 1_000_000

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: SansRedirection())
        return (try await Self.collect(bytes, limit: Self.responseLimit), response)
    }
}

/// Le corps de la réponse dépasse la limite du transport.
public struct ResponseTooLarge: Error, Equatable {
    public init() {}
}

extension URLSessionTransport {
    static func collect<S: AsyncSequence>(_ bytes: S, limit: Int) async throws -> Data where S.Element == UInt8 {
        var data = Data()
        for try await b in bytes {
            guard data.count < limit else { throw ResponseTooLarge() }
            data.append(b)
        }
        return data
    }
}

private final class SansRedirection: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

/// Pourquoi un appel n'a pas donné de réponse. Chaque cas est distinct et testé ; aucun ne contient la clé.
public enum ClaudeError: Error, Equatable, Sendable {
    /// Aucune clé dans le Trousseau.
    case noKey
    /// Le Trousseau ne répond pas (appareil verrouillé, par exemple) : la clé est peut-être là.
    case keychainUnavailable
    /// 401 : la clé est refusée.
    case unauthorized
    /// 429, encore après la seule nouvelle tentative (ou un délai demandé trop long).
    case rateLimited
    /// 5xx (dont 529, surcharge).
    case serviceUnavailable(status: Int)
    /// Un autre refus de la requête (400, 402, 403, 404, 413…).
    case rejected(status: Int)
    /// Pas de réseau, hôte injoignable.
    case offline
    /// Pas de réponse dans le délai (20 s).
    case timeout
    /// Réponse illisible, tronquée ou hors schéma.
    case invalidResponse
    /// Le modèle décline (`stop_reason: "refusal"`), avec la catégorie de `stop_details`.
    case refusal(category: String?)
    /// Plafond atteint : l'appel n'est pas parti.
    case budgetReached(BudgetLimit)
}

public actor ClaudeClient {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let model = "claude-haiku-5-5"
    public static let apiVersion = "2026-10-21"
    public static let effort = "low"
    public static let timeout: Duration = .seconds(20)
    /// Au-delà, on n'attend pas pour la nouvelle tentative : l'écran passe à la consigne du moteur.
    public static let longestRetryWait: Duration = .seconds(20)

    private let keys: any SecretStore
    private let budgetStore: BudgetStore
    private let transport: any HTTPTransport
    private let calendar: Calendar
    private let timeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(keys: any SecretStore, budget: BudgetStore, transport: (any HTTPTransport)? = nil,
                calendar: Calendar, timeout: Duration = ClaudeClient.timeout,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.keys = keys
        self.budgetStore = budget
        self.transport = transport ?? URLSessionTransport(timeout: timeout)
        self.calendar = calendar
        self.timeout = timeout
        self.sleep = sleep
    }

    /// Un appel : `system` et `prompt` en entrée, un objet JSON conforme à `schema` (texte JSON) en sortie, décodé en `Output`.
    /// Le plafond est vérifié avant chaque envoi, nouvelle tentative comprise ; chaque envoi compte pour un appel.
    public func ask<Output: Decodable>(system: String, prompt: String, schema: String, as: Output.Type,
                                       maxTokens: Int = 4_096, now: Date) async throws(ClaudeError) -> Output {
        let stored: String?
        do { stored = try keys.read() } catch { throw .keychainUnavailable }
        guard let stored, let key = APIKey.normalized(stored) else { throw .noKey }
        let body = try Self.body(system: system, prompt: prompt, schema: schema, maxTokens: maxTokens)
        let request = Self.request(key: key, body: body, timeout: timeout)
        let worst = Self.worstCase(maxTokens: maxTokens, bodyBytes: body.count)

        for attempt in 1...2 {
            var limit = budgetStore.reserveCall(at: now, calendar: calendar, worstCase: worst)
            // Bloqué par une date plus récente que l'horloge : peut-être une horloge mise dans le futur puis remise à l'heure.
            if limit != nil, let latest = budgetStore.load().latest, latest > now.addingTimeInterval(Budget.clockTolerance),
               await recalerHorloge() {
                limit = budgetStore.reserveCall(at: now, calendar: calendar, worstCase: worst)
            }
            if let limit { throw .budgetReached(limit) }
            let data: Data, response: URLResponse
            do { (data, response) = try await transport.send(request) } catch {
                // Délai dépassé, connexion perdue, réponse trop grosse : la requête a peut-être été traitée, le pire reste compté.
                if !Self.mayHaveBeenBilled(error) { settle(worst, actual: 0, now: now) }
                throw Self.transportError(error)
            }
            guard let http = response as? HTTPURLResponse else { throw .invalidResponse }
            if let date = Self.serverDate(http) { budgetStore.correctClock(serverDate: date, calendar: calendar) }
            if http.statusCode != 200 { settle(worst, actual: 0, now: now) }    // une erreur HTTP n'est pas facturée
            switch http.statusCode {
            case 200: return try read(data, as: Output.self, reserved: worst, now: now)
            case 401: throw .unauthorized
            case 429:
                guard attempt == 1, let wait = Self.retryDelay(http), wait <= Self.longestRetryWait else { throw .rateLimited }
                do { try await sleep(wait) } catch { throw .offline }
            case 500...599: throw .serviceUnavailable(status: http.statusCode)
            default: throw .rejected(status: http.statusCode)
            }
        }
        throw .rateLimited
    }

    /// La date du service, lue dans l'en-tête `Date` d'une requête sans clé (ni coût ni appel compté) ; vrai si le budget a été recalé.
    private func recalerHorloge() async -> Bool {
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/")!, cachePolicy: .reloadIgnoringLocalCacheData,
                           timeoutInterval: Double(timeout.components.seconds))
        r.httpMethod = "HEAD"
        guard let (_, response) = try? await transport.send(r), let http = response as? HTTPURLResponse,
              let date = Self.serverDate(http) else { return false }
        return budgetStore.correctClock(serverDate: date, calendar: calendar)
    }

    /// L'en-tête `Date` (protégé par TLS), au format HTTP.
    static func serverDate(_ response: HTTPURLResponse) -> Date? {
        guard let texte = response.value(forHTTPHeaderField: "Date") else { return nil }
        let f = DateFormatter()                              // `Date.HTTPFormatStyle` demande macOS 26
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .gmt
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: texte)
    }

    /// Le plus petit appel utile : vérifie la clé depuis les Réglages (une fraction de centième de centime).
    public func checkKey(now: Date) async throws(ClaudeError) {
        struct Reponse: Decodable { let ok: Bool }
        let schema = #"{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"],"additionalProperties":false}"#
        _ = try await ask(system: "Réponds au format demandé.", prompt: "Réponds ok à vrai.", schema: schema,
                          as: Reponse.self, maxTokens: 1_024, now: now)   // la réflexion compte dans max_tokens
    }

    // MARK: Budget

    private func settle(_ reserved: Int, actual: Int, now: Date) {
        budgetStore.settle(reserved: reserved, actual: actual, at: now, calendar: calendar)
    }

    /// Le pire coût d'un appel : toute la sortie permise, un token par octet envoyé, au tarif long si la requête l'est.
    static func worstCase(maxTokens: Int, bodyBytes: Int) -> Int {
        let p = bodyBytes > Pricing.longPromptThreshold ? Pricing.haiku55Long : Pricing.haiku55
        return maxTokens * p.output + bodyBytes * p.input
    }

    // MARK: Requête

    /// Le corps de la requête. Pas de `thinking` (adaptatif par défaut sur Haiku 5.5), ni `temperature` ni préremplissage :
    /// le dernier message est celui de l'utilisateur.
    static func body(system: String, prompt: String, schema: String, maxTokens: Int) throws(ClaudeError) -> Data {
        guard let schemaObject = try? JSONSerialization.jsonObject(with: Data(schema.utf8)), schemaObject is [String: Any] else {
            assertionFailure("schéma JSON invalide")
            throw .rejected(status: 400)
        }
        let json: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": ["effort": effort, "format": ["type": "json_schema", "schema": schemaObject]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { throw .rejected(status: 400) }
        return data
    }

    static func request(key: String, body: Data, timeout: Duration) -> URLRequest {
        var r = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData,
                           timeoutInterval: Double(timeout.components.seconds))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        r.httpBody = body
        return r
    }

    /// `retry-after` en secondes ; absent, une seconde.
    static func retryDelay(_ response: HTTPURLResponse) -> Duration? {
        guard let text = response.value(forHTTPHeaderField: "retry-after") else { return .seconds(1) }
        guard let s = Double(text.trimmingCharacters(in: .whitespaces)), s.isFinite, s <= 3_600 else { return nil }   // borné avant la conversion en entier
        return .milliseconds(Int((max(0, s) * 1000).rounded(.up)))
    }

    static func transportError(_ error: any Error) -> ClaudeError {
        if error is ResponseTooLarge { return .invalidResponse }
        if error is CancellationError { return .timeout }
        return [.timedOut, .cancelled].contains((error as? URLError)?.code) ? .timeout : .offline
    }

    static func mayHaveBeenBilled(_ error: any Error) -> Bool {
        error is ResponseTooLarge || error is CancellationError
            || [.timedOut, .networkConnectionLost, .cancelled].contains((error as? URLError)?.code)
    }

    // MARK: Réponse

    private struct Envelope: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        struct StopDetails: Decodable { let category: String? }
        let content: [Block]
        let stopReason: String?
        let stopDetails: StopDetails?
        let usage: Usage
        enum CodingKeys: String, CodingKey { case content, usage, stopReason = "stop_reason", stopDetails = "stop_details" }
    }

    /// `stop_reason` est lu avant le contenu. La dépense est comptée sur `usage`, même quand la réponse est refusée ;
    /// sans `usage` lisible (ou hors bornes), la réservation au pire reste comptée.
    private func read<Output: Decodable>(_ data: Data, as: Output.Type, reserved: Int, now: Date) throws(ClaudeError) -> Output {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw .invalidResponse }
        settle(reserved, actual: Pricing.haiku55Cost(of: envelope.usage), now: now)
        switch envelope.stopReason {
        case "end_turn": break
        case "refusal": throw .refusal(category: envelope.stopDetails?.category)
        default: throw .invalidResponse                    // max_tokens : sortie tronquée ; autre : inattendu
        }
        // Les blocs se lisent par type : Haiku 5.5 peut commencer par des blocs `thinking`.
        guard let text = envelope.content.first(where: { $0.type == "text" })?.text,
              let output = try? JSONDecoder().decode(Output.self, from: Data(text.utf8)) else { throw .invalidResponse }
        return output
    }
}
