import Foundation

/// Le conteneur partagé avec le widget (T25). Les photos et leur index restent TOUJOURS dans Application Support :
/// le widget ne les lit pas, il lit l'état que l'app publie dans le conteneur (`WidgetEtat`). Sans l'App Group
/// (interrupteur `VILLAGE_PLANNER_WIDGETS=NO`, compte refusé, signature absente), il n'y a pas de conteneur et rien ne change.
public enum Stockage {
    /// Le groupe est `group.<identifiant de l'app>` ; le widget (`<identifiant>.widget`) donne le même.
    public static func groupe(bundleID: String) -> String {
        "group." + (bundleID.hasSuffix(".widget") ? String(bundleID.dropLast(".widget".count)) : bundleID)
    }

    /// Le conteneur partagé de l'app ou du widget ; nil quand l'App Group n'est pas accordé.
    public static func conteneurPartage(bundleID: String?, fileManager: FileManager = .default) -> URL? {
        guard let bundleID else { return nil }
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupe(bundleID: bundleID))
    }

    /// Filet de sécurité pour les versions de test qui avaient déplacé les photos dans le conteneur : COPIE vers
    /// `support` ce qui y manque. Rien n'est jamais supprimé ni écrasé ; un fichier de même nom mais de contenu
    /// différent est copié sous `<nom>.conflit` (ni photo ni lecture pour l'app : `SnapshotStore.list` l'ignore, mais il est gardé ; un nom en `-conflit.json` serait lu comme une seconde photo de la même date) et signalé.
    public struct Recuperation: Equatable, Sendable {
        public var copies = 0
        public var conflits: [String] = []
        public var echecs: [String] = []
    }

    @discardableResult
    public static func recuperer(depuis partage: URL, vers support: URL, fileManager fm: FileManager = .default) -> Recuperation {
        var bilan = Recuperation()
        func copier(_ source: URL, _ cible: URL, nom: String) {
            guard let donnees = try? Data(contentsOf: source) else { bilan.echecs.append(nom); return }
            var destination = cible
            if let present = try? Data(contentsOf: cible) {
                if present == donnees { return }
                destination = cible.appendingPathExtension("conflit")
                if let deja = try? Data(contentsOf: destination), deja == donnees { return }   // déjà signalé
                if fm.fileExists(atPath: destination.path) { bilan.echecs.append(nom); return }
                bilan.conflits.append(nom)
            } else if fm.fileExists(atPath: cible.path) { bilan.echecs.append(nom); return }
            do {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try donnees.write(to: destination, options: .atomic)
            } catch { bilan.echecs.append(nom); return }
            guard (try? Data(contentsOf: destination)) == donnees else { bilan.echecs.append(nom); return }
            bilan.copies += 1
        }
        let photos = partage.appending(path: "Photos")
        for nom in ((try? fm.contentsOfDirectory(atPath: photos.path)) ?? []).sorted() where nom.hasSuffix(".json") {
            copier(photos.appending(path: nom), support.appending(path: "Photos").appending(path: nom), nom: "Photos/" + nom)
        }
        if fm.fileExists(atPath: partage.appending(path: "joueur.json").path) {
            copier(partage.appending(path: "joueur.json"), support.appending(path: "joueur.json"), nom: "joueur.json")
        }
        return bilan
    }
}
