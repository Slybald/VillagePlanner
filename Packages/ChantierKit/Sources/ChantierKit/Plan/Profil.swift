import Foundation

/// Une réduction en cours (événement, Pass Or) : un pourcentage sur le coût et la durée, jusqu'à une date.
public struct Reduction: Sendable, Equatable, Codable {
    /// 0 à 100 ; hors de ces bornes, la valeur est ramenée dedans à l'usage.
    public let percent: Int
    /// La réduction vaut pour une amélioration lancée avant cette date ; à cette date, elle est finie.
    public let endsAt: Date

    public init(percent: Int, endsAt: Date) {
        self.percent = percent
        self.endsAt = endsAt
    }

    /// Pourcentage appliqué à `date` : 0 une fois la fin atteinte.
    public func percent(at date: Date) -> Int { date < endsAt ? min(max(percent, 0), 100) : 0 }
}

/// Les heures où le joueur ne lance rien (S4), de `start` heure à `end` heure dans `timeZone`.
/// La plage peut passer minuit (23 h → 7 h) ; `start == end` : aucune plage.
public struct QuietHours: Sendable, Equatable, Codable {
    public var start: Int
    public var end: Int
    public var timeZone: TimeZone

    /// 23 h → 7 h, heure de Paris (l'app passera le fuseau de l'appareil).
    public static let `default` = QuietHours(start: 23, end: 7, timeZone: TimeZone(identifier: "Europe/Paris")!)

    public init(start: Int, end: Int, timeZone: TimeZone) {
        self.start = start
        self.end = end
        self.timeZone = timeZone
    }

    /// `date` hors plage : `date` ; dans la plage : sa fin.
    public func release(_ date: Date) -> Date {
        let (s, e) = ((start % 24 + 24) % 24, (end % 24 + 24) % 24)
        guard s != e else { return date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let h = calendar.component(.hour, from: date)
        guard s < e ? (h >= s && h < e) : (h >= s || h < e) else { return date }
        return calendar.nextDate(after: date, matching: DateComponents(hour: e, minute: 0, second: 0),
                                 matchingPolicy: .nextTime) ?? date
    }
}

/// Le profil de jeu : orientation, héros, épingles, heures sans jeu, réductions.
public struct Profile: Sendable, Equatable, Codable {
    /// Ouvriers : bâtiments, pièges, murs, héros.
    public var builderReduction: Reduction?
    /// Laboratoire seulement (PLAN §5.2) : ni la Maison des familiers ni la forge.
    public var laboratoryReduction: Reduction?
    public var orientation: Orientation
    /// Héros en amélioration en même temps ; nil : pas de limite.
    public var heroLimit: Int?
    /// Identifiants des types épinglés (« je veux ça d'abord ») : en tête de leur poste.
    public var pinned: Set<Int>
    public var nextTownHallThreshold: TownHallThreshold
    /// Heures sans jeu (S4) ; nil : on lance à toute heure.
    public var quietHours: QuietHours?

    public init(builderReduction: Reduction? = nil, laboratoryReduction: Reduction? = nil,
                orientation: Orientation = .balanced, heroLimit: Int? = nil, pinned: Set<Int> = [],
                nextTownHallThreshold: TownHallThreshold = .complete, quietHours: QuietHours? = .default) {
        self.builderReduction = builderReduction
        self.laboratoryReduction = laboratoryReduction
        self.orientation = orientation
        self.heroLimit = heroLimit
        self.pinned = pinned
        self.nextTownHallThreshold = nextTownHallThreshold
        self.quietHours = quietHours
    }

    /// Pourcentage de réduction d'une amélioration lancée à `date` par ce poste.
    public func reductionPercent(for worker: WorkerKind, at date: Date) -> Int {
        switch worker {
        case .builder: builderReduction?.percent(at: date) ?? 0
        case .laboratory: laboratoryReduction?.percent(at: date) ?? 0
        case .petHouse, .blacksmith: 0
        }
    }

    /// Valeur après réduction, arrondie vers le bas.
    static func reduced(_ value: Int, byPercent percent: Int) -> Int { value * (100 - percent) / 100 }
}
