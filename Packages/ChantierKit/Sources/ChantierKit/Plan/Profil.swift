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

/// Le profil de jeu : orientation, héros, épingles, heures sans jeu, réductions.
/// T10 ne porte que les réductions ; les autres réglages arrivent avec T12, T13 et T17.
public struct Profile: Sendable, Equatable, Codable {
    /// Ouvriers : bâtiments, pièges, murs, héros.
    public var builderReduction: Reduction?
    /// Laboratoire seulement (PLAN §5.2) : ni la Maison des familiers ni la forge.
    public var laboratoryReduction: Reduction?

    public init(builderReduction: Reduction? = nil, laboratoryReduction: Reduction? = nil) {
        self.builderReduction = builderReduction
        self.laboratoryReduction = laboratoryReduction
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
