import Foundation

/// Remplace la valeur de chaque champ "tag" par `#2PP`, touche à rien d'autre, et refuse d'écrire
/// si un tag reste ailleurs (un tag hors d'un champ "tag", par exemple dans un texte, fait refuser l'écriture).
enum Anonymiser {
    static let tagFactice = "#2PP"
    // Un tag de joueur : `#` suivi de 3 caractères alphanumériques ou plus, majuscules ou minuscules.
    private static let motifTag = #"#[0-9A-Za-z]{3,}"#
    private static let motifChampTag = ##"("tag"\s*:\s*)"#[0-9A-Za-z]{3,}""##

    enum Erreur: Error, CustomStringConvertible {
        case illisible(String)
        case aucunTag
        case tagRestant(Int)
        var description: String {
            switch self {
            case .illisible(let c): "lecture impossible : \(c)"
            case .aucunTag: "aucun champ \"tag\" trouvé dans l'entrée"
            case .tagRestant(let n): "refus d'écrire : \(n) autre(s) tag(s) restent dans la sortie"
            }
        }
    }

    /// Texte anonymisé, ou une erreur. Les octets hors du tag sont conservés tels quels.
    static func anonymiser(_ texte: String) throws -> String {
        let champ = try NSRegularExpression(pattern: motifChampTag)
        let plein = NSRange(texte.startIndex..., in: texte)
        guard champ.firstMatch(in: texte, range: plein) != nil else { throw Erreur.aucunTag }
        let sortie = champ.stringByReplacingMatches(
            in: texte, range: plein, withTemplate: "$1\"\(tagFactice)\"")
        let tags = try NSRegularExpression(pattern: motifTag)
        let restants = tags.matches(in: sortie, range: NSRange(sortie.startIndex..., in: sortie))
            .filter { (Range($0.range, in: sortie).map { String(sortie[$0]) }) != tagFactice }
        guard restants.isEmpty else { throw Erreur.tagRestant(restants.count) }
        return sortie
    }

    static func lancer(entrée: String, sortie: String) throws {
        guard let texte = try? String(contentsOfFile: entrée, encoding: .utf8) else {
            throw Erreur.illisible(entrée)
        }
        try Data(anonymiser(texte).utf8).write(to: URL(fileURLWithPath: sortie))
    }
}
