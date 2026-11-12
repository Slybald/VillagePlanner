import ChantierKit
import Foundation
import Synchronization

// `swift run --package-path Packages/ChantierKit outils maj-images`
// Télécharge par `gh api` les illustrations de ClashKingAssets (bâtiments et pièges à chaque niveau, icône des
// unités, héros, familiers et équipements) pour les éléments qui comptent dans l'avancement, plus deux décors.
// Idempotent : un fichier déjà présent n'est pas retéléchargé. Écrit la liste des éléments sans image.

enum MajImages {
    static let depot = "ClashKingInc/ClashKingAssets"
    static let sortie = MajReference.paquet
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Ressources/Illustrations")
    static let rapport = MajReference.cache.deletingLastPathComponent().appendingPathComponent("maj-images/rapport.md")

    /// Décors du terrain de l'écran Cap : jour (thème clair) et nuit (thème sombre).
    static let decors = ["decor-jour.webp": "assets/sceneries/jungle_scenery/thumbnail.webp",
                         "decor-nuit.webp": "assets/sceneries/classic_scenery/thumbnail.webp"]

    /// Icônes des six ressources (écran Chantier) : `ressource-<nom>.webp`, nommées comme `Resource.rawValue` en snake_case.
    static let ressources = Dictionary(uniqueKeysWithValues: ["gold", "elixir", "dark_elixir", "shiny_ore", "glowy_ore", "starry_ore"]
        .map { ("ressource-\($0).webp", "assets/resources/\($0).webp") })

    /// Règle de nommage du README de ClashKingAssets.
    static func nomNettoye(_ nom: String) -> String {
        nom.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "?", with: "").replacingOccurrences(of: "\\q", with: "")
            .replacingOccurrences(of: "’", with: "")
    }

    /// Fichier local → chemin dans le dépôt. Un fichier par niveau pour les bâtiments et les pièges
    /// (`<id>_<niveau>.webp`), une icône sinon (`<id>.webp`). Hors avancement : rien.
    static func fichiers(_ item: ReferenceItem) -> [(local: String, distant: String)] {
        guard item.category != nil, let en = item.names["en"] else { return [] }
        let n = nomNettoye(en)
        func niveaux(_ dossier: String) -> [(String, String)] {
            item.levels.map { ("\(item.id)_\($0.level).webp", "assets/\(dossier)/\(n)/level_\($0.level).webp") }
        }
        let icone: String
        switch item.section {
        case "buildings": return niveaux("buildings/home-village")
        case "traps": return niveaux("traps/home-village")
        case "units", "siege_machines": icone = "assets/troops/\(n)/icon.webp"
        case "spells": icone = "assets/spells/\(n).webp"
        case "heroes": icone = "assets/heroes/\(n)/icon.webp"
        case "pets": icone = "assets/pets/\(n)/icon.webp"
        case "equipment": icone = "assets/equipment/\(n).webp"
        default: return []
        }
        return [("\(item.id).webp", icone)]
    }

    static func lancer() throws {
        let reference = try ReferenceData.load()
        let commit = String(decoding: try Telechargement.gh(["repos/\(depot)/commits/main", "--jq", ".sha"]), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let presents = Set(String(decoding: try Telechargement.gh(["repos/\(depot)/git/trees/\(commit)?recursive=1",
                                                                   "--jq", ".tree[] | select(.type == \"blob\") | .path"]),
                                  as: UTF8.self).split(separator: "\n").map(String.init))

        var voulus = (decors.merging(ressources) { a, _ in a }).map { (local: $0.key, distant: $0.value) }
        var sansImage: [String] = []
        for item in reference.items {
            let f = fichiers(item)
            let manquants = f.filter { !presents.contains($0.distant) }
            if !manquants.isEmpty {
                let detail = f.count > 1 ? " : niveaux " + manquants.map { String($0.local.split(separator: "_")[1].dropLast(5)) }.joined(separator: ", ") : ""
                sansImage.append("- \(item.names["en"] ?? "#\(item.id)") (\(item.id))\(detail), cherché \(manquants[0].distant)")
            }
            voulus += f.filter { presents.contains($0.distant) }
        }

        let fm = FileManager.default
        try fm.createDirectory(at: sortie, withIntermediateDirectories: true)
        let aTelecharger = voulus.filter {
            ((try? fm.attributesOfItem(atPath: sortie.appendingPathComponent($0.local).path))?[.size] as? Int ?? 0) == 0
        }
        print("\(voulus.count) images voulues, \(aTelecharger.count) à télécharger (\(depot) @ \(commit.prefix(7)))")
        let erreurs = Mutex<[String]>([])
        DispatchQueue.concurrentPerform(iterations: aTelecharger.count) { i in
            let f = aTelecharger[i]
            do {
                let data = try Telechargement.gh(["-H", "Accept: application/vnd.github.raw",
                                                  "repos/\(depot)/contents/\(f.distant)?ref=\(commit)"])
                // Écrit à côté puis renomme : jamais d'image à moitié écrite.
                let cible = sortie.appendingPathComponent(f.local)
                let partiel = cible.appendingPathExtension("partiel")
                try data.write(to: partiel)
                _ = try? FileManager.default.removeItem(at: cible)
                try FileManager.default.moveItem(at: partiel, to: cible)
            } catch { erreurs.withLock { $0.append("\(f.distant) : \(error)") } }
        }

        let texte = """
            # Rapport de maj-images

            - Source : \(depot), commit \(commit) (images servies aussi sur assets.clashk.ing ; crédit demandé par le README)
            - \(voulus.count) images voulues, \(aTelecharger.count) téléchargées cette fois

            ## Éléments sans image

            \(sansImage.isEmpty ? "Aucun." : sansImage.joined(separator: "\n"))
            """
        try fm.createDirectory(at: rapport.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texte.utf8).write(to: rapport)
        print(sansImage.isEmpty ? "aucun élément sans image" : "sans image :\n" + sansImage.joined(separator: "\n"))
        print("rapport : \(rapport.path)")
        let liste = erreurs.withLock { $0 }
        guard liste.isEmpty else { throw Telechargement.Erreur.gh(depot, liste.sorted().joined(separator: "\n")) }
    }
}
