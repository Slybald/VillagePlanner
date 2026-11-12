import Foundation
import Synchronization

// Téléchargement des sources par `gh api` (jamais curl ni wget) dans un cache ignoré par git :
// `Packages/ChantierKit/.cache/maj-reference/<source>/<commit>/`. Un commit déjà en cache n'est
// pas retéléchargé ; `--cache` travaille sans réseau sur les derniers commits téléchargés.

struct SourceDistante: Codable {
    let depot: String          // "propriétaire/nom"
    let chemin: String         // dossier des données dans le dépôt
    let licence: String
}

struct Instantane: Codable {
    let commit: String
    let date: String
}

let clashKing = SourceDistante(depot: "ClashKingInc/ClashKingAssets", chemin: "assets/static_data",
                               licence: "GPL-3.0")
let chiefpansancolt = SourceDistante(depot: "chiefpansancolt/clash-of-clans-data", chemin: "data/home",
                                     licence: "MIT")

enum Telechargement {
    enum Erreur: Error, CustomStringConvertible {
        case gh(String, String)
        case pasDeCache(String)
        var description: String {
            switch self {
            case .gh(let a, let e): "gh api \(a) a échoué : \(e)"
            case .pasDeCache(let c): "aucun téléchargement en cache (\(c)) : relancer sans --cache"
            }
        }
    }

    static func gh(_ arguments: [String]) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["gh", "api"] + arguments
        let sortie = Pipe(), erreur = Pipe()
        p.standardOutput = sortie
        p.standardError = erreur
        try p.run()
        let data = sortie.fileHandleForReading.readDataToEndOfFile()
        let texteErreur = String(decoding: erreur.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Erreur.gh(arguments.joined(separator: " "), texteErreur) }
        return data
    }

    /// Dernier commit qui touche le dossier des données.
    static func dernierCommit(_ s: SourceDistante) throws -> Instantane {
        let ligne = String(decoding: try gh(["repos/\(s.depot)/commits?path=\(s.chemin)&per_page=1",
                                             "--jq", ".[0] | .sha + \" \" + .commit.committer.date"]),
                           as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let parties = ligne.split(separator: " ")
        guard parties.count == 2 else { throw Erreur.gh("commits \(s.depot)", "réponse inattendue : \(ligne)") }
        return Instantane(commit: String(parties[0]), date: String(parties[1]))
    }

    /// Fichiers JSON du dossier des données, au commit donné (chemins relatifs à la racine du dépôt).
    static func listerJSON(_ s: SourceDistante, commit: String) throws -> [String] {
        String(decoding: try gh(["repos/\(s.depot)/git/trees/\(commit)?recursive=1",
                                 "--jq", ".tree[] | select(.type == \"blob\") | .path"]), as: UTF8.self)
            .split(separator: "\n").map(String.init)
            .filter { $0.hasPrefix(s.chemin + "/") && $0.hasSuffix(".json") }
    }

    /// Télécharge les fichiers dans `dossier` (créé à côté puis renommé : jamais de cache à moitié écrit).
    static func telecharger(_ s: SourceDistante, commit: String, chemins: [String], vers dossier: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dossier.path) { return }
        let partiel = dossier.appendingPathExtension("partiel")
        try? fm.removeItem(at: partiel)
        let erreurs = Mutex<[String]>([])
        DispatchQueue.concurrentPerform(iterations: chemins.count) { i in
            let chemin = chemins[i]
            do {
                let data = try gh(["-H", "Accept: application/vnd.github.raw",
                                   "repos/\(s.depot)/contents/\(chemin)?ref=\(commit)"])
                let cible = partiel.appendingPathComponent(String(chemin.dropFirst(s.chemin.count + 1)))
                try FileManager.default.createDirectory(at: cible.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cible)
            } catch { erreurs.withLock { $0.append("\(chemin) : \(error)") } }
        }
        let liste = erreurs.withLock { $0 }
        guard liste.isEmpty else { throw Erreur.gh(s.depot, liste.sorted().joined(separator: "\n")) }
        try fm.moveItem(at: partiel, to: dossier)
    }
}
