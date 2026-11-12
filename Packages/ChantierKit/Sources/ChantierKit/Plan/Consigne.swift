import Foundation

// La consigne du moteur (PLAN §3.1, §6.3 G3) : une ou deux phrases écrites par un gabarit à partir du plan.
// Elle est toujours disponible : c'est le repli du conseiller (clé absente, budget atteint, refus).
//
// Les cas, dans l'ordre où le gabarit les examine :
//  C1  photo de plus de sept jours : les minuteurs ont fini, le plan ne vaut plus ; on demande un nouvel export ;
//  C2  rien à lancer : tout est terminé (`cap == nil`), ou il ne reste que des améliorations bloquées (S7), ou il ne
//      reste que des minuteurs en cours ;
//  C3  un poste libre à `now` : « Un ouvrier est libre : lance … » ; plusieurs postes libres au même instant : une
//      seule phrase, les lancements du même instant sont regroupés ;
//  C4  le prochain lancement est dans les 24 h : « Demain 14 h, deux ouvriers se libèrent : lance … » ;
//  C5  le prochain lancement est à plus de 24 h : « Rien à lancer avant jeudi 9 h. »
// Décisions :
//  - les dates sont écrites à la main (jours et mois en français) dans le fuseau donné : même texte sur tous les
//    appareils, testable ; l'heure est arrondie à la minute supérieure (jamais une heure avant la vraie) ;
//  - « Arc-X 11 » désigne le niveau que l'amélioration fait atteindre ; pas d'article (« l'Arc-X », « la Tour ») pour
//    ne pas deviner un genre ;
//  - au-delà de trois améliorations lancées au même instant, les autres sont comptées (« et 2 autres »).

/// Une photo plus vieille que cela ne dit plus rien de l'état du village.
let photoPerimee: TimeInterval = 7 * 86_400

/// Au-delà, le prochain lancement n'est plus « pour bientôt ».
let horizonConsigne: TimeInterval = 24 * 3600

/// `photo` : la date de l'export. `timeZone` : celui de l'appareil (les jours et les heures sont ceux du joueur).
public func consigne(of plan: Plan, photo: Date, reference: ReferenceData, timeZone: TimeZone) -> String {
    let age = plan.now.timeIntervalSince(photo)
    if age > photoPerimee {                                                       // C1
        return "Ta photo date de \(Int(age / 86_400)) jours : les minuteurs ont fini depuis et le plan ne vaut plus. "
            + "Copie un nouvel export depuis le jeu."
    }
    let launches = plan.steps.filter { !$0.fromSnapshot }
    guard let start = launches.map(\.start).min() else {                          // C2
        if let cap = plan.cap {
            return "Rien d'autre à lancer : il ne reste que les améliorations en cours. La dernière finit "
                + Lisible.moment(cap, now: plan.now, timeZone: timeZone) + "."
        }
        let n = plan.blocked.count
        if n > 0 { return "Plus rien ne peut partir : \(n) amélioration\(n > 1 ? "s sont bloquées" : " est bloquée")." }
        return "Tout est terminé à ton HDV : plus rien à améliorer, hors murs et équipements."
    }
    let wave = launches.filter { $0.start == start }
    let postes = postes(of: wave)
    let seul = wave.count == 1
    let quand = Lisible.moment(start, now: plan.now, timeZone: timeZone)
    let lancer = "lance " + liste(wave, reference: reference)
    let couts = Resource.allCases.compactMap { r -> String? in
        let total = wave.reduce(0) { $0 + $1.costs.filter { $0.resource == r }.reduce(0) { $0 + $1.amount } }
        return total > 0 ? Lisible.cout(total, r) : nil
    }
    let reunir = couts.isEmpty ? "" : " " + couts.joined(separator: " et ")
    let sujet = enumerer(postes)

    if start <= plan.now {                                                        // C3
        return majuscule(sujet) + (seul ? " est libre" : " sont libres") + " : " + lancer + "."
            + (couts.isEmpty ? "" : " Il te faut" + reunir + ".")
    }
    let libere = sujet + (seul ? " se libère" : " se libèrent")
    if start.timeIntervalSince(plan.now) > horizonConsigne {                      // C5
        return "Rien à lancer avant \(quand). Ce jour-là, \(libere) : \(lancer)."
            + (couts.isEmpty ? "" : " Prépare" + reunir + ".")
    }
    return majuscule(quand) + ", " + libere + " : " + lancer + "."               // C4
        + (couts.isEmpty ? "" : " Prépare" + reunir + ".")
}

