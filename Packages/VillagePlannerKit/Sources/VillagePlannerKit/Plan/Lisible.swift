import Foundation

/// Temps, montants et sommes restantes sous une forme lisible (écran Village), en français.
public enum Lisible {
    private static let fine = "\u{202F}", insecable = "\u{00A0}"

    /// Entier avec une espace fine tous les trois chiffres.
    static func groupes(_ n: Int) -> String {
        var s = String(abs(n)), out = ""
        while s.count > 3 { out = fine + s.suffix(3) + out; s.removeLast(3) }
        return (n < 0 ? "-" : "") + s + out
    }

    /// Temps de travail : « 3 j 4 h », « 5 h 20 min », « 12 min » ; les minutes ne se montrent plus au-delà d'un jour.
    public static func duree(_ secondes: Int) -> String {
        let m = secondes / 60 % 60, h = secondes / 3600 % 24, j = secondes / 86_400
        if j > 0 { return groupes(j) + insecable + "j" + (h > 0 ? insecable + "\(h)" + insecable + "h" : "") }
        if h > 0 { return "\(h)" + insecable + "h" + (m > 0 ? insecable + "\(m)" + insecable + "min" : "") }
        return secondes >= 60 ? "\(m)" + insecable + "min" : "moins d'une" + insecable + "min"
    }

    /// Montant : entier jusqu'à 999 999, puis « 1,5 M » et « 1,64 Md » (deux décimales au plus).
    public static func montant(_ n: Int) -> String {
        func court(_ v: Double, _ unite: String) -> String {
            var t = String(format: "%.2f", (v * 100).rounded() / 100).replacingOccurrences(of: ".", with: ",")
            while t.hasSuffix("0") { t.removeLast() }
            if t.hasSuffix(",") { t.removeLast() }
            return t + insecable + unite
        }
        if n >= 1_000_000_000 { return court(Double(n) / 1e9, "Md") }
        if n >= 1_000_000 { return court(Double(n) / 1e6, "M") }
        return groupes(n)
    }

    /// « 162 M d'or », « 512 560 de minerai brillant ».
    public static func cout(_ montant: Int, _ ressource: Resource) -> String {
        let (de, nom): (String, String) = switch ressource {
        case .gold: ("d'", "or")
        case .elixir: ("d'", "élixir")
        case .darkElixir: ("d'", "élixir noir")
        case .shinyOre: ("de" + insecable, "minerai brillant")
        case .glowyOre: ("de" + insecable, "minerai luisant")
        case .starryOre: ("de" + insecable, "minerai étoilé")
        }
        return Self.montant(montant) + insecable + de + nom.replacingOccurrences(of: " ", with: insecable)
    }

    /// Ce qui reste à un ensemble de pas : « Reste 3 j 4 h · 162 M d'or · 2 M d'élixir ».
    /// En cours sans rien d'autre : « rien à payer » ; minuteur illisible : pas de durée inventée.
    /// nil quand il ne reste aucun pas. `exemplaires` > 1 : précise que les montants valent pour tous.
    public static func resume(_ steps: [UpgradeStep], exemplaires: Int = 1) -> String? {
        guard !steps.isEmpty else { return nil }
        let t = RemainingTotals(steps)
        var parts: [String] = []
        if t.seconds > 0 { parts.append("Reste " + duree(t.seconds) + (t.unknownTimers > 0 ? ", plus un minuteur illisible" : "")) }
        else if t.unknownTimers > 0 { parts.append("Fin du minuteur inconnue") }
        let couts = Resource.allCases.compactMap { r in t.costs[r].flatMap { $0 > 0 ? cout($0, r) : nil } }
        if couts.isEmpty, steps.contains(where: \.isInProgress) { parts.append("rien à payer") }
        else if !couts.isEmpty { parts += parts.isEmpty ? ["À payer " + couts[0]] + couts.dropFirst() : couts }   // murs : pas de durée
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + (exemplaires > 1 ? " (pour les \(exemplaires))" : "")
    }

    /// La mention des réductions actives à `date`, ou nil : « Avec la réduction actuelle : ouvriers −20 %, labo −10 %. »
    public static func reductions(_ profil: Profile, at date: Date) -> String? {
        var parts: [String] = []
        let o = profil.reductionPercent(for: .builder, at: date), l = profil.reductionPercent(for: .laboratory, at: date)
        if o > 0 { parts.append("ouvriers −\(o)" + insecable + "%") }
        if l > 0 { parts.append("labo −\(l)" + insecable + "%") }
        return parts.isEmpty ? nil : "Avec la réduction actuelle : " + parts.joined(separator: ", ") + "."
    }
}
