import Foundation

// Les garde-fous (PLAN §6.2) : une réponse du modèle n'est montrée que si elle ne dit rien que le résumé ne dise.
//  G1  aucun chiffre inventé : chaque nombre, heure, date, niveau du texte figure dans le résumé (Nombres.swift) ;
//  G2  aucun identifiant ni nom inventé : les identifiants cités et les noms d'éléments du texte sont ceux du résumé ;
//  G3  repli silencieux : tout échec (voir `Conseiller`) montre la consigne du moteur, sans alerte.
// S'y ajoute la forme : trois phrases au plus, et pas de texte vide.
// Décisions :
//  - un nom est reconnu par les noms français de `ReferenceData.name(of:)`, en minuscules sans accents, à la limite
//    des mots, avec un « s » de pluriel possible ; le plus long gagne (« Canon à ricochet » n'est pas « Canon ») ;
//  - un nom du jeu qui n'est pas dans le résumé fait rejeter la réponse, même s'il est de bonne foi : un garde-fou
//    trop prudent coûte un repli, un garde-fou trop lâche coûte une fausse consigne.

/// La réponse structurée du modèle : un texte, et les identifiants des améliorations qu'il nomme.
public struct ReponseConseil: Decodable, Sendable, Equatable {
    public let texte: String
    public let ids: [Int]

    public init(texte: String, ids: [Int]) {
        self.texte = texte
        self.ids = ids
    }

    /// Le schéma JSON imposé à l'API (`output_config.format`).
    public static let schema = #"{"type":"object","properties":{"texte":{"type":"string"},"ids":{"type":"array","items":{"type":"integer"}}},"required":["texte","ids"],"additionalProperties":false}"#
}

/// Pourquoi une réponse est rejetée. Jamais montré à l'écran (G3).
public enum MotifRejet: Equatable, Sendable {
    case vide
    case trop(phrases: Int)
    case nombre(String)           // G1
    case identifiant(Int)         // G2
    case nom(String)              // G2
}

public enum Verdict: Equatable, Sendable {
    case acceptee(String)
    case refusee(MotifRejet)
}

public enum GardeFous {
    public static let phrasesMax = 3
    public static let caracteresMax = 500

    public static func verifier(_ reponse: ReponseConseil, resume: ResumeConseil, reference: ReferenceData) -> Verdict {
        let texte = reponse.texte.trimmingCharacters(in: .whitespacesAndNewlines)
        if texte.isEmpty { return .refusee(.vide) }
        let phrases = nombreDePhrases(texte)
        if phrases > phrasesMax || texte.count > caracteresMax { return .refusee(.trop(phrases: phrases)) }
        // G2
        if let id = reponse.ids.first(where: { !resume.identifiants.contains($0) }) { return .refusee(.identifiant(id)) }
        let autorises = nomsCites(resume.texte, reference: reference)
        for (id, nom) in nomsCites(texte, reference: reference).sorted(by: { $0.key < $1.key }) where autorises[id] == nil {
            return .refusee(.nom(nom))
        }
        // G1
        let connues = Nombres.connues(dans: resume.texte)
        if let inconnu = Nombres.lire(texte).first(where: { !connues.contains($0.valeur) }) { return .refusee(.nombre(inconnu.extrait)) }
        return .acceptee(texte)
    }

    /// Les phrases : coupées après « . », « ! », « ? » suivis d'une espace (« 1.5 » ne coupe pas, ni un point final).
    static func nombreDePhrases(_ texte: String) -> Int {
        texte.replacingOccurrences(of: #"(?<=[.!?…])\s+"#, with: "\n", options: .regularExpression)
            .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
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
