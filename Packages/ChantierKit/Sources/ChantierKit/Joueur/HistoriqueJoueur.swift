import Foundation

// L'historique des lectures du profil (T30) et les équipements que l'API dit possédés ou équipés.
// Rangé à côté des photos (même racine que `HistoryStore`), dans `joueur.json`. Aucune horloge : la date de la lecture est
// un paramètre. Le fichier s'écrit en entier et en une fois (atomique) ; un fichier abîmé est mis de côté, jamais effacé.

/// Les chiffres d'une lecture réussie, avec sa date. Un chiffre que le service n'a pas donné reste nil.
public struct LectureJoueur: Codable, Sendable, Equatable, Identifiable {
    public var date: Date
    public var trophees: Int?
    public var record: Int?
    public var ligue: String?
    public var victoiresAttaque: Int?
    public var victoiresDefense: Int?
    public var dons: Int?
    public var etoilesGuerre: Int?
    /// Le total des étoiles de tous les succès.
    public var etoilesSucces: Int?
    /// Les succès terminés (trois étoiles).
    public var succesTermines: Int?

    public var id: Int { Int(date.timeIntervalSince1970) }

    public init(date: Date, trophees: Int? = nil, record: Int? = nil, ligue: String? = nil, victoiresAttaque: Int? = nil,
                victoiresDefense: Int? = nil, dons: Int? = nil, etoilesGuerre: Int? = nil, etoilesSucces: Int? = nil,
                succesTermines: Int? = nil) {
        self.date = date; self.trophees = trophees; self.record = record; self.ligue = ligue
        self.victoiresAttaque = victoiresAttaque; self.victoiresDefense = victoiresDefense; self.dons = dons
        self.etoilesGuerre = etoilesGuerre; self.etoilesSucces = etoilesSucces; self.succesTermines = succesTermines
    }

    public init(profil p: ProfilJoueur, date: Date) {
        self.init(date: date, trophees: p.trophies, record: p.bestTrophies, ligue: p.leagueTier?.name,
                  victoiresAttaque: p.attackWins, victoiresDefense: p.defenseWins, dons: p.donations,
                  etoilesGuerre: p.warStars,
                  etoilesSucces: p.achievements.isEmpty ? nil : p.achievements.reduce(0) { $0 + ($1.stars ?? 0) },
                  succesTermines: p.achievements.isEmpty ? nil : p.achievements.filter { ($0.stars ?? 0) >= 3 }.count)
    }

    /// Les points d'une courbe : les lectures qui donnent ce chiffre, de la plus ancienne à la plus récente.
    public static func serie(_ lectures: [LectureJoueur], _ chiffre: KeyPath<LectureJoueur, Int?>) -> [(date: Date, valeur: Int)] {
        lectures.sorted { $0.date < $1.date }.compactMap { l in l[keyPath: chiffre].map { (l.date, $0) } }
    }
}

/// Un héros et les noms (anglais, ceux de l'API) de ses équipements équipés.
public struct HerosEquipe: Codable, Sendable, Equatable {
    public var heros: String
    public var equipements: [String]
    public init(heros: String, equipements: [String]) { (self.heros, self.equipements) = (heros, equipements) }
}

/// Ce que l'API dit des équipements : ceux qu'on possède (remplace la règle V4) et ceux qui sont équipés (en tête de la forge).
public struct EquipementsJoueur: Sendable, Equatable {
    public var possedes: Set<Int>
    public var equipes: Set<Int>

    public init(possedes: Set<Int> = [], equipes: Set<Int> = []) {
        self.equipes = equipes
        self.possedes = possedes.union(equipes)      // un équipement équipé est possédé
    }

    /// Le type de la référence portant ce nom (nom anglais de l'API) ; nil si la référence ne le connaît pas encore.
    public static func identifiant(_ nom: String, dans reference: ReferenceData, categorie: Category = .equipment) -> Int? {
        let cle = nom.lowercased()
        return reference.items.first { $0.category == categorie && $0.names["en"]?.lowercased() == cle }?.id
    }

    /// Ce que dit un profil lu ; nil s'il ne dit rien des équipements (la règle V4 reste alors la seule source).
    public init?(profil: ProfilJoueur, reference: ReferenceData) {
        guard !(profil.heroEquipment.isEmpty && profil.heroes.allSatisfy { $0.equipment.isEmpty }) else { return nil }
        self.init(possedes: profil.heroEquipment,
                  equipes: profil.heroes.map { HerosEquipe(heros: $0.name, equipements: $0.equipment.map(\.name)) },
                  reference: reference)
    }

    init(possedes: [ItemJoueur], equipes: [HerosEquipe], reference: ReferenceData) {
        let noms = { (l: [String]) in Set(l.compactMap { Self.identifiant($0, dans: reference) }) }
        self.init(possedes: noms(possedes.map(\.name)), equipes: noms(equipes.flatMap(\.equipements)))
    }
}

