import Foundation

// Le résumé envoyé au modèle (PLAN §6.2) : tout ce qu'il a le droit de dire, sous la forme où il peut le dire.
// Chaque valeur y est déjà écrite (« demain 14 h », « 18 M d'or », « Arc-X 11 »). Il ne contient ni le tag, ni l'export
// brut : seulement des noms du jeu, des niveaux, des dates et des montants calculés par le moteur.
//
// Règle d'écriture : tout nombre du résumé devient un nombre que la réponse a le droit de citer (G1). Les libellés
// ne contiennent donc aucun nombre (ni « dix prochaines », ni « sur sept jours »), et la liste n'est pas numérotée.

/// Un niveau gagné entre la photo précédente et celle-ci. `depuis` vaut 0 pour un élément construit depuis.
public struct ChangementPhoto: Sendable, Equatable {
    public let id: Int
    public let depuis: Int
    public let vers: Int

    public init(id: Int, depuis: Int, vers: Int) {
        self.id = id
        self.depuis = depuis
        self.vers = vers
    }
}

extension Village {
    /// Les niveaux gagnés depuis `ancien`, dans un ordre fixe (identifiant, puis niveau).
    public func changements(depuis ancien: Village) -> [ChangementPhoto] {
        montees(depuis: ancien).flatMap { id, niveaux in niveaux.map { ChangementPhoto(id: id, depuis: $1, vers: $0) } }
            .sorted { ($0.id, $0.vers) < ($1.id, $1.vers) }
    }
}

/// Une amélioration que le modèle peut choisir : tout ce que la consigne affichée en dit vient du plan, pas du modèle.
public struct PasCandidat: Sendable, Equatable {
    public let id: Int
    public let nom: String
    public let niveau: Int
    public let copies: Int
    public let debut: Date
    /// Le poste est libre à la date du calcul : pas de date à annoncer.
    public let maintenant: Bool
    /// Coût de tous les exemplaires lancés ensemble.
    public let couts: [ResourceAmount]
    public let poste: WorkerKind
}

public struct ResumeConseil: Sendable, Equatable {
    /// Version du format du résumé et des instructions : elle entre dans la clé du conseil gardé.
    public static let version = 2
    /// Le modèle choisit parmi les trois premiers lancements du plan.
    public static let choixMax = 3
    /// Au plus ce nombre d'améliorations, groupées par exemplaires lancés ensemble.
    static let ameliorationsMax = 10
    static let changementsMax = 10

    /// Le texte envoyé tel quel au modèle.
    public let texte: String
    /// Les trois premiers lancements du plan, dans l'ordre du plan : `premier` et `ensuite` en sont l'un ou l'autre.
    public let candidats: [PasCandidat]
    let maintenant: Date
    let fuseau: TimeZone

    public init(texte: String, candidats: [PasCandidat], maintenant: Date, fuseau: TimeZone) {
        self.texte = texte
        self.candidats = candidats
        self.maintenant = maintenant
        self.fuseau = fuseau
    }

    /// Les identifiants permis, sans doublon, dans l'ordre du plan.
    public var identifiantsPermis: [Int] {
        var vus = Set<Int>()
        return candidats.map(\.id).filter { vus.insert($0).inserted }
    }

    public func candidat(_ id: Int) -> PasCandidat? { candidats.first { $0.id == id } }

    /// Le schéma imposé à l'API : `premier` et `ensuite` sont des énumérations des identifiants permis.
    /// (Les longueurs ne se contraignent pas dans un schéma : la raison est bornée par les garde-fous.)
    public var schema: String {
        let ids = identifiantsPermis.map(String.init).joined(separator: ",")
        return #"{"type":"object","properties":{"premier":{"type":"integer","enum":["# + ids + #"]},"raison":{"type":"string"},"ensuite":{"anyOf":[{"type":"integer","enum":["# + ids + #"]},{"type":"null"}]}},"required":["premier","raison","ensuite"],"additionalProperties":false}"#
    }

