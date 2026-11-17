import Foundation
import Testing

/// Aucun fichier du dépôt (suivi, ou prêt à l'être) ne porte un tag autre que `#2PP`.
@Suite struct GardeFouAnonymatTests {
    static let racine = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Les champs tag dont la valeur n'est pas `#2PP`, par fichier.
    static func tagsInterdits(dans racine: URL) throws -> [String] {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.currentDirectoryURL = racine
        git.arguments = ["ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        let sortie = Pipe()
        git.standardOutput = sortie
        try git.run()
        let données = sortie.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        guard git.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }

        let motif = try NSRegularExpression(pattern: ##""tag"\s*:\s*"(#[^"]*)""##)
        var trouvés: [String] = []
        var lus = 0
        for chemin in String(decoding: données, as: UTF8.self).split(separator: "\0") {
            guard let octets = try? Data(contentsOf: racine.appendingPathComponent(String(chemin))),
                  let texte = String(data: octets, encoding: .isoLatin1) else { continue }
            lus += 1
            let plein = NSRange(texte.startIndex..., in: texte)
            for m in motif.matches(in: texte, range: plein) {
                let valeur = String(texte[Range(m.range(at: 1), in: texte)!])
                if valeur != "#2PP" { trouvés.append("\(chemin) : un tag autre que #2PP") }
            }
        }
        #expect(lus > 0, "aucun fichier lu : le garde-fou ne vérifie rien")
        return trouvés
    }

    @Test func aucunTagAutreQueFactice() throws {
        let trouvés = try Self.tagsInterdits(dans: Self.racine)
        #expect(trouvés.isEmpty, "\(trouvés)")
    }

    @Test func leGardeFouVoitUnTagInjecté() throws {
        // Dossier temporaire : dépôt git jetable avec un faux tag.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("anonymat-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let init_ = Process()
        init_.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        init_.arguments = ["init", "-q", tmp.path]
        try init_.run(); init_.waitUntilExit()
        try Data("{\"tag\":\"#9ZZZ9\",\"timestamp\":1}".utf8).write(to: tmp.appendingPathComponent("a.json"))
        try Data("{\"tag\":\"#2PP\",\"timestamp\":1}".utf8).write(to: tmp.appendingPathComponent("b.json"))
        let trouvés = try Self.tagsInterdits(dans: tmp)
        #expect(trouvés.count == 1 && trouvés[0].hasPrefix("a.json"))
    }
}
