import Foundation
import Synchronization

// Le plafond du conseiller (PLAN §6.3) : 30 appels par jour et 1 $ par mois, au calendrier de l'appareil.
// Les montants sont des entiers en nanodollars (1 $ = 10^9) : l'addition des dépenses reste exacte.

/// Le champ `usage` d'une réponse de l'API Messages : les tokens réellement facturés.
public struct Usage: Sendable, Equatable, Decodable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheCreationInputTokens: Int
    public var cacheReadInputTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cacheCreationInputTokens: Int = 0, cacheReadInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens", cacheReadInputTokens = "cache_read_input_tokens"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try c.decode(Int.self, forKey: .inputTokens)
        outputTokens = try c.decode(Int.self, forKey: .outputTokens)
        cacheCreationInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens) ?? 0
        cacheReadInputTokens = try c.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens) ?? 0
        // Une valeur hors bornes rend la réponse illisible : elle est alors comptée au pire.
        guard [inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens].allSatisfy({ (0...Self.maxTokens).contains($0) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "usage hors bornes"))
        }
    }

    /// Bien au-delà de ce qu'une requête peut compter (1 M de contexte, 128 K en sortie).
    public static let maxTokens = 10_000_000

    /// Toute la requête : c'est elle qui choisit le tarif (au-delà de 100 000 tokens, le tarif long).
    public var promptTokens: Int { Self.borne(inputTokens) + Self.borne(cacheCreationInputTokens) + Self.borne(cacheReadInputTokens) }

    /// Chaque champ ramené à 0…10 000 000 : le calcul du coût ne déborde jamais.
    static func borne(_ n: Int) -> Int { min(max(n, 0), maxTokens) }
}

/// Prix par token, en nanodollars.
public struct Pricing: Sendable, Equatable {
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int

    /// Claude Haiku 5.5, prix du 2026-11-03 (skill `claude-api`) : 0,10 $ / 0,50 $ par million de tokens
    /// en entrée / sortie pour une requête de 100 000 tokens au plus, 0,50 $ / 2,50 $ au-delà. Lecture du cache :
    /// 0,1 × l'entrée. Écriture du cache comptée au tarif d'une heure (2 × l'entrée), le plus cher des deux.
    public static let haiku55 = Pricing(input: 100, output: 500, cacheRead: 10, cacheWrite: 200)
    public static let haiku55Long = Pricing(input: 500, output: 2_500, cacheRead: 50, cacheWrite: 1_000)
    public static let longPromptThreshold = 100_000

    /// Le coût d'une réponse de Haiku 5.5, en nanodollars.
    public static func haiku55Cost(of usage: Usage) -> Int {
        let p = usage.promptTokens > longPromptThreshold ? haiku55Long : haiku55
        return Usage.borne(usage.inputTokens) * p.input + Usage.borne(usage.outputTokens) * p.output
            + Usage.borne(usage.cacheReadInputTokens) * p.cacheRead + Usage.borne(usage.cacheCreationInputTokens) * p.cacheWrite
    }
}

/// La barrière qui arrête les appels.
public enum BudgetLimit: Sendable, Equatable { case daily, monthly }

/// Le compteur du jour et la dépense du mois. Un nouveau jour remet les appels à zéro, un nouveau mois la dépense.
public struct Budget: Codable, Sendable, Equatable {
    public static let callsPerDay = 30
    public static let monthlyLimit = 1_000_000_000           // 1 $

    public private(set) var day = ""                         // « 2026-11-12 », au calendrier de l'appareil
    public private(set) var callsToday = 0
    public private(set) var month = ""                       // « 2026-11 »
    public private(set) var spentThisMonth = 0               // nanodollars, réservations en cours comprises
    /// La date la plus récente déjà vue : reculer l'horloge de l'appareil ne remet rien à zéro.
    public private(set) var latest: Date?

    public init() {}

    /// Le budget tel qu'il se lit à `now`, ou à la date la plus récente déjà vue si l'horloge a reculé.
    public func at(_ now: Date, calendar: Calendar) -> Budget {
        let t = max(now, latest ?? now)
        let (d, m) = Self.keys(t, calendar)
        var b = self
        // Seulement en avançant : changer de fuseau au même instant ne remet rien à zéro.
        if m > b.month { b.month = m; b.spentThisMonth = 0 }
        if d > b.day { b.day = d; b.callsToday = 0 }
        b.latest = t
        return b
    }