    /// `plan` et `besoins` viennent du moteur ; `consigneMoteur` est sa consigne (le modèle la reformule).
    /// `changements` : `Village.changements(depuis:)` de la photo précédente, nil quand il n'y en a pas.
    public static func make(village: Village, rapport: ProgressReport, plan: Plan, besoins: [ResourceNeed], profil: Profile,
                            reference: ReferenceData, photo: Date, consigneMoteur: String, changements: [ChangementPhoto]?,
                            timeZone: TimeZone) -> ResumeConseil {
        let now = plan.now
        func nom(_ id: Int) -> String { reference.name(of: id) ?? "#\(id)" }
        var lignes: [String] = []

        func quand(_ d: Date) -> String { "le\u{00A0}\(Lisible.jour(d, now: now, timeZone: timeZone)) à\u{00A0}\(Lisible.heure(d, timeZone: timeZone))" }
        lignes.append("Hôtel de ville \(village.townHall). Photo : \(quand(photo)). Maintenant : \(quand(now)).")
        lignes.append("Consigne du moteur, à reformuler : \(consigneMoteur)")
        if let cap = plan.cap {
            lignes.append("Cap : hôtel de ville \(village.townHall) terminé \(Lisible.moment(cap, now: now, timeZone: timeZone)), "
                + "dans \(Lisible.duree(max(0, Int(cap.timeIntervalSince(now).rounded(.up))))), hors murs et équipements.")
        } else {
            lignes.append("Cap : plus rien à améliorer à cet hôtel de ville, hors murs et équipements.")
        }
        lignes.append(avancement(rapport))
        lignes.append(profilEnClair(profil, village: village, plan: plan, reference: reference))

        let groupes = groupesDeLancement(plan)
        // Photo périmée : le plan ne vaut plus (la consigne du moteur le dit), le modèle n'a rien à choisir.
        let candidats = now.timeIntervalSince(photo) > photoPerimee ? [] : premiersChoix(plan: plan, reference: reference)
        if groupes.isEmpty {
            lignes.append("Prochaines améliorations : aucune à lancer.")
        } else {
            lignes.append("Prochaines améliorations, dans l'ordre du moteur :")
            for (s, copies) in groupes.prefix(ameliorationsMax) {
                let niveau = s.step.level == 1 ? "construction" : "niveau \(s.step.level - 1) → \(s.step.level)"
                let couts = s.costs.filter { $0.amount > 0 }.map { Lisible.cout($0.amount, $0.resource) }
                var ligne = "- (id \(s.step.itemID)) \(nom(s.step.itemID)) \(s.step.level) (\(niveau))" + (copies > 1 ? " (×\(copies))" : "")
                ligne += " : lancement \(Lisible.moment(s.start, now: now, timeZone: timeZone)), "
                ligne += couts.isEmpty ? "aucun coût" : "coût \(couts.joined(separator: " et "))" + (copies > 1 ? " par exemplaire" : "")
                ligne += ", durée \(Lisible.duree(max(0, Int(s.end.timeIntervalSince(s.start).rounded())))), \(poste(s.worker))."
                ligne += " Raison : \(raison(s.reason, pinned: profil.pinned.contains(s.step.itemID)))."
                lignes.append(ligne)
            }
        }

        if !candidats.isEmpty {
            lignes.append("Choix possibles pour « premier » et « ensuite » : "
                + candidats.map { "(id \($0.id)) \($0.nom) \($0.niveau)" }.joined(separator: ", ") + ".")
        }

        if !besoins.isEmpty {
            lignes.append("Ressources à réunir :")
            for b in besoins {
                var parts = b.dues.map { "\(Lisible.cout($0.amount, b.resource)) \(Lisible.moment($0.date, now: now, timeZone: timeZone))" }
                if b.perDay > 0 { parts.append("rythme \(Lisible.cout(b.perDay, b.resource)) par jour") }
                if b.wallsRemaining > 0 {
                    parts.append("murs : \(Lisible.cout(b.wallsRemaining, b.resource)) restants"
                        + (b.wallsPerDay.map { ", \(Lisible.cout($0, b.resource)) par jour jusqu'au cap" } ?? ""))
                }
                lignes.append("- " + parts.joined(separator: " ; ") + ".")
            }
        }

        if let changements {
            let liste = changements.prefix(changementsMax)
            if liste.isEmpty {
                lignes.append("Changements depuis la photo précédente : aucun.")
            } else {
                lignes.append("Changements depuis la photo précédente :")
                for c in liste {
                    lignes.append("- (id \(c.id)) \(nom(c.id)) " + (c.depuis == 0 ? "construit, niveau \(c.vers)" : "niveau \(c.depuis) → \(c.vers)") + ".")
                }
            }
        } else {
            lignes.append("Changements depuis la photo précédente : pas de photo précédente.")
        }
        return ResumeConseil(texte: lignes.joined(separator: "\n"), candidats: candidats, maintenant: now, fuseau: timeZone)
    }

