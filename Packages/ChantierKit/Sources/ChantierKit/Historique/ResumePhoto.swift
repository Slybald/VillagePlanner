import Foundation

// L'index de l'historique (PLAN §4.5) : un résumé par photo, pour tracer les courbes sans tout relire.
// C'est un cache : les photos restent la source de vérité, l'index se reconstruit à l'identique.

/// Ce dont le calcul d'un résumé dépend, hors de la photo : la référence, les conseils et le profil.
/// Quand l'un change, tous les résumés sont recalculés.
public struct HistoryContext: Sendable {
    public let reference: ReferenceData
    public let advice: AdviceData
    public let profile: Profile

    public init(reference: ReferenceData, advice: AdviceData = AdviceData(), profile: Profile = Profile()) {
        self.reference = reference
        self.advice = advice
        self.profile = profile
    }

    /// Une empreinte de la version : un index écrit avec une autre empreinte est recalculé.
    var key: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let profile = (try? encoder.encode(profile)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let source = reference.source
        return "\(reference.format)|\(source.commit)|\(source.date)|\(reference.maxTownHall)|\(reference.items.count)"
            + "|\(advice.format)|\(advice.date)|\(profile)"
    }
}

public struct PhotoSummary: Sendable, Equatable, Codable, Identifiable {
    public struct CategoryProgress: Sendable, Equatable, Codable {
        public let category: Category
        public let done: Int
        public let total: Int
    }

    /// Secondes depuis 1970 (entier : l'index s'écrit toujours de la même façon).
    public let timestamp: Int
    public let townHall: Int
    /// Avancement total (A4) ; nil quand l'HDV est inconnu (V7).
    public let total: Double?
    /// Dans l'ordre des catégories ; vide quand l'HDV est inconnu.
    public let categories: [CategoryProgress]
    /// Le cap calculé À LA DATE DE LA PHOTO (pas celle d'aujourd'hui : une courbe du cap ne doit pas dépendre du jour
    /// où on la trace). nil : rien à faire après la photo, ou HDV inconnu.
    public let capTimestamp: Int?

    public var id: Int { timestamp }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
    public var cap: Date? { capTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    init(snapshot: Snapshot, export: VillageExport, context: HistoryContext) {
        let village = Village(export: export, reference: context.reference)
        let report = progress(of: village, reference: context.reference)
        timestamp = Int(snapshot.date.timeIntervalSince1970)
        townHall = village.townHall
        total = report.total
        categories = Category.allCases.compactMap { c in
            report.categories[c].map { CategoryProgress(category: c, done: $0.done, total: $0.total) }
        }
        if village.status == .unknownTownHall {
            capTimestamp = nil
        } else {
            let plan = makePlan(for: village, reference: context.reference, advice: context.advice,
                                profile: context.profile, now: export.date, boosts: export.boosts,
                                assistants: Assistants(export: export, reference: context.reference))
            capTimestamp = plan.cap.map { Int($0.timeIntervalSince1970.rounded(.down)) }
        }
    }
}

struct HistoryIndex: Codable, Equatable {
    static let currentFormat = 1
    var format = HistoryIndex.currentFormat
    var key: String
    var entries: [PhotoSummary]
}
