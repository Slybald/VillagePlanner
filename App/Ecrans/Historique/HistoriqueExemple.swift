#if DEBUG
import Foundation

/// Captures seulement : n photos tirées de `exemple-village.json`, du plus ancien au plus récent, où quelques niveaux
/// montent d'une photo à l'autre. Écrites dans un dossier temporaire, jamais dans les dossiers de l'app.
enum HistoriqueExemple {
    /// `calme` : quelques éléments seulement montent d'une photo à l'autre et les minuteurs en cours restent les mêmes
    /// (pour un taux d'occupation vraisemblable ; la série par défaut gagne des centaines de niveaux en quelques jours).
    static func textes(_ n: Int, calme: Bool = false) -> [String] {
        guard let url = Bundle.main.url(forResource: "exemple-village", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let base = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let fin = base["timestamp"] as? Int ?? 0
        return (0..<n).map { i in
            let retard = n - 1 - i                          // 0 : la photo la plus récente
            var export = base
            export["timestamp"] = fin - retard * 2 * 86_400  // une photo tous les deux jours
            var fait = 0
            if calme {
                // Un minuteur sur deux n'existait pas encore à la photo d'avant (lancé depuis : début déduit) ;
                // les autres continuent d'une photo à l'autre ; un niveau seulement sur vingt-cinq éléments monte.
                var rang = 0
                for liste in ["buildings", "traps", "heroes", "units", "pets"] {
                    var elements = base[liste] as? [[String: Any]] ?? []
                    for k in elements.indices {
                        guard let niveau = elements[k]["lvl"] as? Int, ![1_000_001, 1_000_010].contains(elements[k]["data"] as? Int) else { continue }
                        if let t = elements[k]["timer"] as? Int, liste == "units" || liste == "pets" {
                            // Le labo et les familiers : un minuteur d'un jour une photo sur deux, rien entre les deux.
                            if retard > 0 { elements[k]["timer"] = retard % 2 == 0 ? 86_400 : nil }
                            else { elements[k]["timer"] = t }
                        } else if let t = elements[k]["timer"] as? Int {
                            rang += 1
                            if retard > 0, rang % 2 == 0 { elements[k]["timer"] = nil }
                            else { elements[k]["timer"] = t + retard * 2 * 86_400 }
                        } else if k % 25 == 0, retard > 0 { elements[k]["lvl"] = max(1, niveau - 1) }
                    }
                    export[liste] = elements
                }
                let json = (try? JSONSerialization.data(withJSONObject: export, options: [.sortedKeys])) ?? Data()
                return String(decoding: json, as: UTF8.self)
            }
            for liste in ["buildings", "traps", "heroes"] {
                var elements = base[liste] as? [[String: Any]] ?? []
                for k in elements.indices {
                    guard let niveau = elements[k]["lvl"] as? Int, ![1_000_001, 1_000_010].contains(elements[k]["data"] as? Int) else { continue }
                    if elements[k]["timer"] != nil {
                        // Les deux premières améliorations en cours finissent à la dernière photo.
                        if fait < 2 {
                            fait += 1
                            if retard == 0 { elements[k]["lvl"] = niveau + 1; elements[k]["timer"] = nil }
                            else if retard > 1 { elements[k]["lvl"] = max(1, niveau - (retard - 1)); elements[k]["timer"] = nil }
                        }
                    } else {
                        // Les éléments montent à trois rythmes différents.
                        elements[k]["lvl"] = max(1, niveau - [(retard + 1) / 2, retard / 3, (retard + 2) / 4][k % 3])
                    }
                }
                export[liste] = elements
            }
            let json = (try? JSONSerialization.data(withJSONObject: export, options: [.sortedKeys])) ?? Data()
            return String(decoding: json, as: UTF8.self)
        }
    }
}
#endif
