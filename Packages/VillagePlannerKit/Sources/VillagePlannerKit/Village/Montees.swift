public extension Village {
    /// Ce qui a monté de niveau depuis `ancien` : type → nouveau niveau → niveau d'où il vient.
    /// Un niveau est « monté » quand il a gagné des exemplaires ; il vient du plus haut niveau inférieur
    /// qui en a perdu (0 : construit depuis). Sert à l'animation de montée de niveau après un import.
    func montees(depuis ancien: Village) -> [Int: [Int: Int]] { Self.montees(de: ancien.elements, vers: elements) }

    static func montees(de ancien: [Element], vers nouveau: [Element]) -> [Int: [Int: Int]] {
        func compte(_ v: [Element]) -> [Int: [Int: Int]] {
            v.reduce(into: [:]) { $0[$1.itemID, default: [:]][$1.level, default: 0] += $1.count }
        }
        let avant = compte(ancien)
        var resultat: [Int: [Int: Int]] = [:]
        for (id, apres) in compte(nouveau) {
            let av = avant[id] ?? [:]
            let perdus = Set(av.keys.filter { (apres[$0] ?? 0) < av[$0]! })
            for (niveau, n) in apres where n > (av[niveau] ?? 0) {
                if let depuis = perdus.filter({ $0 < niveau }).max() {
                    resultat[id, default: [:]][niveau] = depuis
                } else if av.isEmpty {
                    resultat[id, default: [:]][niveau] = 0      // absent de l'ancienne photo : construit depuis
                }
            }
        }
        return resultat
    }
}