    // MARK: Morceaux

    private static func poste(_ w: WorkerKind) -> String {
        switch w {
        case .builder: "ouvrier"
        case .laboratory: "labo"
        case .petHouse: "Maison des familiers"
        case .blacksmith: "forge"
        }
    }

    private static func raison(_ r: PrioritizedStep.Reason?, pinned: Bool) -> String {
        let base: String = switch r {
        case .unlocks: "elle débloque d'autres améliorations"
        case .armyAndCastle: "elle fait partie de la base de l'armée"
        case .build: "bâtiment à construire"
        case .hero: "c'est un héros"
        case .keyDefense: "défense clé de la liste de conseils"
        case .otherBuilding: "bâtiment du village"
        case .trap: "c'est un piège"
        case .advice: "bien placée dans la liste de conseils de son poste"
        case .cheapest: "peu coûteuse parmi celles de son poste"
        case nil: "déjà en cours"
        }
        return pinned ? base + ", épinglée par le joueur" : base
    }

    private static let categories: [(Category, String)] = [(.defenses, "Défenses"), (.heroes, "Héros"), (.laboratory, "Labo"), (.walls, "Murs"),
                                                          (.traps, "Pièges"), (.economy, "Économie"), (.pets, "Familiers"), (.equipment, "Équipements")]

    private static func avancement(_ r: ProgressReport) -> String {
        func pc(_ f: Double) -> String { "\(Int((f * 100).rounded()))\u{00A0}%" }
        var parts: [String] = []
        if let total = r.total { parts.append("total \(pc(total))") }
        for (c, nom) in categories {
            guard let p = r.categories[c] else { continue }
            parts.append(p.hasWork ? "\(nom) \(pc(p.fraction))" : "\(nom) rien à faire")
        }
        return "Avancement : " + parts.joined(separator: ", ") + "."
    }

    private static func profilEnClair(_ p: Profile, village: Village, plan: Plan, reference: ReferenceData) -> String {
        var parts = ["Profil : orientation " + (p.orientation == .attack ? "attaque" : p.orientation == .defense ? "défense" : "équilibrée")]
        parts.append(p.heroLimit.map { "limite de héros en amélioration : \($0)" } ?? "pas de limite de héros")
        let epingles = p.pinned.sorted().compactMap { reference.name(of: $0) }
        parts.append(epingles.isEmpty ? "aucune épingle" : "épinglés : " + epingles.joined(separator: ", "))
        parts.append(p.quietHours.map { "heures sans jeu de \($0.start)\u{00A0}h à \($0.end)\u{00A0}h" } ?? "pas d'heures sans jeu")
        if let n = village.workers[.builder] { parts.append("ouvriers : \(n)") }
        var texte = parts.joined(separator: ", ") + "."
        if let r = Lisible.reductions(p, at: plan.now) { texte += " " + r }
        return texte
    }
}

// MARK: - Les choix du modèle et la consigne composée par l'app

