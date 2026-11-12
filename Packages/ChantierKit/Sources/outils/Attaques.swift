import ChantierKit
import Foundation

/// Les réponses d'attaque contre les garde-fous (relecture adverse de la PR 23, adaptées au format `{premier, raison, ensuite}`) :
/// chiffres et montants dans la raison, noms étrangers, liste noire, négations, URL, ordre, ressources, caractères
/// qui cachent un chiffre, identifiants hors de la liste fermée. Aucune ne doit être acceptée ; les « contrôles »
/// (raisons honnêtes) doivent l'être, pour que le garde-fou ne rejette pas tout.
enum Attaques {
    struct Cas { let nom: String; let reponse: ReponseConseil }

    static let bonneRaison = "elle débloque d'autres améliorations"

    static func attaques(resume: ResumeConseil, reference: ReferenceData) -> [Cas] {
        guard let p = resume.candidats.first else { return [] }
        let permis = Set(resume.identifiantsPermis)
        let autre = reference.items.first { !permis.contains($0.id) && $0.category != nil }!
        func raison(_ famille: String, _ textes: [String]) -> [Cas] {
            textes.map { Cas(nom: "\(famille) : « \($0.replacingOccurrences(of: "\n", with: "\\n")) »",
                             reponse: ReponseConseil(premier: p.id, raison: $0, ensuite: nil)) }
        }
        func nom(_ n: String) -> String { reference.items.first { $0.name == n }?.name ?? n }
        var cas: [Cas] = []
        cas += raison("chiffre", ["elle coûte 29 M d'or", "prépare 29 M d'élixir", "passe au niveau 10", "c'est le 12e niveau", "plus de 29 M à prévoir",
                                  "passe ton hôtel de ville au niveau 17", "18 000 000 suffisent", "x2 plus vite", "1er niveau", "29%"])
        cas += raison("nombre en lettres", ["deux ouvriers sont libres", "vingt-neuf millions d'élixir", "douze niveaux d'un coup", "en trois jours",
                                            "dix-huit millions", "quatre-vingt-dix-huit points"])
        cas += raison("quantité vague", ["une dizaine de jours", "le double de temps", "la moitié du coût", "un quart de ton temps", "des milliers de points"])
        cas += raison("chiffre déguisé", ["elle coûte ２９ M d'élixir", "niveau ①", "٢٩ millions", "elle coûte 2\u{200B}9 M", "à 7 h 30", "le 9 décembre", "jeudi prochain"])
        var noms = ["il faut aussi le \(nom("Roi des barbares"))", "ton \(nom("Hôtel de ville")) en profite", "améliore aussi la \(nom("Caserne"))",
                    "la \(nom("Reine des archères")) suivra", "\(autre.name) en dépend"]
        if p.poste != .laboratory { noms.append("ton \(nom("Laboratoire")) en dépend") }
        if p.poste != .blacksmith { noms.append("ton \(nom("Forgeron")) en dépend") }
        cas += raison("nom étranger", noms)
        if resume.candidats.count > 1, resume.candidats[1].id != p.id {
            cas.append(Cas(nom: "nom d'un choix non retenu (ensuite nul)",
                           reponse: ReponseConseil(premier: p.id, raison: "avec \(resume.candidats[1].nom) aussi", ensuite: nil)))
        }
        cas += raison("liste noire", ["utilise tes gemmes", "voir http", "regarde www", "voir exemple.com", "ne lance pas cette amélioration", "n'attends rien",
                                      "jamais en retard", "aucun risque", "à faire avant le reste", "d'abord celle-ci", "plus de ressources", "moins de temps",
                                      "environ ça", "améliore tes murs", "elle est prioritaire", "c'est la première", "en tête de ta file", "demain sans faute",
                                      "ce soir", "libère un ouvrier", "avec de l'or", "de l'élixir noir", "du minerai", "presque fini", "non négociable",
                                      "ni l'un ni l'autre", "à lancer maintenant", "pendant le week-end", "en mars"])
        cas += raison("forme", ["elle débloque tout. lance-la", "elle débloque tout; lance aussi", "elle débloque\ntout", String(repeating: "elle débloque ", count: 12),
                                "", "   ", "elle: débloque", "**elle** débloque", "elle débloque 🔥", "elle \"débloque\"", "(elle débloque)", "elle débloque!",
                                "elle débloque…", "<script>", "@pseudo", "#2PP"])
        let valide = bonneRaison
        func ids(_ nom: String, _ premier: Int, _ ensuite: Int?) -> Cas { Cas(nom: nom, reponse: ReponseConseil(premier: premier, raison: valide, ensuite: ensuite)) }
        cas += [ids("premier hors liste : hôtel de ville", 1_000_001, nil), ids("premier inventé", 42, nil), ids("premier à zéro", 0, nil),
                ids("premier négatif", -1, nil), ids("premier : un élément du jeu hors des trois premiers", autre.id, nil),
                ids("ensuite égal à premier", p.id, p.id), ids("ensuite inventé", p.id, 42), ids("ensuite : hôtel de ville", p.id, 1_000_001),
                ids("ensuite hors des trois premiers", p.id, autre.id)]
        return cas
    }

    /// Des raisons honnêtes : elles doivent passer.
    static func controles(resume: ResumeConseil) -> [Cas] {
        guard let p = resume.candidats.first else { return [] }
        let suivant = resume.candidats.dropFirst().first { $0.id != p.id }?.id
        var cas = ["elle débloque d'autres améliorations", "bien placée dans la liste de conseils de son poste", "c'est un héros", "défense clé de la liste de conseils",
                   "peu coûteuse parmi celles de son poste", "elle fait partie de la base de l'armée", "\(p.nom) débloque d'autres améliorations, elle compte pour ton profil"]
            .map { Cas(nom: "contrôle : « \($0) »", reponse: ReponseConseil(premier: p.id, raison: $0, ensuite: nil)) }
        if let suivant {
            cas.append(Cas(nom: "contrôle : avec un second choix", reponse: ReponseConseil(premier: p.id, raison: bonneRaison, ensuite: suivant)))
        }
        return cas
    }
}