private func majuscule(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

/// « a », « a et b », « a, b et c ».
private func enumerer(_ parts: [String]) -> String {
    parts.count < 2 ? parts.joined() : parts.dropLast().joined(separator: ", ") + " et " + parts[parts.count - 1]
}

/// Les postes qui se libèrent : « deux ouvriers », « le labo », « la Maison des familiers ».
private func postes(of wave: [ScheduledStep]) -> [String] {
    func n(_ w: WorkerKind) -> Int { wave.filter { $0.worker == w }.count }
    let mots = ["un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix"]
    var out: [String] = []
    let o = n(.builder)
    if o > 0 { out.append((o <= mots.count ? mots[o - 1] : String(o)) + (o > 1 ? " ouvriers" : " ouvrier")) }
    if n(.laboratory) > 0 { out.append("le labo") }
    if n(.petHouse) > 0 { out.append("la Maison des familiers") }
    return out
}

/// « Arc-X 11 », « Canon 5 (×2) » ; trois au plus, puis « et 2 autres ».
private func liste(_ wave: [ScheduledStep], reference: ReferenceData) -> String {
    var groupes: [(nom: String, copies: Int)] = []
    for s in wave {
        let nom = "\(reference.item(s.step.itemID)?.name ?? "#\(s.step.itemID)") \(s.step.level)"
        if let i = groupes.firstIndex(where: { $0.nom == nom }) { groupes[i].copies += 1 } else { groupes.append((nom, 1)) }
    }
    let textes = groupes.map { $0.copies > 1 ? "\($0.nom) (×\($0.copies))" : $0.nom }
    guard textes.count > 3 else { return enumerer(textes) }
    let reste = groupes.dropFirst(3).reduce(0) { $0 + $1.copies }
    return textes.prefix(3).joined(separator: ", ") + " et \(reste) autre\(reste > 1 ? "s" : "")"
}

// MARK: - Dates en français

extension Lisible {
    private static let jours = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    private static let mois = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre",
                               "octobre", "novembre", "décembre"]

    private static func calendrier(_ timeZone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// « 14 h », « 9 h 05 » : arrondi à la minute supérieure.
    public static func heure(_ date: Date, timeZone: TimeZone) -> String {
        let ronde = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
        let c = calendrier(timeZone).dateComponents([.hour, .minute], from: ronde)
        let h = "\(c.hour ?? 0)\u{00A0}h"
        return (c.minute ?? 0) == 0 ? h : h + "\u{00A0}" + (c.minute! < 10 ? "0" : "") + "\(c.minute!)"
    }

    /// « 14 mars », « 1er mars » ; l'année s'ajoute quand elle n'est pas celle de `now`.
    public static func jour(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        let c = calendrier(timeZone)
        let d = c.dateComponents([.day, .month, .year], from: date)
        let texte = (d.day == 1 ? "1er" : "\(d.day ?? 0)") + "\u{00A0}" + mois[(d.month ?? 1) - 1]
        return d.year == c.component(.year, from: now) ? texte : texte + "\u{00A0}\(d.year ?? 0)"
    }

    /// Jours de calendrier entre `now` et `date` dans ce fuseau (0 : le même jour, 1 : demain, -1 : hier).
    private static func ecart(_ date: Date, now: Date, timeZone: TimeZone) -> Int {
        let c = calendrier(timeZone)
        return c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: date)).day ?? 0
    }

    /// Un moment à venir : « aujourd'hui 14 h », « demain 9 h », « jeudi 9 h » (dans la semaine),
    /// « le 14 mars à 9 h » au-delà. Toujours en minuscules : l'appelant met la majuscule.
    public static func moment(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        let e = ecart(date, now: now, timeZone: timeZone)
        let heure = heure(date, timeZone: timeZone)
        switch e {
        case ..<0: return "le\u{00A0}" + jour(date, now: now, timeZone: timeZone) + " à\u{00A0}" + heure
        case 0: return "aujourd'hui\u{00A0}" + heure
        case 1: return "demain\u{00A0}" + heure
        case 2...6: return jours[calendrier(timeZone).component(.weekday, from: date) - 1] + "\u{00A0}" + heure
        default: return "le\u{00A0}" + jour(date, now: now, timeZone: timeZone) + " à\u{00A0}" + heure
        }
    }

    /// Ce qui suit « libre depuis » : « 14 h » (aujourd'hui), « hier 14 h », « mardi 14 h » (dans la semaine),
    /// « le 9 novembre » au-delà. `date` est avant `now`.
    public static func depuis(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        let e = ecart(date, now: now, timeZone: timeZone)
        let heure = heure(date, timeZone: timeZone)
        switch e {
        case 0...: return heure
        case -1: return "hier\u{00A0}" + heure
        case -6 ... -2: return jours[calendrier(timeZone).component(.weekday, from: date) - 1] + "\u{00A0}" + heure
        default: return "le\u{00A0}" + jour(date, now: now, timeZone: timeZone)
        }
    }
}
