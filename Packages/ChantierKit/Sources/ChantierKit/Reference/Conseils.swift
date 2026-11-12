import Foundation

// Contrat §7.2. Le fichier `Ressources/conseils.json` est écrit à la main (voir docs/conseils.md) :
// ce sont des opinions de guides tiers, datées, pas des faits.

/// Les données de conseil : ordres conseillés, défenses prioritaires. Des opinions, pas des faits.
public struct AdviceData: Sendable, Codable, Equatable {
    public static let currentFormat = 1

    public let format: Int
    /// Date de la dernière révision (ISO 8601, jour).
    public let date: String
    public let note: String
    /// La règle écrite pour les éléments absents d'une liste.
    public let fallback: String
    public let lists: [String: AdviceList]

    public init(format: Int = AdviceData.currentFormat, date: String = "", note: String = "",
                fallback: String = "", lists: [String: AdviceList] = [:]) {
        self.format = format
        self.date = date
        self.note = note
        self.fallback = fallback
        self.lists = lists
    }

    public static let listNames = ["defenses", "laboratory", "equipment", "pets"]

    /// Position (0 = en premier) de `id` dans la liste `list` ; nil s'il n'y est pas.
    public func rank(of id: Int, in list: String) -> Int? { lists[list]?.ids.firstIndex(of: id) }

    /// Classe `items` : d'abord ceux de la liste dans son ordre, puis les autres du moins cher au plus cher,
    /// puis par identifiant (résultat toujours le même).
    public func sorted<T>(_ items: [T], in list: String, id: (T) -> Int, cost: (T) -> Int) -> [T] {
        items.sorted { a, b in
            let (ra, rb) = (rank(of: id(a), in: list), rank(of: id(b), in: list))
            switch (ra, rb) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (cost(a), id(a)) < (cost(b), id(b))
            }
        }
    }
}

public struct AdviceList: Sendable, Codable, Equatable {
    /// Une phrase : le critère de classement.
    public let criterion: String
    public let sources: [String]
    public let ids: [Int]
}

public enum AdviceError: Error, Equatable {
    case missing
    case corrupt
    case unsupportedFormat(Int)
}

extension AdviceData {
    public static var bundledURL: URL? { Bundle.module.url(forResource: "conseils", withExtension: "json") }

    public static func load() throws(AdviceError) -> AdviceData {
        guard let url = bundledURL, let data = try? Data(contentsOf: url) else { throw .missing }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws(AdviceError) -> AdviceData {
        struct Entete: Decodable { let format: Int }
        guard let entete = try? JSONDecoder().decode(Entete.self, from: data) else { throw .corrupt }
        guard entete.format == currentFormat else { throw .unsupportedFormat(entete.format) }
        guard let advice = try? JSONDecoder().decode(AdviceData.self, from: data) else { throw .corrupt }
        return advice
    }
}
