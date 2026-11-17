import Foundation

// G1 (PLAN §6.2) : lire tous les nombres d'un texte, sous n'importe quelle écriture, pour vérifier que chacun figure
// dans le résumé envoyé au modèle. La même lecture sert au texte de la réponse et au résumé : deux écritures du même
// nombre donnent la même `Valeur`.
//
// Formes reconnues (la table testée est `NombresTests` / GardeFousTests.tableDesFormes) :
//  - entiers, avec espaces de milliers (ordinaires, insécables U+00A0, fines U+202F) : « 18 000 000 » ;
//  - décimaux à virgule : « 1,5 » ; multiplicateurs : « 18 M », « 18 millions », « 1,64 Md », « 18k », « 2 mille » ;
//  - nombres en lettres, de zéro à plusieurs milliers : « douze », « vingt et un », « quatre-vingt-dix » ;
//  - pourcentages : « 64 % », « 64 pour cent » ; durées : « 3 j », « 3 jours », « 2 semaines », « 20 min » ;
//  - heures : « 7 h », « 7 h 30 », « 7h30 », « 7:30 », « 7 heures et 30 minutes » ;
//  - dates : « le 9 décembre », « 1er mars » (le jour d'une date n'est pas un nombre à part) ;
//  - jours de la semaine : « jeudi ».
// Décisions :
//  - « un » et « une » ne comptent que devant une unité (jour, heure, ouvrier, niveau, fois…) : ailleurs, c'est un article ;
//  - les ordinaux (« 2e », « deuxième ») désignent un rang dans la liste, pas une donnée : ils ne sont pas lus ;
//  - un quantificateur vague qui cache un nombre (« une dizaine », « le double », « la moitié ») ne peut pas être
//    vérifié : il est lu comme `.vague`, jamais connu, donc la réponse est rejetée ;
//  - une heure est comparée avec ses minutes : « 7 h 30 » n'est pas « 7 h ».
// Limite connue : « neuf » adjectif (« un bâtiment neuf ») est lu comme le nombre 9.

/// Une valeur lue dans un texte, sans trace de l'écriture d'origine.
enum Valeur: Hashable, Sendable {
    enum Unite: String, Sendable { case jour, semaine, mois, an, minute, heure }
    case nombre(String)                 // décimal canonique : « 18000000 », « 1.5 »
    case pourcent(String)
    case duree(String, Unite)
    case horaire(heure: Int, minute: Int)
    case date(jour: Int, mois: Int)
    case jourSemaine(Int)
    case vague(String)
}

/// Une valeur et le morceau de texte (replié : minuscules, sans accents) où elle a été lue.
struct Lecture: Equatable, Sendable {
    let valeur: Valeur
    let extrait: String
}