/// Le fichier : les lectures, et la dernière liste d'équipements (pour que le conseil s'en serve sans nouvelle lecture).
public struct HistoriqueJoueur: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// Au-delà, les plus anciennes lectures sortent (une par heure au plus : plus de cinq ans).
    /// shortcut: la coupe se fait à l'écriture, sans agrégation ; à revoir si l'on veut des courbes sur dix ans.
    public static let maximum = 50_000
    static let format = 1

    var url: URL { root.appending(path: "joueur.json") }

    struct Fichier: Codable, Equatable {
        var format = HistoriqueJoueur.format
        var lectures: [LectureJoueur] = []
        var possedes: [String] = []
        var equipes: [HerosEquipe] = []

        init() {}

        /// Tolérant : une lecture illisible est écartée sans emporter les autres ; une liste absente est vide.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            format = try c.decode(Int.self, forKey: .format)
            lectures = ((try? c.decode([Souple<LectureJoueur>].self, forKey: .lectures)) ?? []).compactMap(\.valeur)
            possedes = (try? c.decode([String].self, forKey: .possedes)) ?? []
            equipes = ((try? c.decode([Souple<HerosEquipe>].self, forKey: .equipes)) ?? []).compactMap(\.valeur)
        }
    }

    private struct Souple<T: Decodable>: Decodable {
        let valeur: T?
        init(from decoder: any Decoder) throws { valeur = try? T(from: decoder) }
    }

    private static func encodeur() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }

    private static func decodeur() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    private enum Etat { case absent, lu(Fichier), abime, illisible }

    /// `absent` : pas de fichier. `abime` : le contenu ne se relit pas. `illisible` : le fichier est là mais le système refuse
    /// de le lire (appareil verrouillé, erreur d'E/S) : on n'y touche pas, on ne repart pas d'un fichier vide.
    private func lire() -> Etat {
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url) else { return .illisible }
        guard let f = try? Self.decodeur().decode(Fichier.self, from: data), f.format == Self.format else { return .abime }
        return .lu(f)
    }

    /// Met le fichier abîmé de côté sous un nom daté ; jamais d'effacement. Faux si le déplacement échoue.
    private func mettreDeCote(_ date: Date) -> Bool {
        let base = "joueur-abime-\(Int(date.timeIntervalSince1970))"
        var cible = root.appending(path: "\(base).json")
        var n = 2
        while FileManager.default.fileExists(atPath: cible.path) { cible = root.appending(path: "\(base)-\(n).json"); n += 1 }
        return (try? FileManager.default.moveItem(at: url, to: cible)) != nil
    }

    private func fichierLu() -> Fichier? { if case .lu(let f) = lire() { f } else { nil } }

    /// Les lectures, de la plus ancienne à la plus récente ; vide si le fichier manque ou ne se relit pas.
    public func lectures() -> [LectureJoueur] {
        (fichierLu()?.lectures ?? []).sorted { $0.date < $1.date }
    }

    /// Les héros et leurs équipements équipés à la dernière lecture.
    public func equipes() -> [HerosEquipe] { fichierLu()?.equipes ?? [] }

    /// Ce que l'API disait à la dernière lecture ; nil avant la première lecture.
    public func equipements(reference: ReferenceData) -> EquipementsJoueur? {
        guard let f = fichierLu(), !(f.possedes.isEmpty && f.equipes.isEmpty) else { return nil }
        return EquipementsJoueur(possedes: f.possedes.map { ItemJoueur(name: $0) }, equipes: f.equipes, reference: reference)
    }

    /// Garde la lecture. Deux lectures de la même seconde n'en font qu'une. Faux si le fichier ne s'écrit pas.
    @discardableResult
    public func enregistrer(_ profil: ProfilJoueur, le date: Date) -> Bool {
        var f: Fichier
        switch lire() {
        case .lu(let lu): f = lu
        case .absent: f = Fichier()
        case .abime:
            guard mettreDeCote(date) else { return false }
            f = Fichier()
        case .illisible: return false                  // l'historique existe : on n'écrit rien par-dessus
        }
        let l = LectureJoueur(profil: profil, date: date)
        f.lectures.removeAll { $0.id == l.id }
        f.lectures.append(l)
        f.lectures.sort { $0.date < $1.date }
        if f.lectures.count > Self.maximum { f.lectures.removeFirst(f.lectures.count - Self.maximum) }
        // Un profil qui ne dit rien des équipements (champs absents) laisse les listes précédentes en place.
        if !(profil.heroEquipment.isEmpty && profil.heroes.allSatisfy { $0.equipment.isEmpty }) {
            f.possedes = profil.heroEquipment.map(\.name)
            f.equipes = profil.heroes.filter { !$0.equipment.isEmpty }.map { HerosEquipe(heros: $0.name, equipements: $0.equipment.map(\.name)) }
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Self.encodeur().encode(f).write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
}
