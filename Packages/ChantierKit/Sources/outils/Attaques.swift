import ChantierKit
import Foundation

/// Les réponses d'attaque contre les garde-fous (relecture adverse de la PR 23, adaptées au format `{premier, raison, ensuite}`) :
/// chiffres et montants dans la raison, noms étrangers, liste noire, négations, URL, ordre, ressources, caractères
/// qui cachent un chiffre, identifiants hors de la liste fermée. Aucune ne doit être acceptée ; les « contrôles »
/// (raisons honnêtes) doivent l'être, pour que le garde-fou ne rejette pas tout.
enum Attaques {
    struct Cas { let nom: String; let reponse: ReponseConseil }

    static let bonneRaison = "elle débloque d'autres améliorations"

    /// Un début de phrase honnête, devant chaque attaque : elle est alors refusée pour sa propre faute (le chiffre, le nom, le mot
    /// interdit), pas parce que la raison serait trop courte.
    static func sain(_ t: String) -> String { "elle compte pour ton profil, " + t }

    static func attaques(resume: ResumeConseil, reference: ReferenceData) -> [Cas] {
        guard let p = resume.candidats.first else { return [] }
        let permis = Set(resume.identifiantsPermis)
        let autre = reference.items.first { !permis.contains($0.id) && $0.category != nil }!
        func raison(_ famille: String, _ textes: [String], prefixe: Bool = true) -> [Cas] {
            textes.map { Cas(nom: "\(famille) : « \($0.replacingOccurrences(of: "\n", with: "\\n")) »",
                             reponse: ReponseConseil(premier: p.id, raison: prefixe ? sain($0) : $0, ensuite: nil)) }
        }
        func nom(_ n: String) -> String { reference.items.first { $0.name == n }?.name ?? n }
        var cas: [Cas] = []
        cas += raison("chiffre", ["elle coûte 29 M d'or", "prépare 29 M d'élixir", "passe au niveau 10", "c'est le 12e niveau", "plus de 29 M à prévoir",
                                  "passe ton hôtel de ville au niveau 17", "18 000 000 suffisent", "x2 plus vite", "1er niveau", "29%"])
        cas += raison("nombre en lettres", ["deux ouvriers sont libres", "vingt-neuf millions d'élixir", "douze niveaux d'un coup", "en trois jours",
                                            "dix-huit millions", "quatre-vingt-dix-huit points"])
        cas += raison("quantité vague", ["une dizaine de jours", "le double de temps", "la moitié du coût", "un quart de ton temps", "des milliers de points"])
        cas += raison("chiffre déguisé", ["elle coûte ２９ M d'élixir", "niveau ①", "٢٩ millions", "elle coûte 2\u{200B}9 M", "à 7 h 30", "le 9 décembre", "jeudi prochain"])
        cas += raison("chiffre romain", ["passe au niveau XII", "l'\(p.nom) IX", "niveau xii", "année MMXXVI", "le niveau viii"])
        cas += raison("ordinal", ["c'est le douzième niveau", "la deuxième de ta liste", "la troisième amélioration", "en seconde position", "à ne pas rater en dernier"])
        cas += raison("homoglyphe ou accent combinant", ["nе lance pаs ça", "zе\u{0301}ro risque, lance la", "lаnce la vite", "elle compte pour ton prоfil", "a\u{0308}\u{0301} compter pour toi"], prefixe: false)
        var noms = ["il faut aussi le \(nom("Roi des barbares"))", "améliore aussi la \(nom("Caserne"))", "la \(nom("Reine des archères")) suivra",
                    "\(autre.name) en dépend", "la Tour d'archère en profite", "la Forteresse des ombres en profite", "le Grand Gardien en profite"]
        if !p.prerequis.contains(1_000_001), p.id != 1_000_001 { noms.append("ton \(nom("Hôtel de ville")) en profite") }
        if p.poste != .laboratory { noms.append("ton \(nom("Laboratoire")) en dépend") }
        if p.poste != .blacksmith { noms.append("ton \(nom("Forgeron")) en dépend") }
        cas += raison("nom étranger", noms)
        if resume.candidats.count > 1, resume.candidats[1].id != p.id {
            cas.append(Cas(nom: "nom d'un choix non retenu (ensuite nul)",
                           reponse: ReponseConseil(premier: p.id, raison: sain("avec \(resume.candidats[1].nom) aussi"), ensuite: nil)))
        }
        cas += raison("liste noire", ["utilise tes gemmes", "voir http", "regarde www", "voir exemple.com", "ne lance pas cette amélioration", "n'attends rien",
                                      "jamais en retard", "aucun risque", "à faire avant le reste", "d'abord celle-ci", "plus de ressources", "moins de temps",
                                      "environ ça", "améliore tes murs", "elle est prioritaire", "c'est la première", "en tête de ta file", "demain sans faute",
                                      "ce soir", "libère un ouvrier", "avec de l'or", "de l'élixir noir", "du minerai", "presque fini", "non négociable",
                                      "ni l'un ni l'autre", "à lancer maintenant", "pendant le week-end", "en mars", "elle est inutile", "elle est facultative",
                                      "tu peux sauter celle-ci", "ignore celle-ci", "reporte celle-ci", "c'est la dernière", "elle est secondaire", "elle est dangereuse",
                                      "elle est gratuite", "elle est terminée", "à faire tout de suite", "avant midi", "d'ici l'année prochaine"])
        cas += raison("pas une phrase française", ["ok", "bof", "do not launch this one", "skip it and wait", "just wait it out"], prefixe: false)
        cas += raison("forme", ["elle débloque tout. lance-la", "elle débloque tout; lance aussi", "elle débloque\ntout", String(repeating: "elle débloque ", count: 12),
                                "", "   ", "elle: débloque", "**elle** débloque", "elle débloque 🔥", "elle \"débloque\"", "(elle débloque)", "elle débloque ?",
                                "elle débloque…", "<script>", "@pseudo", "#2PP"], prefixe: false)
        let valide = bonneRaison
        func ids(_ nom: String, _ premier: Int, _ ensuite: Int?) -> Cas { Cas(nom: nom, reponse: ReponseConseil(premier: premier, raison: valide, ensuite: ensuite)) }
        cas += [ids("premier hors liste : hôtel de ville", 1_000_001, nil), ids("premier inventé", 42, nil), ids("premier à zéro", 0, nil),
                ids("premier négatif", -1, nil), ids("premier : un élément du jeu hors des trois premiers", autre.id, nil),
                ids("ensuite égal à premier", p.id, p.id), ids("ensuite inventé", p.id, 42), ids("ensuite : hôtel de ville", p.id, 1_000_001),
                ids("ensuite hors des trois premiers", p.id, autre.id)]
        // Un pas qui ne démarre pas au tout premier moment ne peut pas être `premier` (et un `ensuite` plus tôt que lui non plus).
        if let tard = resume.candidats.first(where: { $0.debut > p.debut }) {
            cas += [ids("premier : un pas qui démarre plus tard", tard.id, nil), ids("premier plus tard, ensuite plus tôt", tard.id, p.id)]
        }
        return cas
    }

    /// Des raisons honnêtes : elles doivent passer.
    static func controles(resume: ResumeConseil) -> [Cas] {
        guard let p = resume.candidats.first else { return [] }
        let suivant = resume.candidats.dropFirst().first { $0.id != p.id }?.id
        var cas = ["elle débloque d'autres améliorations", "bien placée dans la liste de conseils de son poste", "c'est un héros", "défense clé de la liste de conseils",
                   "peu coûteuse parmi celles de son poste", "elle fait partie de la base de l'armée", "\(p.nom) débloque d'autres améliorations, elle compte pour ton profil", "elle débloque d'autres améliorations!",
                   "c'est la plus utile pour ton profil", "elle est plus forte que les autres"]
            .map { Cas(nom: "contrôle : « \($0) »", reponse: ReponseConseil(premier: p.id, raison: $0, ensuite: nil)) }
        if let suivant {
            cas.append(Cas(nom: "contrôle : avec un second choix", reponse: ReponseConseil(premier: p.id, raison: bonneRaison, ensuite: suivant)))
        }
        return cas
    }
}