enum Nombres {
    /// Minuscules, sans accents, espaces et apostrophes ordinaires : la forme sur laquelle tout se lit.
    static func replier(_ texte: String) -> String {
        var t = texte.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        for (de, vers) in [("\u{00A0}", " "), ("\u{202F}", " "), ("\u{2009}", " "), ("\u{2007}", " "), ("\u{2011}", "-"),
                           ("\u{2019}", "'"), ("\u{2212}", "-"), ("\u{00D7}", " x "), ("\u{2192}", " vers ")] {
            t = t.replacingOccurrences(of: de, with: vers)
        }
        t = t.replacingOccurrences(of: #"(\d{1,2}):(\d{2})"#, with: "$1 h $2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"pour[ -]?cent"#, with: "%", options: .regularExpression)
        return t
    }

    static func lire(_ texte: String) -> [Lecture] {
        let t = replier(texte)
        var out = lireNombres(t)
        out += motifs(Self.jours, dans: t) { _, i in .jourSemaine(i) }
        out += motifs(Self.vagues, dans: t) { m, _ in .vague(m) }
        return out
    }

    // MARK: Nombres

    private static let motsNombres = "zero|une|un|deux|trois|quatorze|quatre|quinze|cinquante|cinq|seize|six|sept|huit|neuf|dix|onze|douze|treize|"
        + "vingts?|trente|quarante|soixante|cents?|mille|millions?|milliards?"
    private static let maitre = try! NSRegularExpression(
        pattern: #"(?<![0-9#])(\d{1,3}(?: \d{3})+|\d+)(?:[.,](\d+))?(?![0-9])|\b(?:"# + motsNombres + #")(?:(?:-|\s+et\s+|\s+)(?:"# + motsNombres + #"))*\b"#)
    private static let mois = ["janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout", "septembre", "octobre", "novembre", "decembre"]
    private static let jours = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    private static let vagues = ["double", "triple", "moitie", "demi", "demie", "quart", "tiers", "dizaines?", "douzaines?", "quinzaines?",
                                 "vingtaines?", "trentaines?", "quarantaines?", "cinquantaines?", "centaines?", "milliers?"]

    private static func lireNombres(_ t: String) -> [Lecture] {
        let ns = t as NSString
        var out: [Lecture] = []
        var position = 0
        while position < ns.length, let m = maitre.firstMatch(in: t, range: NSRange(location: position, length: ns.length - position)) {
            let corps = ns.substring(with: m.range)
            var fin = m.range.location + m.range.length
            let candidats: [(Decimal, Bool)] = m.range(at: 1).location != NSNotFound
                ? [(decimal(corps), false)] : motsEnNombres(corps)
            // Les mots donnent parfois plusieurs nombres (« deux trois ») : seul le dernier prend l'unité qui suit.
            for (i, (valeur, article)) in candidats.enumerated() {
                let dernier = i == candidats.count - 1
                let suite = dernier ? ns.substring(from: fin) : ""
                let (valeurLue, consomme) = unite(valeur, article: article, suite: suite, ordinalPossible: m.range(at: 1).location != NSNotFound)
                if dernier { fin += consomme }
                if let valeurLue { out.append(Lecture(valeur: valeurLue, extrait: corps + (dernier ? String(suite.prefix(consomme)) : ""))) }
            }
            position = max(fin, m.range.location + max(m.range.length, 1))
        }
        return out
    }

    /// L'unité qui suit un nombre : donne la valeur et le nombre de caractères consommés. nil : rien à vérifier.
    private static func unite(_ v: Decimal, article: Bool, suite: String, ordinalPossible: Bool) -> (Valeur?, Int) {
        func debut(_ motif: String) -> (String, Int)? {
            guard let r = suite.range(of: "^(?:" + motif + ")", options: .regularExpression) else { return nil }
            return (String(suite[r]), suite.distance(from: suite.startIndex, to: r.upperBound))
        }
        let entier = Self.entier(v)
        if let (_, n) = debut(#"(?:er|ere|eme|nd|nde|e)(?![a-z])"#), ordinalPossible {
            // « 1er mars » est une date ; un autre ordinal est un rang, pas une donnée.
            if let (mot, n2) = debut(#"(?:er|ere|eme|nd|nde|e)(?![a-z])\s+(?:"# + mois.joined(separator: "|") + #")\b"#), entier == 1,
               let i = mois.firstIndex(where: { mot.hasSuffix($0) }) { return (.date(jour: 1, mois: i + 1), n2) }
            return (nil, n)
        }
        if let (mot, n) = debut(#"\s+(?:"# + mois.joined(separator: "|") + #")\b"#), let j = entier, (1...31).contains(j),
           let i = mois.firstIndex(where: { mot.hasSuffix($0) }) { return (.date(jour: j, mois: i + 1), n) }
        if let (mot, n) = debut(#"\s*(?:(?:milliards?|mds?|millions?|mille)\b|[km](?![a-z]))"#) {
            let m = mot.trimmingCharacters(in: .whitespaces)
            let facteur: Decimal = m.hasPrefix("milliard") || m.hasPrefix("md") ? 1_000_000_000 : m.hasPrefix("million") || m == "m" ? 1_000_000 : 1_000
            return (.nombre(canon(v * facteur)), n)
        }
        if let (_, n) = debut(#"\s*%"#) { return (.pourcent(canon(v)), n) }
        if let (_, n) = debut(#"\s*(?:heures?\b|h(?![a-z]))"#) {
            guard let h = entier else { return (.duree(canon(v), .heure), n) }
            // Minutes : « 7 h 30 », « 7 h 5 min », « 7 heures et 30 minutes » (deux chiffres, sauf devant « min »).
            let apres = String(suite.dropFirst(n))
            if let r = apres.range(of: #"^\s*(?:et\s+)?(\d{1,2})\s*min(?:utes?)?\b"#, options: .regularExpression)
                ?? apres.range(of: #"^\s*(\d{2})(?![0-9])(?!\s*(?:%|j\b|jours?|ouvriers?|niveaux?|mds?\b|m\b|k\b|millions?|milliards?|h\b))"#, options: .regularExpression),
               let chiffres = apres[r].range(of: #"\d{1,2}"#, options: .regularExpression), let mn = Int(apres[r][chiffres]), mn < 60 {
                return (.horaire(heure: h, minute: mn), n + apres.distance(from: apres.startIndex, to: r.upperBound))
            }
            return (.duree(canon(v), .heure), n)
        }
        for (motif, u) in [(#"\s*(?:jours?\b|j(?![a-z]))"#, Valeur.Unite.jour), (#"\s*semaines?\b"#, .semaine), (#"\s*mois\b"#, .mois),
                           (#"\s*ans?\b"#, .an), (#"\s*min(?:utes?)?\b"#, .minute)] {
            if let (_, n) = debut(motif) { return (.duree(canon(v), u), n) }
        }
        if article {                                                    // « un », « une » : un article, sauf devant ces mots
            guard debut(#"\s+(?:ouvriers?|niveaux?|fois)\b"#) != nil else { return (nil, 0) }
        }
        return (.nombre(canon(v)), 0)
    }

    // MARK: Valeurs

    private static func decimal(_ corps: String) -> Decimal {
        Decimal(string: corps.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func entier(_ v: Decimal) -> Int? {
        var r = Decimal(), x = v
        NSDecimalRound(&r, &x, 0, .plain)
        return r == v ? NSDecimalNumber(decimal: v).intValue : nil
    }

    /// Écriture canonique : « 18000000 », « 1.5 » ; deux écritures d'un même nombre donnent le même texte.
    static func canon(_ v: Decimal) -> String { NSDecimalNumber(decimal: v).stringValue }

    // MARK: Nombres en lettres

    private static let petits: [String: Int] = ["zero": 0, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7,
                                                "huit": 8, "neuf": 9, "dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14,
                                                "quinze": 15, "seize": 16]
    private static let dizaines: [String: Int] = ["vingt": 20, "trente": 30, "quarante": 40, "cinquante": 50, "soixante": 60]

    /// Une suite de mots-nombres (« quatre-vingt-dix-huit », « deux trois ») : un ou plusieurs nombres.
    /// Le booléen dit si le nombre est un « un » ou « une » seul (peut-être un article).
    private static func motsEnNombres(_ corps: String) -> [(Decimal, Bool)] {
        let mots = corps.split(whereSeparator: { $0 == "-" || $0 == " " }).map(String.init).filter { $0 != "et" }
        var out: [(Decimal, Bool)] = []
        var total = 0, courant = 0, dernier = ""        // `dernier` : catégorie du mot précédent de ce nombre
        var vide = true, seul = ""
        func clore() {
            if !vide { out.append((Decimal(total + courant), seul == "un" || seul == "une")) }
            total = 0; courant = 0; dernier = ""; vide = true; seul = ""
        }
        for mot in mots {
            let racine = mot.hasSuffix("s") && !["six", "trois", "cents", "vingts"].contains(mot) || ["cents", "vingts"].contains(mot) ? String(mot.dropLast()) : mot
            var categorie = "", valeur = 0
            if let p = petits[racine] { categorie = p >= 10 ? "dix" : "unite"; valeur = p }
            else if let d = dizaines[racine] { categorie = "dizaine"; valeur = d }
            else if racine == "cent" { categorie = "cent" }
            else if ["mille", "million", "milliard"].contains(racine) { categorie = "echelle" }
            else { clore(); continue }
            // Un mot qui ne peut pas suivre le précédent commence un autre nombre.
            let suit: Bool = switch (dernier, categorie) {
            case ("", _): true
            case ("dix", "unite") where valeur >= 7: true                            // dix-sept, soixante-dix-huit
            case ("unite", "cent"), ("dizaine", "unite"), ("dizaine", "dix"), ("cent", "dizaine"), ("cent", "unite"), ("cent", "dix"),
                 ("dix", "echelle"), ("unite", "echelle"), ("dizaine", "echelle"), ("cent", "echelle"), ("echelle", "dizaine"),
                 ("echelle", "unite"), ("echelle", "dix"), ("echelle", "cent"): true
            case ("unite", "dizaine") where courant == 4 && valeur == 20: true      // quatre-vingt
            case ("dizaine", "dix") where courant == 60 || courant == 80: true       // soixante-dix, quatre-vingt-dix
            default: false
            }
            if !suit { clore() }
            if vide { seul = racine; vide = false } else { seul = "" }
            switch categorie {
            case "cent": courant = (courant == 0 ? 1 : courant) * 100
            case "echelle":
                let e = racine == "mille" ? 1_000 : racine == "million" ? 1_000_000 : 1_000_000_000
                total += (courant == 0 ? 1 : courant) * e; courant = 0
            default: courant = (categorie == "dizaine" && dernier == "unite" && courant == 4) ? 80 : courant + valeur
            }
            dernier = categorie
        }
        clore()
        return out
    }

    // MARK: Motifs simples

    private static func motifs(_ liste: [String], dans t: String, _ f: (String, Int) -> Valeur) -> [Lecture] {
        var out: [Lecture] = []
        for (i, motif) in liste.enumerated() {
            guard let re = try? NSRegularExpression(pattern: #"\b(?:"# + motif + #")\b"#) else { continue }
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                let mot = (t as NSString).substring(with: m.range)
                out.append(Lecture(valeur: f(mot, i), extrait: mot))
            }
        }
        return out
    }

    /// Ce que le résumé autorise : toutes ses valeurs, et les minutes d'une heure (« 5 h 20 » donne aussi « 20 min »).
    static func connues(dans resume: String) -> Set<Valeur> {
        var out = Set<Valeur>()
        for l in lire(resume) {
            if case .vague = l.valeur { continue }
            out.insert(l.valeur)
            if case .horaire(_, let m) = l.valeur, m > 0 { out.insert(.duree(String(m), .minute)) }
        }
        return out
    }
}
