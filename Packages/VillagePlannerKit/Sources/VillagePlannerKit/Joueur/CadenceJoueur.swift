import Foundation
import Synchronization

// La cadence des lectures du profil : pas plus d'une par heure (l'API est publique et passe par un relais communautaire).
// Même méthode que le budget de T19 : la date la plus récente déjà vue est retenue, donc reculer l'horloge de l'appareil
// n'autorise rien ; une date mise dans le futur puis remise à l'heure est recalée sur l'en-tête `Date` du service.

public struct CadenceJoueur: Codable, Sendable, Equatable {
    public static let intervalle: TimeInterval = 3_600

    /// La date de la dernière lecture partie (même une lecture refusée par le service : elle l'a sollicité).
    public private(set) var dernierAppel: Date?
    /// La date la plus récente déjà vue.
    public private(set) var plusRecent: Date?

    public init() {}

    /// Le moment où une lecture sera de nouveau permise, ou nil si elle peut partir à `now`.
    public func bloqueJusqua(_ now: Date) -> Date? {
        guard let dernierAppel else { return nil }
        let t = max(now, plusRecent ?? now)
        let pret = dernierAppel.addingTimeInterval(Self.intervalle)
        return t < pret ? pret : nil
    }

    mutating func enregistrer(_ now: Date) {
        let t = max(now, plusRecent ?? now)
        dernierAppel = t
        plusRecent = t
    }

    /// L'appareil avait une date en avance de plus d'un jour sur celle du service : on revient à celle du service.
    mutating func recaler(serverDate: Date) -> Bool {
        guard let plusRecent, plusRecent > serverDate.addingTimeInterval(Budget.clockTolerance) else { return false }
        self.plusRecent = serverDate
        if let d = dernierAppel { dernierAppel = min(d, serverDate) }
        return true
    }
}

/// L'enregistrement de la cadence : un blob JSON dans les préférences (deux dates, aucun secret).
/// shortcut: un blob abîmé redonne une cadence neuve (une lecture de plus, au pire) ; le relais borne de toute façon.
public struct CadenceStore: @unchecked Sendable {   // UserDefaults est sûr entre fils
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "cadence-joueur") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> CadenceJoueur {
        guard let data = defaults.data(forKey: key) else { return CadenceJoueur() }
        return (try? JSONDecoder().decode(CadenceJoueur.self, from: data)) ?? CadenceJoueur()
    }

    private func save(_ cadence: CadenceJoueur) {
        guard let data = try? JSONEncoder().encode(cadence) else { return }
        defaults.set(data, forKey: key)
    }

    private static let verrou = Mutex(())

    /// Réserve la lecture : nil si elle peut partir (elle est alors comptée), sinon le moment où elle sera permise.
    public func reserver(at now: Date) -> Date? {
        Self.verrou.withLock { _ in
            var c = load()
            if let jusqua = c.bloqueJusqua(now) { return jusqua }
            c.enregistrer(now)
            save(c)
            return nil
        }
    }

    /// Rend la réservation : la requête n'est jamais partie (pas de réseau).
    public func annuler(_ avant: CadenceJoueur) {
        Self.verrou.withLock { _ in save(avant) }
    }

    @discardableResult
    public func recaler(serverDate: Date) -> Bool {
        Self.verrou.withLock { _ in
            var c = load()
            guard c.recaler(serverDate: serverDate) else { return false }
            save(c)
            return true
        }
    }
}
