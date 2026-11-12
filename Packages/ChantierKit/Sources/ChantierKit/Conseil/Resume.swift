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

public struct ResumeConseil: Sendable, Equatable {
    /// Version du format du résumé et des instructions : elle entre dans la clé du conseil gardé.
    public static let version = 1
    /// Au plus ce nombre d'améliorations, groupées par exemplaires lancés ensemble.
    static let ameliorationsMax = 10
    static let changementsMax = 10

    /// Le texte envoyé tel quel au modèle.
    public let texte: String
    /// Les identifiants qui figurent dans le résumé : la réponse n'en cite pas d'autres (G2).
    public let identifiants: Set<Int>

    public init(texte: String, identifiants: Set<Int>) {
        self.texte = texte
        self.identifiants = identifiants
    }

    /// `plan` et `besoins` viennent du moteur ; `consigneMoteur` est sa consigne (le modèle la reformule).
    /// `changements` : `Village.changements(depuis:)` de la photo précédente, nil quand il n'y en a pas.
    public static func make(village: Village, rapport: ProgressReport, plan: Plan, besoins: [ResourceNeed], profil: Profile,
                            reference: ReferenceData, photo: Date, consigneMoteur: String, changements: [ChangementPhoto]?,
                            timeZone: TimeZone) -> ResumeConseil {
        let now = plan.now
        func nom(_ id: Int) -> String { reference.name(of: id) ?? "#\(id)" }
        var ids = Set<Int>()
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
        lignes.append(profilEnClair(profil, village: village, plan: plan, reference: reference, ids: &ids))

        let lancements = plan.steps.filter { !$0.fromSnapshot }
        var groupes: [(step: ScheduledStep, copies: Int)] = []
        for s in lancements {
            if let i = groupes.firstIndex(where: { $0.step.step.itemID == s.step.itemID && $0.step.step.level == s.step.level && $0.step.start == s.start }) {
                groupes[i].copies += 1
            } else { groupes.append((s, 1)) }
        }
        if groupes.isEmpty {
            lignes.append("Prochaines améliorations : aucune à lancer.")
        } else {
            lignes.append("Prochaines améliorations, dans l'ordre du moteur :")
            for (s, copies) in groupes.prefix(ameliorationsMax) {
                ids.insert(s.step.itemID)
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
                    ids.insert(c.id)
                    lignes.append("- (id \(c.id)) \(nom(c.id)) " + (c.depuis == 0 ? "construit, niveau \(c.vers)" : "niveau \(c.depuis) → \(c.vers)") + ".")
                }
            }
        } else {
            lignes.append("Changements depuis la photo précédente : pas de photo précédente.")
        }
        return ResumeConseil(texte: lignes.joined(separator: "\n"), identifiants: ids)
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
        case .armyAndCastle: "le château de clan et les camps passent d'abord"
        case .build: "bâtiment à construire"
        case .hero: "héros"
        case .keyDefense: "défense clé de la liste de conseils"
        case .otherBuilding: "bâtiment"
        case .trap: "piège"
        case .advice: "en bonne place dans la liste de conseils de son poste"
        case .cheapest: "la moins chère de son poste"
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

    private static func profilEnClair(_ p: Profile, village: Village, plan: Plan, reference: ReferenceData, ids: inout Set<Int>) -> String {
        var parts = ["Profil : orientation " + (p.orientation == .attack ? "attaque" : p.orientation == .defense ? "défense" : "équilibrée")]
        parts.append(p.heroLimit.map { "limite de héros en amélioration : \($0)" } ?? "pas de limite de héros")
        let epingles = p.pinned.sorted().compactMap { id -> String? in reference.name(of: id).map { ids.insert(id); return $0 } }
        parts.append(epingles.isEmpty ? "aucune épingle" : "épinglés : " + epingles.joined(separator: ", "))
        parts.append(p.quietHours.map { "heures sans jeu de \($0.start)\u{00A0}h à \($0.end)\u{00A0}h" } ?? "pas d'heures sans jeu")
        if let n = village.workers[.builder] { parts.append("ouvriers : \(n)") }
        var texte = parts.joined(separator: ", ") + "."
        if let r = Lisible.reductions(p, at: plan.now) { texte += " " + r }
        return texte
    }
}
