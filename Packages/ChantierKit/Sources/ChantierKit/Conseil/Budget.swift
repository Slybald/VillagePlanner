import Foundation

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
    }

    /// Toute la requête : c'est elle qui choisit le tarif (au-delà de 100 000 tokens, le tarif long).
    public var promptTokens: Int { inputTokens + cacheCreationInputTokens + cacheReadInputTokens }
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
        return usage.inputTokens * p.input + usage.outputTokens * p.output
            + usage.cacheReadInputTokens * p.cacheRead + usage.cacheCreationInputTokens * p.cacheWrite
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
    public private(set) var spentThisMonth = 0               // nanodollars

    public init() {}

    /// Le budget tel qu'il se lit à `now`.
    public func at(_ now: Date, calendar: Calendar) -> Budget {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let m = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        let d = m + String(format: "-%02d", c.day ?? 0)
        var b = self
        if b.month != m { b.month = m; b.spentThisMonth = 0 }
        if b.day != d { b.day = d; b.callsToday = 0 }
        return b
    }

    /// La barrière atteinte à `now`, ou nil si un appel peut partir.
    public func limitReached(at now: Date, calendar: Calendar) -> BudgetLimit? {
        let b = at(now, calendar: calendar)
        if b.spentThisMonth >= Self.monthlyLimit { return .monthly }
        if b.callsToday >= Self.callsPerDay { return .daily }
        return nil
    }

    public mutating func recordCall(at now: Date, calendar: Calendar) {
        self = at(now, calendar: calendar)
        callsToday += 1
    }

    public mutating func recordCost(_ nanodollars: Int, at now: Date, calendar: Calendar) {
        self = at(now, calendar: calendar)
        spentThisMonth += max(0, nanodollars)
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
}
