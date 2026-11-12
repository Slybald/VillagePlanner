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
// La raison est aussi bornée dans sa forme : une phrase de 140 caractères au plus, faite de lettres, d'espaces, de virgules,
// d'apostrophes et de traits d'union ; elle ne contient ni négation, ni mot de la liste noire. Une raison qui contredirait
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
public enum MotifRejet: Equatable, Sendable {
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

    /// Mots et tournures refusés dans la raison : affirmations de date, d'ordre, de quantité, de ressource ou de négation
    /// que rien ne vérifie (liste de la relecture adverse, PR 23, élargie).
    static let listeNoire = [
        "gemmes?", "http", "https", "www", "avant", "apres", "d'abord", "premier", "premiere", "premiers", "prioritaire", "priorite",
        "en tete", "en priorite", "ne", "pas", "rien", "jamais", "aucun", "aucune", "nul", "nulle", "non", "ni", "plus", "moins",
        "environ", "presque", "quasi", "mur", "murs", "rempart", "remparts", "ressources?", "or", "elixir", "minerai", "ouvriers?",
        "libres?", "libere", "liberent", "maintenant", "demain", "hier", "aujourd'hui", "soir", "matin", "nuit", "semaines?", "jours?",
        "heures?", "minutes?", "mois", "ans?", "week-end", "janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout",
        "septembre", "octobre", "novembre", "decembre",
    ]
    private static let motifListeNoire = try! NSRegularExpression(
        pattern: #"(?<![a-z])(?:"# + listeNoire.joined(separator: "|") + #")(?![a-z])|(?<![a-z])n'"#)
    private static let autorises = CharacterSet.letters.union(CharacterSet(charactersIn: " ,'’-"))

    public static func verifier(_ reponse: ReponseConseil, resume: ResumeConseil, reference: ReferenceData) -> Verdict {
        // G2 : les identifiants (le schéma de la requête les énumère déjà ; l'app ne s'y fie pas).
        guard let premier = resume.candidat(reponse.premier) else { return .refusee(.identifiant(reponse.premier)) }
        var ensuite: PasCandidat?
        if let id = reponse.ensuite {
            guard id != reponse.premier, let c = resume.candidat(id) else { return .refusee(.identifiant(id)) }
            ensuite = c
        }
        // La raison : une phrase, un point final au plus.
        var raison = reponse.raison.trimmingCharacters(in: .whitespacesAndNewlines)
        if raison.hasSuffix(".") { raison.removeLast() }
        if raison.isEmpty { return .refusee(.vide) }
        if raison.count > raisonMax { return .refusee(.trop(caracteres: raison.count)) }
        // G1 : ni chiffre (de toute écriture), ni nombre, heure, date, jour ou quantité vague.
        if let c = raison.first(where: { $0.isNumber }) { return .refusee(.nombre(String(c))) }
        if let l = Nombres.lire(raison).first { return .refusee(.nombre(l.extrait)) }
        // G2 : les noms d'éléments.
        var permis = Set([premier.id] + (ensuite.map { [$0.id] } ?? []))
        for poste in [premier.poste] + (ensuite.map { [$0.poste] } ?? []) {
            let nom: String? = switch poste {
            case .laboratory: "Laboratoire"
            case .blacksmith: "Forgeron"
            case .petHouse: "Animalerie"
            case .builder: nil
            }
            if let nom { permis.formUnion(reference.items.filter { $0.name == nom }.map(\.id)) }
        }
        for (id, nom) in nomsCites(raison, reference: reference).sorted(by: { $0.key < $1.key }) where !permis.contains(id) {
            return .refusee(.nom(nom))
        }
        // Forme : lettres, espaces, virgules, apostrophes, traits d'union ; pas de liste noire.
        if let c = raison.unicodeScalars.first(where: { !autorises.contains($0) }) { return .refusee(.interdit(String(c))) }
        let replie = Nombres.replier(raison)
        if let m = motifListeNoire.firstMatch(in: replie, range: NSRange(replie.startIndex..., in: replie)) {
            return .refusee(.interdit((replie as NSString).substring(with: m.range)))
        }
        return .acceptee(texte: resume.composer(premier: premier, raison: raison, ensuite: ensuite),
                         jusqua: premier.maintenant ? nil : premier.debut)
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
