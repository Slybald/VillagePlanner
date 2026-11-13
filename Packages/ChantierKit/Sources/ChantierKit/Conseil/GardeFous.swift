import Foundation

// Les garde-fous (PLAN §6.2). Le modèle ne produit plus de consigne : il choisit des identifiants dans une liste fermée
// (le schéma de la requête les énumère) et écrit UNE raison. L'app compose la consigne à partir du plan : aucune valeur
// chiffrée, aucune date, aucun nom d'élément ne vient du modèle.
//  G1  aucun chiffre inventé : la raison ne contient ni chiffre, ni nombre en lettres, ni heure, date, jour, montant, ni
//      quantité vague (Nombres.swift) ;
//  G2  aucun identifiant ni nom inventé : `premier` et `ensuite` sont parmi les trois premiers lancements du plan (le
//      schéma le dit, l'app le revérifie) et la raison ne nomme que ces éléments (plus le poste du premier : laboratoire,
//      forgeron, animalerie) ;
//  G3  repli silencieux : tout échec (voir `Conseiller`) montre la consigne du moteur, sans alerte.
// La raison est aussi bornée dans sa forme : une phrase française de 140 caractères au plus (trois mots, un mot outil), faite de
// lettres latines, d'espaces, de virgules, d'apostrophes et de traits d'union ; ni chiffre romain, ni ordinal, ni négation, ni mot de la
// liste noire, ni mot à majuscule qui ne soit un nom permis. Une raison qui contredirait
// le plan par ses seuls mots (« ne lance pas », « d'abord », « plus de ») ne passe pas.
// Décision : un nom du jeu qui n'est pas celui de `premier`, de `ensuite` ou de leur poste fait rejeter la réponse, même de
// bonne foi : un garde-fou trop prudent coûte un repli, un garde-fou trop lâche coûte une fausse consigne.

/// La réponse structurée du modèle.
public struct ReponseConseil: Decodable, Sendable, Equatable {
    public let premier: Int
    public let raison: String
    public let ensuite: Int?

    public init(premier: Int, raison: String, ensuite: Int?) {
        self.premier = premier
        self.raison = raison
        self.ensuite = ensuite
    }
}

/// Pourquoi une réponse est rejetée. Jamais montré à l'écran (G3).
public enum MotifRejet: Error, Equatable, Sendable {
    case vide
    case trop(caracteres: Int)
    case nombre(String)            // G1
    case identifiant(Int)          // G2
    case nom(String)               // G2
    case interdit(String)          // forme : caractère, négation, liste noire
}

public enum Verdict: Equatable, Sendable {
    /// La consigne composée par l'app, et jusqu'à quand elle vaut (le début du premier lancement, s'il est à venir).
    case acceptee(texte: String, jusqua: Date?)
    case refusee(MotifRejet)
}

public enum GardeFous {
    public static let raisonMax = 140

