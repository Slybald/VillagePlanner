import Foundation

/// Où vivent les photos et leur index (T25). Un seul choix : le conteneur partagé (App Group) quand il existe,
/// sinon Application Support, comme avant. Sans l'App Group (interrupteur `CHANTIER_WIDGETS=NO`, compte refusé,
/// signature absente), rien ne change et rien ne produit d'erreur.
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

    /// La racine des photos : le conteneur partagé une fois tout déplacé, sinon `support`.
    /// Une migration qui n'a pas pu tout copier laisse l'ancien dossier intact et garde `support` jusqu'au prochain essai.
    public static func racine(support: URL, partage: URL?, fileManager: FileManager = .default) -> URL {
        guard let partage else { return support }
        return migrer(de: support, vers: partage, fileManager: fileManager).estComplete ? partage : support
    }

    /// Ce qui s'est passé : jamais d'effacement sans copie vérifiée.
    public struct Migration: Equatable, Sendable {
        /// Fichiers copiés et vérifiés (leur original est alors supprimé).
        public var copies = 0
        /// Fichiers déjà présents à l'arrivée avec le même contenu (leur original est alors supprimé).
        public var dejaLa = 0
        /// Fichiers qui existent des deux côtés avec un contenu différent : l'original reste où il est.
        public var conflits: [String] = []
        /// Fichiers qui n'ont pas pu être copiés ou vérifiés : l'original reste où il est.
        public var echecs: [String] = []
        public var estComplete: Bool { echecs.isEmpty }
    }

    /// Ce que l'app a déjà écrit à la racine : le dossier des photos, l'index, les lectures du joueur.
    static func aDeplacer(dans racine: URL, fileManager fm: FileManager) -> [String] {
        var noms = ["Photos", "index.json", "joueur.json"]
        let autres = (try? fm.contentsOfDirectory(atPath: racine.path)) ?? []
        noms += autres.filter { $0.hasPrefix("joueur-abime-") }.sorted()
        return noms
    }

    /// Déplace les photos, l'index et les lectures du joueur de `ancien` vers `nouveau` : copie, vérification de chaque
    /// fichier (contenu identique, octet pour octet), puis suppression de l'original de ce fichier seulement.
    /// Se rejoue sans risque : ce qui est déjà passé est reconnu, ce qui reste est repris.
    @discardableResult
    public static func migrer(de ancien: URL, vers nouveau: URL, fileManager fm: FileManager = .default) -> Migration {
        var bilan = Migration()
        guard ancien.standardizedFileURL != nouveau.standardizedFileURL else { return bilan }

        func deplacer(_ source: URL, vers cible: URL, nom: String) {
            guard let donnees = try? Data(contentsOf: source) else { bilan.echecs.append(nom); return }
            if fm.fileExists(atPath: cible.path) {
                guard let present = try? Data(contentsOf: cible) else { bilan.echecs.append(nom); return }
                if present != donnees { bilan.conflits.append(nom); return }
                bilan.dejaLa += 1
            } else {
                do {
                    try fm.createDirectory(at: cible.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try donnees.write(to: cible, options: .atomic)
                } catch { bilan.echecs.append(nom); return }
                guard (try? Data(contentsOf: cible)) == donnees else { bilan.echecs.append(nom); return }
                bilan.copies += 1
            }
            if (try? fm.removeItem(at: source)) == nil { bilan.echecs.append(nom) }
        }

        for nom in aDeplacer(dans: ancien, fileManager: fm) {
            let source = ancien.appending(path: nom)
            var estDossier: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &estDossier) else { continue }
            if estDossier.boolValue {
                for fichier in ((try? fm.contentsOfDirectory(atPath: source.path)) ?? []).sorted() {
                    deplacer(source.appending(path: fichier), vers: nouveau.appending(path: nom).appending(path: fichier), nom: nom + "/" + fichier)
                }
                // Le dossier d'origine disparaît quand il est vide ; s'il reste des conflits, il reste avec eux.
                if ((try? fm.contentsOfDirectory(atPath: source.path)) ?? ["x"]).isEmpty { try? fm.removeItem(at: source) }
            } else {
                deplacer(source, vers: nouveau.appending(path: nom), nom: nom)
            }
        }
        return bilan
    }
}
