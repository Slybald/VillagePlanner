import ChantierKit
import Foundation

// `swift run --package-path Packages/ChantierKit outils maj-reference [--cache]`
// 1. télécharge les sources (ou relit le cache avec --cache) ;
// 2. convertit ClashKing en reference.json ;
// 3. écrit le rapport : changements depuis la version précédente, écarts avec chiefpansancolt.

enum MajReference {
    /// Racine du paquet ChantierKit, retrouvée depuis ce fichier source.
    static let paquet = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let cache = paquet.appendingPathComponent(".cache/maj-reference")
    static let sortie = paquet.appendingPathComponent("Sources/ChantierKit/Reference/Ressources/reference.json")
    static let rapport = cache.appendingPathComponent("rapport.md")
    static let dernier = cache.appendingPathComponent("dernier.json")

    static func lancer(horsLigne: Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)

        let versions: [String: Instantane]
        if horsLigne {
            guard let data = try? Data(contentsOf: dernier),
                  let v = try? JSONDecoder().decode([String: Instantane].self, from: data) else {
                throw Telechargement.Erreur.pasDeCache(dernier.path)
            }
            versions = v
        } else {
            var v: [String: Instantane] = [:]
            for s in [clashKing, chiefpansancolt] {
                let i = try Telechargement.dernierCommit(s)
                let dossier = dossierCache(s, i)
                var chemins = try Telechargement.listerJSON(s, commit: i.commit)
                if s.depot == clashKing.depot {
                    chemins = chemins.filter { fichiersClashKing.contains(URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent) }
                }
                try Telechargement.telecharger(s, commit: i.commit, chemins: chemins, vers: dossier)
                v[s.depot] = i
            }
            let e = JSONEncoder()
            e.outputFormatting = [.sortedKeys, .prettyPrinted]
            try e.encode(v).write(to: dernier)
            versions = v
        }
        guard let ck = versions[clashKing.depot], let chief = versions[chiefpansancolt.depot] else {
            throw Telechargement.Erreur.pasDeCache(dernier.path)
        }

        let source = ReferenceSource(name: clashKing.depot, license: clashKing.licence, commit: ck.commit, date: ck.date)
        let brute = try ConversionClashKing.convertir(
            try ConversionClashKing.lire(dossier: dossierCache(clashKing, ck)), source: source)
        let (reference, sansNom) = NomsFr.fusionner(brute, noms: try NomsFr.lire())
        let seconde = try SecondeSource.lire(dossier: dossierCache(chiefpansancolt, chief))
        let avant = try? ReferenceData.load(from: sortie)

        let octets = try Rapport.encoder(reference)
        try fm.createDirectory(at: sortie.deletingLastPathComponent(), withIntermediateDirectories: true)
        try octets.write(to: sortie)

        let texte = """
            # Rapport de maj-reference

            - Source : \(clashKing.depot) (\(clashKing.licence)), commit \(ck.commit), du \(ck.date)
            - Contrôle : \(chiefpansancolt.depot) (\(chiefpansancolt.licence)), commit \(chief.commit), du \(chief.date)
            - reference.json : \(reference.items.count) types, HDV max \(reference.maxTownHall), \(octets.count) octets

            ## Changements depuis la version précédente

            \(Rapport.changements(avant: avant, apres: reference))
            ## Noms français manquants (noms-fr.json)

            \(sansNom.isEmpty ? "Aucun." : sansNom.map(String.init).joined(separator: ", "))

            ## Écarts avec la source de contrôle

            \(Rapport.ecarts(reference, seconde))
            """
        try Data(texte.utf8).write(to: rapport)
        print(texte)
        print("écrit : \(sortie.path)\nrapport : \(rapport.path)")
    }

    static func dossierCache(_ s: SourceDistante, _ i: Instantane) -> URL {
        cache.appendingPathComponent(s.depot.replacingOccurrences(of: "/", with: "_"))
            .appendingPathComponent(i.commit)
    }
}