    /// Mots et tournures refusés dans la raison : affirmations de date, d'ordre, de rang, de quantité, de ressource, de négation ou
    /// de jugement que rien ne vérifie (listes de la relecture adverse, PR 23, élargies). « plus » et « moins » seuls sont permis
    /// (« la plus utile ») : seuls « plus de » et « moins de » sont refusés, avec les négations.
    static let listeNoire = [
        "gemmes?", "http", "https", "www", "avant", "apres", "d'abord", "premier", "premiere", "premiers", "premieres", "second", "seconde",
        "dernier", "derniere", "derniers", "dernieres", "prioritaire", "priorite", "en tete", "en priorite", "ne", "pas", "rien", "jamais",
        "aucun", "aucune", "nul", "nulle", "non", "ni", "plus de", "moins de", "environ", "presque", "quasi", "mur", "murs", "rempart",
        "remparts", "ressources?", "or", "elixir", "minerai", "ouvriers?", "libres?", "libere", "liberent", "maintenant", "demain", "hier",
        "aujourd'hui", "soir", "matin", "nuit", "midi", "semaines?", "jours?", "heures?", "minutes?", "mois", "ans?", "annees?", "week-end",
        "janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout", "septembre", "octobre", "novembre", "decembre",
        "inutiles?", "facultatifs?", "facultatives?", "sauter", "saute", "ignore", "ignorer", "reporte", "reporter", "secondaires?",
        "dangereu(?:x|ses?)", "gratuites?", "gratuits?", "terminees?", "termines?", "tout de suite",
    ]
    private static let motifListeNoire = try! NSRegularExpression(
        pattern: #"(?<![a-z])(?:"# + listeNoire.joined(separator: "|") + #")(?![a-z])|(?<![a-z])n'|[a-z]+ieme(?:s)?(?![a-z])"#)
    /// Mots outils du français : une raison en contient au moins un (et compte au moins trois mots).
    private static let motsOutils: Set<String> = ["de", "du", "des", "la", "le", "les", "un", "une", "ton", "ta", "tes", "il", "elle", "ils", "elles", "pour",
                                                  "et", "qui", "que", "dans", "sur", "avec", "ce", "cette", "c", "d", "l", "au", "aux", "son", "sa", "ses"]
    private static let motifRomain = try! NSRegularExpression(
        pattern: #"(?<![A-Za-zÀ-ÿ])(?:[IVXLCDM]+(?![’'])|(?=[ivxlcdm]{3})m{0,3}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{0,3}))(?![A-Za-zÀ-ÿ])"#)

    /// Lettres latines (U+0041 à U+024F) seulement, avec espace, virgule, apostrophes et trait d'union : ni cyrillique, ni grec,
    /// ni accent combinant, ni symbole.
    private static func autorise(_ c: Unicode.Scalar) -> Bool {
        if " ,'’-".unicodeScalars.contains(c) { return true }
        return (0x41...0x24F).contains(c.value) && c.properties.isAlphabetic
    }

    public static func verifier(_ reponse: ReponseConseil, resume: ResumeConseil, reference: ReferenceData) -> Verdict {
        // G2 : les identifiants (le schéma de la requête les énumère déjà ; l'app ne s'y fie pas).
        // `premier` démarre au tout premier moment du plan ; `ensuite` en même temps ou après.
        guard let premier = resume.candidat(reponse.premier), premier.debut == resume.premierMoment else { return .refusee(.identifiant(reponse.premier)) }
        var ensuite: PasCandidat?
        if let id = reponse.ensuite {
            guard id != reponse.premier, let c = resume.candidat(id), c.debut >= premier.debut else { return .refusee(.identifiant(id)) }
            ensuite = c
        }
        // G2 : les noms d'éléments (ceux de `premier`, de `ensuite`, de leur poste et de leurs prérequis).
        var permis = Set([premier.id] + premier.prerequis + (ensuite.map { [$0.id] + $0.prerequis } ?? []))
        for poste in [premier.poste] + (ensuite.map { [$0.poste] } ?? []) {
            let nom: String? = switch poste {
            case .laboratory: "Laboratoire"
            case .blacksmith: "Forgeron"
            case .petHouse: "Animalerie"
            case .builder: nil
            }
            if let nom { permis.formUnion(reference.items.filter { $0.name == nom }.map(\.id)) }
        }
        switch verifierRaison(reponse.raison, permis: permis, reference: reference) {
        case .failure(let motif): return .refusee(motif)
        case .success(let raison):
            return .acceptee(texte: resume.composer(premier: premier, raison: raison, ensuite: ensuite),
                             jusqua: premier.maintenant ? nil : premier.debut)
        }
    }

    /// La phrase d'un modèle (une raison, ou l'explication d'une question) : une phrase française courte, sans chiffre ni date, qui ne
    /// nomme que les éléments de `permis` (G1, G2). Rend la phrase nettoyée. Partagée par le conseiller (T20) et les questions (T21).
    public static func verifierRaison(_ brut: String, permis: Set<Int>, reference: ReferenceData) -> Result<String, MotifRejet> {
        // La raison : une phrase, un point ou un point d'exclamation final au plus.
        var raison = brut.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        if raison.hasSuffix(".") || raison.hasSuffix("!") { raison.removeLast() }
        if raison.isEmpty { return .failure(.vide) }
        if raison.count > raisonMax { return .failure(.trop(caracteres: raison.count)) }
        // G1 : ni chiffre (de toute écriture), ni nombre, heure, date, jour ou quantité vague.
        if let c = raison.first(where: { $0.isNumber }) { return .failure(.nombre(String(c))) }
        if let l = Nombres.lire(raison).first { return .failure(.nombre(l.extrait)) }
        // Forme : lettres latines, espaces, virgules, apostrophes, traits d'union ; pas de chiffres romains.
        if let c = raison.unicodeScalars.first(where: { !autorise($0) }) { return .failure(.interdit(String(c))) }
        let tout = NSRange(raison.startIndex..., in: raison)
        if let m = motifRomain.firstMatch(in: raison, range: tout) { return .failure(.nombre((raison as NSString).substring(with: m.range))) }
        // Une vraie phrase française : trois mots au moins, dont un mot outil.
        let mots = raison.split(whereSeparator: { $0 == " " })
        let replie = Nombres.replier(raison)
        let jetons = replie.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if mots.count < 3 || !jetons.contains(where: motsOutils.contains) { return .failure(.interdit("phrase")) }
        for (id, nom) in nomsCites(raison, reference: reference).sorted(by: { $0.key < $1.key }) where !permis.contains(id) {
            return .failure(.nom(nom))
        }
        // Tout mot à majuscule, hors début de phrase, est un nom : il doit être l'un de ceux qui viennent d'être permis.
        var reste = raison
        let noms = permis.compactMap { reference.name(of: $0) }.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        if !noms.isEmpty, let re = try? NSRegularExpression(pattern: #"(?<![\p{L}])(?:"# + noms.joined(separator: "|") + #")s?(?![\p{L}])"#, options: .caseInsensitive) {
            reste = re.stringByReplacingMatches(in: raison, range: tout, withTemplate: " ")
        }
        let lettres = try! NSRegularExpression(pattern: #"\p{L}+"#)
        let jetonsReste = lettres.matches(in: reste, range: NSRange(reste.startIndex..., in: reste))
        for m in jetonsReste.dropFirst(raison.first?.isLetter == true && reste.first?.isLetter == true ? 1 : 0) {
            let mot = (reste as NSString).substring(with: m.range)
            if mot.first?.isUppercase == true { return .failure(.nom(mot)) }
        }
        // Liste noire.
        if let m = motifListeNoire.firstMatch(in: replie, range: NSRange(replie.startIndex..., in: replie)) {
            return .failure(.interdit((replie as NSString).substring(with: m.range)))
        }
        return .success(raison)
    }

    /// Les éléments nommés dans `texte` : identifiant (l'un de ceux qui portent ce nom) → nom replié.
    static func nomsCites(_ texte: String, reference: ReferenceData) -> [Int: String] {
        let t = Nombres.replier(texte)
        var parNom: [String: [Int]] = [:]
        for item in reference.items { parNom[Nombres.replier(item.name), default: []].append(item.id) }
        let motif = parNom.keys.filter { !$0.isEmpty }.sorted { ($0.count, $0) > ($1.count, $1) }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        guard !motif.isEmpty, let re = try? NSRegularExpression(pattern: #"(?<![a-z0-9])(?:"# + motif + #")s?(?![a-z0-9])"#) else { return [:] }
        var out: [Int: String] = [:]
        for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
            var nom = (t as NSString).substring(with: m.range)
            if parNom[nom] == nil, nom.hasSuffix("s") { nom.removeLast() }
            for id in parNom[nom] ?? [] { out[id] = nom }
        }
        return out
    }
}
