import Foundation

/// Une photo : un export enregistré tel quel, dans un fichier nommé par sa date (PLAN §4.5).
/// Le résumé calculé (courbes) arrive avec l'historique, T22 : les photos restent la source de vérité.
public struct Snapshot: Sendable, Equatable, Identifiable {
    /// Le `timestamp` de l'export, à la seconde près.
    public let date: Date
    public var id: Date { date }

    public init(date: Date) {
        self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// `20261112T094802Z.json` : la date en UTC, qui se trie comme l'ordre du temps.
    public var fileName: String { date.formatted(Self.nameFormat) + ".json" }

    static let nameFormat = Date.ISO8601FormatStyle(timeZone: .gmt).dateSeparator(.omitted).timeSeparator(.omitted)

    init?(fileName: String) {
        guard fileName.hasSuffix(".json"),
              let date = try? Self.nameFormat.parseStrategy.parse(String(fileName.dropLast(5))) else { return nil }
        self.init(date: date)
    }
}

/// Les photos d'un dossier : enregistrer, lister, relire. Aucune horloge, aucun réseau.
public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public enum Outcome: Sendable, Equatable {
        case created(Snapshot)
        /// Même `timestamp` qu'une photo déjà là : rien n'est écrit.
        case alreadyStored(Snapshot)
    }

    public enum SaveError: Error, Equatable {
        /// Le texte n'est pas un export : rien n'est écrit.
        case invalid(ExportError)
        case cannotWrite
    }

    /// Vérifie que le texte est un export, puis l'écrit tel quel (octet pour octet).
    @discardableResult
    public func save(_ text: String) throws(SaveError) -> Outcome {
        let export: VillageExport
        do { export = try VillageExport.parse(text) } catch { throw .invalid(error) }
        let snapshot = Snapshot(date: export.date)
        let url = directory.appending(path: snapshot.fileName)
        // Un fichier de la même date n'est une photo que s'il se relit : un fichier abîmé est réécrit.
        if let existant = try? String(contentsOf: url, encoding: .utf8), (try? VillageExport.parse(existant)) != nil {
            return .alreadyStored(snapshot)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw .cannotWrite
        }
        return .created(snapshot)
    }

    /// Les photos, de la plus ancienne à la plus récente.
    public func list() -> [Snapshot] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { Snapshot(fileName: $0) }.sorted { $0.date < $1.date }
    }

    public func text(of snapshot: Snapshot) -> String? {
        try? String(contentsOf: directory.appending(path: snapshot.fileName), encoding: .utf8)
    }

    /// La photo la plus récente qui se relit. Un fichier abîmé est sauté : la précédente prend sa place.
    public func latest() -> (snapshot: Snapshot, export: VillageExport)? {
        for snapshot in list().reversed() {
            if let text = text(of: snapshot), let export = try? VillageExport.parse(text) {
                return (snapshot, export)
            }
        }
        return nil
    }
}

extension Snapshot {
    /// « photo d'hier, 17 h 28 ». Jusqu'à six jours : le jour de la semaine ; au-delà : la date.
    public func ageDescription(now: Date, calendar: Calendar = .current,
                               locale: Locale = Locale(identifier: "fr_FR")) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = "\(parts.hour ?? 0)\u{A0}h\u{A0}" + String(format: "%02d", parts.minute ?? 0)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        func formatted(_ build: (Date.FormatStyle) -> Date.FormatStyle) -> String {
            date.formatted(build(Date.FormatStyle(date: .omitted, time: .omitted, locale: locale,
                                                  calendar: calendar, timeZone: calendar.timeZone)))
        }
        let day: String
        switch days {
        case ...0: day = "d'aujourd'hui"      // une photo « du futur » (horloge décalée) reste « d'aujourd'hui »
        case 1: day = "d'hier"
        case 2...6: day = "de " + formatted { $0.weekday(.wide) }
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            day = "du " + formatted { sameYear ? $0.day().month(.wide) : $0.day().month(.wide).year() }
        }
        return "photo \(day), \(time)"
    }
}
