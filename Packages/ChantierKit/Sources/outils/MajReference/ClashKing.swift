import ChantierKit
import Foundation

// Adaptateur de la source ClashKingInc/ClashKingAssets (`assets/static_data/*.json`) vers le format
// de l'app. Changer de source, c'est réécrire ce fichier (PLAN §4.3).

/// Les fichiers lus dans `assets/static_data/`.
let fichiersClashKing = ["buildings", "traps", "troops", "spells", "heroes", "pets", "equipment",
                         "helpers", "guardians"]

struct CKFichier: Decodable { let items: [CKItem] }

struct CKItem: Decodable {
    let _id: Int
    let name: String
    let type: String?
    let village: String?
    let upgradeResource: String?
    let productionBuilding: String?
    let productionBuildingLevel: Int?
    let superTroop: CKPresence?                 // un objet (troupe d'origine…) : seule sa présence compte
    let isSeasonal: Bool?
    let hero: String?
    let requiredTownhall: Int?
    let levels: [CKNiveau]?
    let seasonalDefenses: [CKItem]?
    let modules: [CKItem]?
}

struct CKNiveau: Decodable {
    let level: Int
    let buildCost: Int?
    let buildTime: Int?
    let upgradeCost: CKCout?
    let upgradeTime: Int?
    let requiredTownhall: Int?
    let requiredLabLevel: Int?
    let requiredHeroTavernLevel: Int?
    let requiredPetHouseLevel: Int?
    let requiredBlacksmithLevel: Int?
    let unlocks: [CKRef]?
    let mergeRequirement: [CKRef]?
    let altUpgradeResource: String?
    let boostTimeSeconds: Int?
    let boostMultiplier: Int?
}

/// Accepte n'importe quelle valeur JSON.
struct CKPresence: Decodable { init(from decoder: Decoder) throws {} }

struct CKRef: Decodable {
    let _id: Int
    let quantity: Int?
    let level: Int?
}

/// Un coût : un montant dans la ressource de l'élément, ou des minerais (équipements).
enum CKCout: Decodable {
    case montant(Int)
    case minerais([String: Int])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { self = .montant(n) } else {
            self = .minerais(try c.decode([String: Int].self))
        }
    }
}

enum ConversionClashKing {
    static let hdv = 1000001
    static let labo = 1000007
    static let hallDesHeros = 1000071
    static let maisonDesFamiliers = 1000068
    static let forgeron = 1000070

    enum Erreur: Error, CustomStringConvertible {
        case fichier(String, String)
        case pasDHDV
        case typeInconnu(Int, String)
        case batimentInconnu(String)
        case doublon(Int)
        var description: String {
            switch self {
            case .fichier(let f, let e): "\(f).json illisible : \(e)"
            case .pasDHDV: "l'hôtel de ville (1000001) manque dans buildings.json"
            case .typeInconnu(let id, let t):
                "type de bâtiment inconnu « \(t) » pour \(id) : ajouter sa catégorie dans ClashKing.swift"
            case .batimentInconnu(let n): "bâtiment de production inconnu : \(n)"
            case .doublon(let id): "identifiant en double : \(id)"
            }
        }
    }

    /// Lit les fichiers d'un dossier du cache.
    static func lire(dossier: URL) throws -> [String: [CKItem]] {
        let decodeur = JSONDecoder()
        decodeur.keyDecodingStrategy = .convertFromSnakeCase
        var sortie: [String: [CKItem]] = [:]
        for f in fichiersClashKing {
            do {
                let data = try Data(contentsOf: dossier.appendingPathComponent("\(f).json"))
                sortie[f] = try decodeur.decode(CKFichier.self, from: data).items
            } catch { throw Erreur.fichier(f, "\(error)") }
        }
        return sortie
    }

    /// Un type avant le calcul des nombres et des maximums.
    private struct Brouillon {
        let id: Int
        let nom: String
        let section: String
        let categorie: ChantierKit.Category?
        let exclusion: Exclusion?
        let poste: WorkerKind
        let niveaux: [ReferenceLevel]
        let place: Bool                    // bâtiment ou piège : un nombre par HDV
        let fusion: [Requirement]
    }

