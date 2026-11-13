import Foundation

// Le client de l'API officielle (décision D8) : `GET /players/{tag}` par le relais de RoyaleAPI, avec une clé dédiée.
// HTTPS vers un hôte fixe, jamais ailleurs ; aucune redirection suivie. Aucun texte de requête ou de réponse n'est
// journalisé, et la clé ne figure dans aucune erreur. Même transport que le client Claude (T19), donc même faux transport en test.

/// Pourquoi une lecture n'a pas donné de profil. Chaque cas est distinct et testé ; aucun ne contient la clé.
public enum JoueurError: Error, Equatable, Sendable {
    /// Aucune clé dans le Trousseau.
    case noKey
    /// Le Trousseau ne répond pas (appareil verrouillé, par exemple) : la clé est peut-être là.
    case keychainUnavailable
    /// Pas de photo, donc pas de tag.
    case noTag
    /// Le tag n'a pas la forme d'un tag de joueur.
    case invalidTag
    /// Trop tôt : la lecture n'est pas partie.
    case tooSoon(Pause)
    /// 403 : clé refusée, ou clé qui ne déclare pas l'adresse du relais.
    case rejectedKey
    /// 404 : aucun joueur avec ce tag.
    case notFound
    /// 429 : trop de requêtes (pas de nouvelle tentative).
    case rateLimited
    /// 503 : maintenance du jeu.
    case maintenance
    /// Un autre 5xx (le relais ou l'API en panne).
    case serverError(status: Int)
    /// Un autre refus (400, 401, 410…).
    case rejected(status: Int)
    /// Pas de réseau, hôte injoignable.
    case offline
    /// Pas de réponse dans le délai (20 s).
    case timeout
    /// Réponse illisible, trop grosse ou hors schéma (pas un objet JSON portant un `tag`).
    case invalidResponse

    /// Ce qui a arrêté la lecture avant l'envoi.
    public enum Pause: Equatable, Sendable {
        /// Une lecture est déjà partie depuis l'ouverture de l'app.
        case thisLaunch
        /// La dernière lecture date de moins d'une heure ; la prochaine est permise à cette date.
        case hourly(until: Date)
    }
}

public actor ClientJoueur {
    /// Le seul hôte auquel la clé est envoyée.
    public static let host = "cocproxy.royaleapi.dev"
    public static let timeout: Duration = .seconds(20)

    private let keys: any SecretStore
    private let cadence: CadenceStore
    private let transport: any HTTPTransport
    private let timeout: Duration
    /// Une lecture au plus par ouverture de l'app : une instance vit autant que le processus (une instance neuve = une nouvelle ouverture).
    private var luCetteOuverture = false

    public init(keys: any SecretStore, cadence: CadenceStore, transport: (any HTTPTransport)? = nil,
                timeout: Duration = ClientJoueur.timeout) {
        self.keys = keys
        self.cadence = cadence
        self.transport = transport ?? URLSessionTransport(timeout: timeout)
        self.timeout = timeout
    }

    /// Le profil du joueur `tag` (la forme `#2PP` ; il vient de la dernière photo). Au plus une lecture par ouverture
    /// de l'app et une par heure : sinon `.tooSoon`, sans appel. Une lecture refusée par le service compte quand même ;
    /// une lecture qui n'a pas pu partir (pas de réseau) ne compte pas.
    public func lire(tag: String?, now: Date) async throws(JoueurError) -> ProfilJoueur {
        let stored: String?
        do { stored = try keys.read() } catch { throw .keychainUnavailable }
        guard let stored, let key = APIKey.normalized(stored) else { throw .noKey }
        guard let tag else { throw .noTag }
        guard let url = Self.url(forTag: tag) else { throw .invalidTag }
        if luCetteOuverture { throw .tooSoon(.thisLaunch) }

        let avant = cadence.load()
        var jusqua = cadence.reserver(at: now)
        // Bloqué par une date plus récente que l'horloge : peut-être une horloge mise dans le futur puis remise à l'heure.
        if jusqua != nil, let vue = avant.plusRecent, vue > now.addingTimeInterval(Budget.clockTolerance), await recalerHorloge() {
            jusqua = cadence.reserver(at: now)
        }
        if let jusqua { throw .tooSoon(.hourly(until: jusqua)) }
        luCetteOuverture = true

        let data: Data, response: URLResponse
        do { (data, response) = try await transport.send(Self.request(url: url, key: key, timeout: timeout)) } catch {
            if Self.neSortPas(error) { luCetteOuverture = false; cadence.annuler(avant) }
            throw Self.transportError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw .invalidResponse }
        if let date = ClaudeClient.serverDate(http) { cadence.recaler(serverDate: date) }
        switch http.statusCode {
        case 200:
            guard let profil = ProfilJoueur.decode(data) else { throw .invalidResponse }
            return profil
        case 403: throw .rejectedKey
        case 404: throw .notFound
        case 429: throw .rateLimited
        case 503: throw .maintenance
        case 500...599: throw .serverError(status: http.statusCode)
        default: throw .rejected(status: http.statusCode)
        }
    }

    /// La date du service, lue dans l'en-tête `Date` d'une requête sans clé vers le même hôte ; vrai si la cadence a été recalée.
    private func recalerHorloge() async -> Bool {
        var r = URLRequest(url: URL(string: "https://\(Self.host)/")!, cachePolicy: .reloadIgnoringLocalCacheData,
                           timeoutInterval: Double(timeout.components.seconds))
        r.httpMethod = "HEAD"
        guard let (_, response) = try? await transport.send(r), let http = response as? HTTPURLResponse,
              let date = ClaudeClient.serverDate(http) else { return false }
        return cadence.recaler(serverDate: date)
    }

    // MARK: Requête

    /// Les caractères d'un tag de joueur.
    private static let alphabetTag = Set("0289PYLQGRJCUV")

    /// « #2pp », « 2PP » ou « #2PP » donnent `#2PP` (le jeu lit la lettre O comme un zéro) ; nil si ce n'est pas un tag.
    public static func normalizedTag(_ texte: String) -> String? {
        var corps = Substring(texte.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        if corps.first == "#" { corps = corps.dropFirst() }
        let tag = corps.replacingOccurrences(of: "O", with: "0")
        guard (1...15).contains(tag.count), tag.allSatisfy(alphabetTag.contains) else { return nil }
        return "#" + tag
    }

    /// `https://cocproxy.royaleapi.dev/v1/players/%232PP` : le dièse du tag est encodé (sinon il ouvre un fragment et le tag est perdu).
    static func url(forTag tag: String) -> URL? {
        guard let normalise = normalizedTag(tag) else { return nil }
        return URL(string: "https://\(host)/v1/players/%23\(normalise.dropFirst())")
    }

    static func request(url: URL, key: String, timeout: Duration) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Double(timeout.components.seconds))
        r.httpMethod = "GET"
        r.setValue("application/json", forHTTPHeaderField: "accept")
        r.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        return r
    }

    static func transportError(_ error: any Error) -> JoueurError {
        if error is ResponseTooLarge { return .invalidResponse }
        if error is CancellationError { return .timeout }
        return [.timedOut, .cancelled].contains((error as? URLError)?.code) ? .timeout : .offline
    }

    /// La requête n'a pas pu atteindre le relais : elle ne compte pas.
    static func neSortPas(_ error: any Error) -> Bool {
        [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed,
         .internationalRoamingOff].contains((error as? URLError)?.code)
    }
}