/// Les lancements du plan, groupés par exemplaires lancés ensemble (même élément, même niveau, même instant), dans l'ordre du plan.
func groupesDeLancement(_ plan: Plan) -> [(step: ScheduledStep, copies: Int)] {
    var groupes: [(step: ScheduledStep, copies: Int)] = []
    for s in plan.steps where !s.fromSnapshot {
        if let i = groupes.firstIndex(where: { $0.step.step.itemID == s.step.itemID && $0.step.step.level == s.step.level && $0.step.start == s.start }) {
            groupes[i].copies += 1
        } else { groupes.append((s, 1)) }
    }
    return groupes
}

func premiersChoix(plan: Plan, reference: ReferenceData) -> [PasCandidat] {
    groupesDeLancement(plan).prefix(ResumeConseil.choixMax).map { s, copies in
        var totaux: [Resource: Int] = [:]
        for c in s.costs { totaux[c.resource, default: 0] += c.amount * copies }
        return PasCandidat(id: s.step.itemID, nom: reference.name(of: s.step.itemID) ?? "#\(s.step.itemID)", niveau: s.step.level,
                           copies: copies, debut: s.start, maintenant: s.start <= plan.now,
                           couts: Resource.allCases.compactMap { r in totaux[r].flatMap { $0 > 0 ? ResourceAmount(resource: r, amount: $0) : nil } },
                           poste: s.worker)
    }
}

extension ResumeConseil {
    /// L'état du plan qui fonde le conseil : identifiants, niveaux, exemplaires et dates des trois premiers lancements, et
    /// le nombre de lancements possibles maintenant (postes libres). Il entre dans la clé du conseil gardé.
    /// Un poste libre n'a pas de date (« maintenant ») : l'état ne change pas à chaque retour au premier plan.
    public static func etatDuPlan(_ plan: Plan, reference: ReferenceData, photo: Date) -> String {
        if plan.now.timeIntervalSince(photo) > photoPerimee { return "perimee" }
        let premiers = premiersChoix(plan: plan, reference: reference).map {
            "\($0.id)x\($0.niveau)x\($0.copies)@" + ($0.maintenant ? "maintenant" : String(Int($0.debut.timeIntervalSince1970)))
        }
        let libres = plan.steps.filter { !$0.fromSnapshot && $0.start <= plan.now }.count
        return premiers.joined(separator: ",") + "|libres=\(libres)"
    }

    /// La consigne montrée : « {quand}, lance {nom} {niveau} : {raison}. Puis {nom2} {niveau2}. Prépare {montant}. »
    /// Le modèle ne fournit que la raison ; quand, noms, niveaux et montants viennent du plan. `raison` a déjà passé les garde-fous.
    func composer(premier p: PasCandidat, raison: String, ensuite e: PasCandidat?) -> String {
        func maj(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
        func pas(_ c: PasCandidat) -> String { "\(c.nom) \(c.niveau)" + (c.copies > 1 ? " (×\(c.copies))" : "") }
        let quand = p.maintenant ? "Maintenant" : maj(Lisible.moment(p.debut, now: maintenant, timeZone: fuseau))
        var phrases = ["\(quand), lance \(pas(p)) : \(raison.prefix(1).lowercased() + raison.dropFirst())."]
        var ensemble = [p]
        if let e {
            let memeInstant = e.maintenant && p.maintenant || e.debut == p.debut
            if memeInstant { ensemble.append(e) }
            phrases.append("Puis \(pas(e))" + (memeInstant || e.maintenant ? "" : " " + Lisible.moment(e.debut, now: maintenant, timeZone: fuseau)) + ".")
        }
        let couts = Resource.allCases.compactMap { r -> String? in
            let total = ensemble.reduce(0) { $0 + $1.couts.filter { $0.resource == r }.reduce(0) { $0 + $1.amount } }
            return total > 0 ? Lisible.cout(total, r) : nil
        }
        if !couts.isEmpty { phrases.append((p.maintenant ? "Il te faut " : "Prépare ") + couts.joined(separator: " et ") + ".") }
        return phrases.joined(separator: " ")
    }
}