    static func convertir(_ f: [String: [CKItem]], source: ReferenceSource) throws -> ReferenceData {
        let accueil = { (i: CKItem) in i.village == nil || i.village == "home" }
        let batiments = (f["buildings"] ?? []).filter(accueil)
        guard let th = batiments.first(where: { $0._id == hdv }) else { throw Erreur.pasDHDV }
        let maxHDV = (th.levels ?? []).map(\.level).max() ?? 0
        let idParNom = Dictionary(batiments.map { ($0.name, $0._id) }, uniquingKeysWith: { a, _ in a })
        let herosParNom = Dictionary((f["heroes"] ?? []).filter(accueil).map { ($0.name, $0._id) },
                                     uniquingKeysWith: { a, _ in a })

        // Nombres par HDV : la source donne des incréments dans les niveaux de l'HDV, on cumule.
        var nombres: [Int: [Int]] = [hdv: [0] + Array(repeating: 1, count: maxHDV)]
        for niveau in th.levels ?? [] where niveau.level <= maxHDV {
            for u in niveau.unlocks ?? [] {
                var t = nombres[u._id] ?? Array(repeating: 0, count: maxHDV + 1)
                for n in niveau.level...maxHDV { t[n] += u.quantity ?? 0 }
                nombres[u._id] = t
            }
            // Fusion dans l'HDV lui-même (l'Aigle à l'HDV 17) : le bâtiment consommé disparaît.
            for m in niveau.mergeRequirement ?? [] {
                guard var t = nombres[m._id] else { continue }
                for n in niveau.level...maxHDV { t[n] = max(0, t[n] - 1) }
                nombres[m._id] = t
            }
        }

        func exigences(_ paires: [(Int, Int?)]) -> [Requirement] {
            var parID: [Int: Int] = [:]
            for (id, niveau) in paires { if let niveau, niveau > 0 { parID[id] = max(parID[id] ?? 0, niveau) } }
            return parID.sorted { $0.key < $1.key }.map { Requirement(itemID: $0.key, level: $0.value) }
        }
        func production(_ i: CKItem) throws -> (Int, Int?) {
            guard let nom = i.productionBuilding, let niveau = i.productionBuildingLevel, niveau > 0 else {
                return (hdv, nil)
            }
            guard let id = idParNom[nom] else { throw Erreur.batimentInconnu(nom) }
            return (id, niveau)
        }
        func couts(_ c: CKCout?, _ ressource: String?) -> [ResourceAmount] {
            switch c {
            case .minerais(let m):
                return [("shiny_ore", Resource.shinyOre), ("glowy_ore", .glowyOre), ("starry_ore", .starryOre)]
                    .compactMap { cle, r in m[cle].flatMap { $0 > 0 ? ResourceAmount(resource: r, amount: $0) : nil } }
            case .montant(let n):
                guard n > 0, let r = ressourceApp(ressource) else { return [] }
                return [ResourceAmount(resource: r, amount: n)]
            case nil: return []
            }
        }
        /// Un type sans niveau dans la source (cabanes, station, Prospecteur) a un seul niveau, sans coût.
        func niveaux(_ i: CKItem, _ faire: (CKNiveau, Bool) throws -> ReferenceLevel) rethrows -> [ReferenceLevel] {
            let source = (i.levels ?? []).sorted { $0.level < $1.level }
            if source.isEmpty {
                return [ReferenceLevel(level: 1, costs: [], duration: 0, requires: exigences([(hdv, i.requiredTownhall)]))]
            }
            return try source.enumerated().map { try faire($1, $0 == 0) }
        }

        var brouillons: [Brouillon] = []

        // Bâtiments
        for b in batiments {
            let exception = Exceptions.horsAvancement[b._id]
            let categorie: ChantierKit.Category?
            switch b.type {
            case "Defense": categorie = .defenses
            case "Wall": categorie = .walls
            case "Army", "Resource", "Town Hall", "Worker", "Worker2": categorie = .economy
            case "Helper": categorie = nil
            default: throw Erreur.typeInconnu(b._id, b.type ?? "?")
            }
            let exclusion = exception ?? (categorie == nil ? .helper : nil)
            let lv = niveaux(b) { n, _ in
                ReferenceLevel(level: n.level,
                               costs: couts(.montant(n.buildCost ?? 0), b.upgradeResource),
                               duration: n.buildTime ?? 0,
                               requires: b._id == hdv ? [] : exigences([(hdv, n.requiredTownhall)]),
                               alternativeResource: ressourceApp(n.altUpgradeResource))
            }
            let fusion = ((b.levels ?? []).min { $0.level < $1.level }?.mergeRequirement ?? [])
                .map { Requirement(itemID: $0._id, level: $0.level ?? 0) }
            brouillons.append(Brouillon(id: b._id, nom: b.name, section: "buildings",
                                        categorie: exclusion == nil ? categorie : nil, exclusion: exclusion,
                                        poste: .builder, niveaux: lv, place: true,
                                        fusion: b._id == hdv ? [] : fusion))
            // Défenses fabriquées et leurs modules, imbriqués sous la station (hors avancement, V8).
            for d in b.seasonalDefenses ?? [] {
                brouillons.append(Brouillon(id: d._id, nom: d.name, section: "buildings", categorie: nil,
                                            exclusion: .craftedDefense, poste: .builder,
                                            niveaux: niveaux(d) { n, _ in ReferenceLevel(level: n.level, costs: [], duration: 0, requires: []) }, place: false, fusion: []))
                for m in d.modules ?? [] {
                    brouillons.append(Brouillon(
                        id: m._id, nom: m.name, section: "buildings", categorie: nil, exclusion: .craftedDefense,
                        poste: .builder,
                        niveaux: niveaux(m) { n, _ in
                            ReferenceLevel(level: n.level, costs: couts(.montant(n.buildCost ?? 0), m.upgradeResource),
                                           duration: n.buildTime ?? 0, requires: exigences([(hdv, n.requiredTownhall)]))
                        }, place: false, fusion: []))
                }
            }
        }

        // Pièges
        for p in (f["traps"] ?? []).filter(accueil) {
            brouillons.append(Brouillon(
                id: p._id, nom: p.name, section: "traps", categorie: .traps, exclusion: nil, poste: .builder,
                niveaux: niveaux(p) { n, _ in
                    ReferenceLevel(level: n.level, costs: couts(.montant(n.buildCost ?? 0), p.upgradeResource),
                                   duration: n.buildTime ?? 0, requires: exigences([(hdv, n.requiredTownhall)]))
                }, place: true, fusion: []))
        }

        // Troupes, engins de siège et sorts : labo
        for (fichier, defaut) in [("troops", "units"), ("spells", "spells")] {
            for u in (f[fichier] ?? []).filter(accueil) {
                let exclusion: Exclusion? = u.superTroop != nil ? .superTroop : u.isSeasonal == true ? .seasonal : nil
                let prod = try production(u)
                brouillons.append(Brouillon(
                    id: u._id, nom: u.name, section: u.productionBuilding == "Workshop" ? "siege_machines" : defaut,
                    categorie: exclusion == nil ? .laboratory : nil, exclusion: exclusion, poste: .laboratory,
                    niveaux: niveaux(u) { n, premier in
                        ReferenceLevel(level: n.level, costs: couts(n.upgradeCost, u.upgradeResource),
                                       duration: n.upgradeTime ?? 0,
                                       requires: exigences([(hdv, n.requiredTownhall), (labo, n.requiredLabLevel)]
                                                           + (premier ? [prod] : [])))
                    }, place: false, fusion: []))
            }
        }

        // Héros : Hall des héros
        for h in (f["heroes"] ?? []).filter(accueil) {
            let prod = try production(h)
            brouillons.append(Brouillon(
                id: h._id, nom: h.name, section: "heroes", categorie: .heroes, exclusion: nil, poste: .builder,
                niveaux: niveaux(h) { n, premier in
                    ReferenceLevel(level: n.level, costs: couts(n.upgradeCost, h.upgradeResource),
                                   duration: n.upgradeTime ?? 0,
                                   requires: exigences([(hdv, n.requiredTownhall), (hallDesHeros, n.requiredHeroTavernLevel)]
                                                       + (premier ? [prod] : [])))
                }, place: false, fusion: []))
        }

        // Familiers : Maison des familiers
        for p in f["pets"] ?? [] {
            let prod = try production(p)
            brouillons.append(Brouillon(
                id: p._id, nom: p.name, section: "pets", categorie: .pets, exclusion: nil, poste: .petHouse,
                niveaux: niveaux(p) { n, premier in
                    ReferenceLevel(level: n.level, costs: couts(n.upgradeCost, p.upgradeResource),
                                   duration: n.upgradeTime ?? 0,
                                   requires: exigences([(hdv, n.requiredTownhall), (maisonDesFamiliers, n.requiredPetHouseLevel)]
                                                       + (premier ? [prod] : [])))
                }, place: false, fusion: []))
        }

        // Équipements : Forgeron, et le héros qui les porte
        for e in f["equipment"] ?? [] {
            let prod = try production(e)
            let heros = e.hero.flatMap { herosParNom[$0] }
            brouillons.append(Brouillon(
                id: e._id, nom: e.name, section: "equipment", categorie: .equipment, exclusion: nil, poste: .blacksmith,
                niveaux: niveaux(e) { n, premier in
                    ReferenceLevel(level: n.level, costs: couts(n.upgradeCost, nil), duration: 0,
                                   requires: exigences([(hdv, n.requiredTownhall), (forgeron, n.requiredBlacksmithLevel)]
                                                       + (premier ? [prod] + (heros.map { [($0, 1)] } ?? []) : [])))
                }, place: false, fusion: []))
        }

        // Assistants (payés en gemmes : coût non repris) et gardiens : hors avancement
        for a in f["helpers"] ?? [] {
            brouillons.append(Brouillon(
                id: a._id, nom: a.name, section: "helpers", categorie: nil, exclusion: .helper, poste: .builder,
                niveaux: niveaux(a) { n, _ in
                    ReferenceLevel(level: n.level, costs: [], duration: 0, requires: exigences([(hdv, n.requiredTownhall)]),
                                   helperMultiplier: n.boostMultiplier, helperSeconds: n.boostTimeSeconds)
                }, place: false, fusion: []))
        }
        for g in f["guardians"] ?? [] {
            brouillons.append(Brouillon(
                id: g._id, nom: g.name, section: "guardians", categorie: nil, exclusion: .guardian, poste: .builder,
                niveaux: niveaux(g) { n, _ in
                    ReferenceLevel(level: n.level, costs: couts(n.upgradeCost, g.upgradeResource),
                                   duration: n.upgradeTime ?? 0, requires: exigences([(hdv, n.requiredTownhall)]))
                }, place: false, fusion: []))
        }

        brouillons.removeAll { Exceptions.retires[$0.id] != nil }
        var vus = Set<Int>()
        for b in brouillons where !vus.insert(b.id).inserted { throw Erreur.doublon(b.id) }

        // Maximum à l'HDV n : plus haut niveau dont tous les niveaux jusqu'à lui ont leurs prérequis
        // (HDV, labo, Hall des héros, Maison des familiers, Forgeron, bâtiment de production, héros).
        let parID = Dictionary(uniqueKeysWithValues: brouillons.map { ($0.id, $0) })
        func nombre(_ b: Brouillon, _ n: Int) -> Int { nombres[b.id].map { $0[n] } ?? 0 }
        func maximum(_ id: Int, _ n: Int) -> Int {
            if id == hdv { return n }
            guard let b = parID[id] else { return 0 }
            if b.place && nombre(b, n) == 0 { return 0 }
            var max = 0
            for niveau in b.niveaux {
                let ok = niveau.requires.allSatisfy { r in
                    r.itemID == hdv ? r.level <= n : maximum(r.itemID, n) >= r.level
                }
                guard ok else { break }
                max = niveau.level
            }
            return max
        }

        let items = brouillons.sorted { $0.id < $1.id }.map { b in
            let maxima = (0...maxHDV).map { $0 == 0 ? 0 : maximum(b.id, $0) }
            let comptes = b.place ? (0...maxHDV).map { nombre(b, $0) } : maxima.map { $0 > 0 ? 1 : 0 }
            return ReferenceItem(id: b.id, names: ["en": b.nom], section: b.section, category: b.categorie,
                                 exclusion: b.exclusion, worker: b.poste, levels: b.niveaux,
                                 countByTownHall: comptes, maxLevelByTownHall: maxima, mergedFrom: b.fusion)
        }
        return ReferenceData(items: items, source: source, maxTownHall: maxHDV)
    }

    static func ressourceApp(_ nom: String?) -> Resource? {
        switch nom {
        case "Gold": .gold
        case "Elixir": .elixir
        case "Dark Elixir": .darkElixir
        default: nil                       // gemmes, ressources de la base des ouvriers
        }
    }
}