    /// « 2026-11-12 » et « 2026-11 » : des chaînes de largeur fixe, qui se comparent dans l'ordre du temps.
    static func keys(_ date: Date, _ calendar: Calendar) -> (day: String, month: String) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let m = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        return (m + String(format: "-%02d", c.day ?? 0), m)
    }

    /// L'appareil avait une date en avance de plus d'un jour sur celle du service : on revient à celle du service.
    /// Les appels et la dépense déjà comptés restent, rangés sous le jour et le mois du service.
    mutating func correctClock(serverDate: Date, calendar: Calendar) -> Bool {
        guard let latest, latest > serverDate.addingTimeInterval(Self.clockTolerance) else { return false }
        self.latest = serverDate
        let (d, m) = Self.keys(serverDate, calendar)
        day = min(day, d)
        month = min(month, m)
        return true
    }

    /// L'écart toléré entre l'horloge de l'appareil et celle du service.
    public static let clockTolerance: TimeInterval = 86_400

    /// La barrière atteinte à `now` pour un appel qui peut coûter jusqu'à `cost`, ou nil s'il peut partir.
    public func limitReached(at now: Date, calendar: Calendar, cost: Int = 0) -> BudgetLimit? {
        let b = at(now, calendar: calendar)
        if b.spentThisMonth >= Self.monthlyLimit || b.spentThisMonth > Self.monthlyLimit - max(0, cost) { return .monthly }
        if b.callsToday >= Self.callsPerDay { return .daily }
        return nil
    }

    public mutating func recordCall(at now: Date, calendar: Calendar) {
        self = at(now, calendar: calendar)
        callsToday += 1
    }

    public mutating func recordCost(_ nanodollars: Int, at now: Date, calendar: Calendar) {
        self = at(now, calendar: calendar)
        adjustSpending(by: max(0, nanodollars))
    }

    /// Ajoute (ou rend) un montant, sans jamais passer sous zéro ni déborder.
    mutating func adjustSpending(by delta: Int) {
        let (somme, deborde) = spentThisMonth.addingReportingOverflow(delta)
        spentThisMonth = deborde ? (delta > 0 ? Int.max : 0) : max(0, somme)
    }

    /// La dépense du mois en dollars, pour l'affichage.
    public var spentDollars: Double { Double(spentThisMonth) / 1e9 }
}

/// L'enregistrement du budget : un blob JSON dans les préférences (des compteurs, aucun secret).
/// shortcut: un blob abîmé redonne un budget neuf ; la limite de la Console reste la barrière de dernier recours.
public struct BudgetStore: @unchecked Sendable {   // UserDefaults est sûr entre fils
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "budget-conseiller") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> Budget {
        guard let data = defaults.data(forKey: key) else { return Budget() }
        return (try? JSONDecoder().decode(Budget.self, from: data)) ?? Budget()
    }

    public func save(_ budget: Budget) {
        guard let data = try? JSONEncoder().encode(budget) else { return }
        defaults.set(data, forKey: key)
    }

    /// Un verrou pour tout le processus : deux clients (Réglages, conseiller) ne peuvent pas réserver le même dernier appel.
    private static let verrou = Mutex(())

    /// Réserve un appel et son pire coût : la barrière atteinte, ou nil si l'appel peut partir (il est alors compté,
    /// et `worstCase` ajouté à la dépense jusqu'à ce que `settle` le remplace par le coût réel).
    public func reserveCall(at now: Date, calendar: Calendar, worstCase: Int) -> BudgetLimit? {
        Self.verrou.withLock { _ in
            var b = load()
            if let limit = b.limitReached(at: now, calendar: calendar, cost: worstCase) { return limit }
            b.recordCall(at: now, calendar: calendar)
            b.recordCost(worstCase, at: now, calendar: calendar)
            save(b)
            return nil
        }
    }

    /// Recale la date sur celle du service ; vrai si elle a changé.
    @discardableResult
    public func correctClock(serverDate: Date, calendar: Calendar) -> Bool {
        Self.verrou.withLock { _ in
            var b = load()
            guard b.correctClock(serverDate: serverDate, calendar: calendar) else { return false }
            save(b)
            return true
        }
    }

    /// Remplace la réservation par le coût réel (0 si le service n'a rien facturé).
    /// shortcut: si l'app s'arrête entre la réservation et ce règlement, le pire coût reste compté (environ 0,0035 $ pour une requête de 14 Ko).
    public func settle(reserved: Int, actual: Int, at now: Date, calendar: Calendar) {
        Self.verrou.withLock { _ in
            var b = load().at(now, calendar: calendar)
            b.adjustSpending(by: max(0, actual) - reserved)
            save(b)
        }
    }
}
