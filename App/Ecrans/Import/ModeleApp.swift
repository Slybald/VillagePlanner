import VillagePlannerKit
import Foundation
import Observation
import UIKit
import UserNotifications

/// Ce que les écrans montrent : un village calculé, et d'où il vient.
struct VillageAffiche {
    /// La photo plus les améliorations marquées « Lancé » (T28) : c'est lui que les écrans, le plan et le widget lisent.
    let village: Village
    let rapport: ProgressReport
    /// nil pour le village d'exemple, qui n'est jamais enregistré.
    let photo: Snapshot?
    /// nil quand l'HDV est inconnu (V7) : il n'y a pas de plan.
    var plan: PlanAffiche? = nil
    /// Les niveaux gagnés depuis la photo précédente (pour le conseiller) ; nil quand il n'y en a pas.
    var changements: [ChangementPhoto]? = nil
    /// Le village de la photo seule, et ce que les actions « Lancé » y ont changé (L2) ; nil sans référence.
    var villagePhoto: Village? = nil
    var lancees: LocalActionsResult? = nil
    var estExemple: Bool { photo == nil }

    /// L'action « Lancé » qui a produit ce pas en cours ; nil pour un minuteur lu dans la photo.
    func lancement(_ pas: ScheduledStep) -> LocalLaunch? { pas.fromSnapshot ? lancees?.launch(of: pas.step) : nil }
}

/// Un message au-dessus de l'écran : ce qui s'est passé, ce que l'app a gardé, quoi faire.
struct Retour: Equatable {
    let titre: String
    let detail: String
    let estErreur: Bool
}

enum OngletApp: String, Hashable {
    case cap, ouvriers, village
}

/// L'état de l'app : la dernière photo, l'exemple, le presse-papiers. Seul endroit qui touche au presse-papiers.
@MainActor @Observable
final class ModeleApp {
    /// L'instance de l'app, aussi celle de l'action Raccourcis : un import par raccourci met l'écran à jour.
    static let partage = ModeleApp()

    let reference: ReferenceData?
    private(set) var affiche: VillageAffiche?
    private(set) var retour: Retour?
    /// Le presse-papiers contient du texte qu'on n'a pas encore traité (test silencieux, sans lecture).
    private(set) var presseTexteAColler = false
    var onglet: OngletApp = .cap
    /// Le profil de jeu : tout changement est enregistré et recalcule le plan.
    var profil = Profile() {
        didSet {
            guard pret, profil != oldValue else { return }   // rien d'écrit pendant l'init
            profilStore.save(profil)
            rafraichirPlan()                                 // republie le widget et replanifie, une fois (le profil a changé)
            recalculerRythme()                               // les réductions et les heures sans jeu entrent dans la mesure
        }
    }
    /// Prévenir quand un poste se libère (T26) : éteint par défaut, gardé dans les réglages de l'app.
    private(set) var notificationsActives = false
    /// Ce qu'iOS a répondu ; `.denied` : les Réglages disent où l'autoriser.
    private(set) var autorisationNotifications = UNAuthorizationStatus.notDetermined
    /// Le taux d'occupation des 30 derniers jours (T24) ; nil tant qu'il n'y a pas trois photos sur sept jours.
    private(set) var rythme: Rhythm?
    @ObservationIgnored private var calculRythme: Task<Void, Never>?
    @ObservationIgnored private var pret = false
    /// Les Réglages sont ouverts (feuille sur l'écran Cap).
    var reglagesOuverts = false
    /// L'écran Demander est ouvert (feuille sur l'écran Cap).
    var demanderOuvert = false
    /// L'écran Historique est ouvert (poussé depuis la date du cap).
    var historiqueOuvert = false
    /// Le ticket de changements du dernier import ; nil une fois fermé (il ne revient pas pour cette photo).
    var ticket: TicketAffiche?
    /// Les améliorations marquées « Lancé » (T28). Gardées à côté des photos ; pour l'exemple, en mémoire seulement.
    private(set) var actions: [LocalAction] = []
    /// La dernière marque retirée, tant qu'on peut l'annuler.
    private(set) var retiree: LocalAction?
    /// Pourquoi la dernière marque a été refusée (écran Ouvriers) ; nil une fois une marque acceptée.
    private(set) var refusLance: String?
    private let actionsStore: LocalActionStore
    /// Ce qui a été publié au widget et aux notifications la dernière fois.
    private struct Publication: Equatable {
        let photo: Date, exemple: Bool, actions: [LocalAction], profil: Profile, equipements: EquipementsJoueur?
    }
    @ObservationIgnored private var publiee: Publication?
    /// Ce qui a monté de niveau au dernier import (type → nouveau niveau → ancien), pour l'animation.
    private var montees: [Int: [Int: Int]] = [:]
    /// Les montées déjà jouées, une fois par endroit.
    @ObservationIgnored private var monteesJouees: Set<String> = []

    /// Ce qu'il faut pour recalculer le plan quand l'heure a changé.
    private var exportCourant: VillageExport?
    private let conseils = (try? AdviceData.load()) ?? AdviceData()

    /// Les photos et leur index : TOUJOURS dans Application Support (`Photos` et `index.json`), avec ou sans App Group.
    private let historique: HistoryStore
    /// Le conteneur partagé avec le widget, où seul `PontWidget` écrit (état et images) ; nil sans l'App Group
    /// (interrupteur `VILLAGE_PLANNER_WIDGETS=NO`, compte refusé) : l'app marche alors comme avant et ne publie rien.
    private let partage: URL?
    #if DEBUG
    /// `-widget-exemple 1` : publie l'exemple au widget, dates avancées jusqu'à maintenant (captures).
    private var widgetExemple = false
    #endif
    private var store: SnapshotStore { historique.photos }
    private let profilStore: ProfilStore
    /// Les lectures du profil de joueur (T30), à côté des photos.
    let joueur: HistoriqueJoueur
    /// Ce que l'API dit des équipements à la dernière lecture ; nil avant la première (la règle V4 s'applique seule).
    private(set) var equipements: EquipementsJoueur?
    /// Les réglages de l'app (l'exemple est-il actif). En mode `-importer-fichier`, un jeu isolé : les vrais restent intacts.
    private let reglages: UserDefaults
    /// `changeCount` du presse-papiers au dernier collage : tant qu'il ne bouge pas, on ne reproposera pas le même texte.
    private var presseTraite: Int?
    private static let cleExemple = "exempleActif"
    private static let cleNotifications = "notificationsActives"

    init() {
        reference = try? ReferenceData.load()
        let arguments = UserDefaults.standard      // arguments de lancement (-ecran, -exemple…)
        var reglages = UserDefaults.standard
        var racine = URL.applicationSupportDirectory
        var recuperer = true          // le filet de sécurité ne touche jamais un dossier jetable
        var partage = Stockage.conteneurPartage(bundleID: Bundle.main.bundleIdentifier)
        var fichiersDebug: [String] = []
        #if DEBUG
        // Débogage seulement : le fichier est importé dans un dossier neuf, sans trace entre deux lancements.
        // Plusieurs chemins séparés par « : » sont importés dans l'ordre (pour montrer un import refusé après un bon).
        let chemin = arguments.string(forKey: "importer-fichier")
        // `-historique-calme 1` avec le précédent : une série où peu d'éléments montent (taux d'occupation vraisemblable).
        // `-historique-exemple <n>` : n photos tirées de l'exemple (les n − 1 premières écrites, la dernière importée,
        // pour voir son ticket), dans le même dossier jetable.
        let nExemple = arguments.integer(forKey: "historique-exemple")
        if chemin != nil || nExemple > 0 {
            let jetable = FileManager.default.temporaryDirectory.appending(path: "villageplanner-import-debug")
            racine = jetable
            recuperer = false
            if !arguments.bool(forKey: "widget-exemple") { partage = nil }     // un dossier jetable ne publie rien au widget
            try? FileManager.default.removeItem(at: jetable)
            fichiersDebug = chemin?.split(separator: ":").map(String.init) ?? []
            let nom = "villageplanner-import-debug"
            UserDefaults.standard.removePersistentDomain(forName: nom)
            reglages = UserDefaults(suiteName: nom) ?? reglages
        }
        #endif
        var retourDemarrage: Retour?
        if recuperer, let partage {
            // Versions de test qui avaient déplacé les photos dans le conteneur : on les COPIE ici, sans rien supprimer.
            let bilan = Stockage.recuperer(depuis: partage, vers: racine)
            if !bilan.conflits.isEmpty {
                retourDemarrage = Retour(titre: "Photos récupérées", detail: "\(bilan.conflits.count) photo(s) portaient le même nom qu'une photo de l'app avec un contenu différent : elles sont gardées à côté, sous un nom en « .conflit ».", estErreur: false)
            }
        }
        self.partage = partage
        historique = HistoryStore(root: racine)
        actionsStore = LocalActionStore(root: racine)
        let lectures = HistoriqueJoueur(root: racine)
        joueur = lectures
        #if DEBUG
        if arguments.bool(forKey: "joueur-historique-exemple") { JoueurExemple.ecrire(dans: lectures) }   // captures
        #endif
        equipements = reference.flatMap { lectures.equipements(reference: $0) }
        self.reglages = reglages
        notificationsActives = reglages.bool(forKey: Self.cleNotifications)
        profilStore = ProfilStore(defaults: reglages)
        profil = profilStore.load()
        var texteExemple: String?
        #if DEBUG
        // Captures : `-reduction <pourcentage>` met une réduction d'ouvriers sans fin, sans l'enregistrer.
        let pourcentage = arguments.integer(forKey: "reduction")
        // `-profil-b64 <JSON en base 64>` : un profil de capture, sans l'enregistrer (une accolade brute serait lue comme une liste de propriétés).
        if let b64 = arguments.string(forKey: "profil-b64"), let data = Data(base64Encoded: b64),
           let p = try? JSONDecoder().decode(Profile.self, from: data) { profil = p }
        if pourcentage > 0 { profil.builderReduction = Reduction(percent: pourcentage, endsAt: .distantFuture) }
        if arguments.bool(forKey: "reglages") { reglagesOuverts = true }
        if arguments.bool(forKey: "demander") { demanderOuvert = true }
        if arguments.bool(forKey: "historique") { historiqueOuvert = true }
        if nExemple > 0 {
            var textes = HistoriqueExemple.textes(nExemple, calme: arguments.bool(forKey: "historique-calme"))
            texteExemple = textes.popLast()
            for t in textes { _ = try? store.save(t) }
            if arguments.bool(forKey: "historique-illisible") {     // une photo qui ne se relit pas, entre deux bonnes
                try? "{\"timestamp\":".write(to: store.directory.appending(path: Snapshot(date: Date(timeIntervalSince1970: 1_794_000_000)).fileName),
                                              atomically: true, encoding: .utf8)
            }
        }
        #endif

        actions = actionsStore.load()
        var actionsExemple: [LocalAction] = []
        #if DEBUG
        // Captures : `-actions-b64 <JSON en base 64>` (liste de `LocalAction`, dates en secondes) : des marques « Lancé »
        // gardées dans le dossier jetable avant l'import (écarts du ticket), ou en mémoire pour l'exemple.
        if let b64 = arguments.string(forKey: "actions-b64"), let data = Data(base64Encoded: b64) {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .secondsSince1970
            if let lues = try? d.decode([LocalAction].self, from: data) {
                actionsExemple = lues
                if !recuperer { actions = lues; actionsStore.save(lues) }
            }
        }
        #endif

        if !fichiersDebug.isEmpty {
            for chemin in fichiersDebug {
                if let texte = try? String(contentsOfFile: chemin, encoding: .utf8) { importer(texte) }
            }
        } else if let texteExemple {
            importer(texteExemple)
            #if DEBUG
            if arguments.bool(forKey: "sans-ticket") { ticket = nil }
            #endif
        } else if arguments.bool(forKey: "exemple") {
            #if DEBUG
            widgetExemple = arguments.bool(forKey: "widget-exemple")
            #endif
            chargerExemple(retenir: false, actions: actionsExemple)   // `-exemple 1` : pour les captures, rien n'est retenu
        } else if let derniere = store.latest() {
            affiche = calculer(derniere.export, photo: derniere.snapshot)
        } else if reglages.bool(forKey: Self.cleExemple) {
            chargerExemple(retenir: false)
        }
        if let ecran = arguments.string(forKey: "ecran"), let demande = OngletApp(rawValue: ecran) { onglet = demande }
        rafraichirPressePapiers()
        retour = retourDemarrage
        pret = true
        recalculerRythme()
    }

    // MARK: Import

    /// Texte collé avec le bouton système, ou donné par l'action Raccourcis. Un texte qui n'est pas un export ne change rien.
    /// Rend la phrase de résultat (l'action la dit ; les écrans montrent `retour` et le ticket).
    @discardableResult
    func importer(_ texte: String) -> String {
        guard let contexte else { return "Les données du jeu sont illisibles : réinstalle l'app" }
        let avant = affiche?.estExemple == false ? affiche?.village : nil   // depuis l'exemple : rien à animer
        let marquees = actionsStore.load()
        // L3 : l'import efface les actions « Lancé » qui ne sont pas postérieures à l'export (celles de l'exemple partent aussi).
        let resultat = ResultatImport.importer(texte, dans: historique, context: contexte, actions: actionsStore) { derniere, export in
            actions = actionsStore.load()
            retiree = nil
            refusLance = nil
            affiche = calculer(export, photo: derniere)    // recalcule, recharge le widget, replanifie les notifications
        }
        switch resultat {
        case .refuse(let erreur):
            retour = Self.message(pour: erreur, avecPhoto: affiche?.estExemple == false)
        case .enregistree, .dejaPresente:
            if let avant, let apres = affiche?.village {
                montees = apres.montees(depuis: avant)
                monteesJouees = []
            }
            reglages.removeObject(forKey: Self.cleExemple)    // le premier vrai import efface l'exemple
            recalculerRythme()
            onglet = .cap
            if case .enregistree(let photo, let plusRecente) = resultat {
                if plusRecente {
                    retour = nil
                    // Le ticket : ce qui a changé depuis la photo d'avant. Rien pour la première photo.
                    // L7 : les écarts entre les marques effacées et ce que montre l'export.
                    let effacees = marquees.filter { !actions.contains($0) }
                    let ecarts = affiche?.villagePhoto.flatMap { nouveau in
                        villagePrecedent(avant: photo, reference: contexte.reference).map { launchGaps(erased: effacees, old: $0, new: nouveau) }
                    } ?? []
                    ticket = historique.ticket(for: photo, context: contexte).flatMap { diff in
                        affiche.map { TicketAffiche(photo: photo, diff: diff, village: $0.village, ecarts: ecarts) }
                    }
                } else {
                    retour = Retour(titre: "Photo plus ancienne", detail: "Elle est gardée, mais l'écran montre ta photo la plus récente.", estErreur: false)
                }
            } else {
                retour = Retour(titre: "Déjà enregistré", detail: "Cet export est déjà dans tes photos. Rien n'a changé.", estErreur: false)
            }
        }
        presseTraite = UIPasteboard.general.changeCount
        presseTexteAColler = false
        return resultat.phrase(cap: affiche?.plan?.plan.cap, now: maintenant, timeZone: affiche?.plan?.fuseau ?? .current)
    }

    private static func message(pour erreur: SnapshotStore.SaveError, avecPhoto: Bool) -> Retour {
        let garde = avecPhoto ? "Rien n'a changé : ta dernière photo reste affichée." : "Rien n'a changé."
        switch erreur {
        case .invalid(.empty):
            return Retour(titre: "Le texte est vide", detail: "\(garde) Copie l'export dans le jeu, puis reviens ici.", estErreur: true)
        case .invalid(.tooLarge):
            return Retour(titre: "Ce n'est pas un export de village", detail: "\(garde) Le texte est beaucoup trop long pour en être un.", estErreur: true)
        case .invalid(.notJSON):
            return Retour(titre: "Ce n'est pas un export de village", detail: "\(garde) Le texte est illisible ou coupé : copie l'export en entier, depuis le jeu.", estErreur: true)
        case .invalid(.notAVillageExport):
            return Retour(titre: "Ce n'est pas un export de village", detail: "\(garde) Dans le jeu : Data Export, puis Copier.", estErreur: true)
        case .cannotWrite:
            return Retour(titre: "Photo non enregistrée", detail: "L'espace de l'app n'est pas accessible en écriture. \(garde)", estErreur: true)
        }
    }

    // MARK: Exemple

    /// Le village embarqué : en mémoire seulement, jamais dans les photos.
    /// `actions` : les marques « Lancé » de l'exemple, en mémoire (celles des vraies photos ne s'y appliquent pas).
    func chargerExemple(retenir: Bool = true, actions: [LocalAction] = []) {
        self.actions = actions
        retiree = nil
        guard let url = Bundle.main.url(forResource: "exemple-village", withExtension: "json"),
              let texte = try? String(contentsOf: url, encoding: .utf8),
              let export = try? VillageExport.parse(texte) else { return }
        affiche = calculer(export, photo: nil)
        if retenir { reglages.set(true, forKey: Self.cleExemple) }
        onglet = .cap
    }

    private func calculer(_ export: VillageExport, photo: Snapshot?) -> VillageAffiche? {
        guard let reference else { return nil }
        exportCourant = export
        let villagePhoto = Village(export: export, reference: reference, joueur: equipements)
        let changements = photo.flatMap { villagePrecedent(avant: $0, reference: reference) }.map { villagePhoto.changements(depuis: $0) }
        return afficher(villagePhoto, export: export, photo: photo, changements: changements, reference: reference)
    }

    /// La photo plus les actions « Lancé », son plan, et ce qui en dépend hors de l'app (widget, notifications).
    private func afficher(_ villagePhoto: Village, export: VillageExport, photo: Snapshot?, changements: [ChangementPhoto]?,
                          reference: ReferenceData) -> VillageAffiche {
        let lancees = villagePhoto.applying(actions, reference: reference, profile: profil)
        let village = lancees.village
        let plan = plan(village: village, export: export, reference: reference, estExemple: photo == nil)
        // Widget et notifications : une fois par changement réel (photo, marques, profil, équipements), pas à chaque
        // retour au premier plan.
        let cle = Publication(photo: villagePhoto.date, exemple: photo == nil, actions: lancees.applied.map(\.action),
                              profil: profil, equipements: equipements)
        if cle != publiee {
            publiee = cle
            publierAuWidget(plan: plan?.plan, village: village, reference: reference, photo: photo, lancees: lancees)
            planifierNotifications(plan: plan?.plan, estExemple: photo == nil)    // chaque import annule et replanifie
        }
        return VillageAffiche(village: village, rapport: progress(of: village, reference: reference), photo: photo,
                              plan: plan, changements: changements, villagePhoto: villagePhoto, lancees: lancees)
    }

    /// Chaque photo affichée (import, suppression, lancement) remet l'état du widget d'accord et recharge sa chronologie.
    /// L'exemple n'est jamais publié, sauf en débogage avec `-widget-exemple 1`.
    private func publierAuWidget(plan: Plan?, village: Village, reference: ReferenceData, photo: Snapshot?,
                                 lancees: LocalActionsResult? = nil) {
        var decalage: TimeInterval = 0
        #if DEBUG
        if photo == nil, widgetExemple, let plan { decalage = Date().timeIntervalSince(plan.now) } else if photo == nil { return }
        #else
        if photo == nil { return }
        #endif
        guard let plan else { PontWidget.retirer(partage: partage); return }
        PontWidget.publier(plan: plan, village: village, reference: reference, partage: partage, decalage: decalage,
                           lancees: lancees)
    }

    // MARK: Notifications

    /// Allume ou éteint l'option. Allumer demande l'autorisation à iOS ; refusée, l'option reste éteinte.
    func reglerNotifications(_ voulu: Bool) {
        guard voulu else { fixerNotifications(false); return }
        Task {
            let accordee = await Notifications.autoriser()
            autorisationNotifications = await Notifications.statut()
            fixerNotifications(accordee)
        }
    }

    /// Au retour dans les Réglages d'iOS : une autorisation retirée remet l'option à éteint.
    func rafraichirAutorisationNotifications() async {
        autorisationNotifications = await Notifications.statut()
        if notificationsActives, autorisationNotifications == .denied { fixerNotifications(false) }
    }

    private func fixerNotifications(_ actives: Bool) {
        notificationsActives = actives
        reglages.set(actives, forKey: Self.cleNotifications)
        if actives { planifierNotifications(plan: affiche?.plan?.plan, estExemple: affiche?.estExemple ?? true) } else { Notifications.annuler() }
    }

    /// Annule les notifications en attente et pose celles du plan (T26). L'exemple n'en pose jamais, sauf en débogage
    /// avec `-notification-dans <secondes>` : la première fin est avancée à maintenant + ce délai (captures).
    private func planifierNotifications(plan: Plan?, estExemple: Bool) {
        guard notificationsActives, let reference else { return }
        var quietHours = profil.quietHours
        quietHours?.timeZone = .current                       // les heures sans jeu sont celles de l'appareil
        #if DEBUG
        let dans = UserDefaults.standard.double(forKey: "notification-dans")
        if estExemple, dans > 0 { quietHours = nil } else if estExemple { return }
        #else
        if estExemple { return }
        #endif
        guard let plan else { Notifications.annuler(); return }
        var liste = Echeances.liste(plan: plan, nom: { reference.item($0)?.name ?? "Amélioration" }, quietHours: quietHours, now: plan.now)
        #if DEBUG
        if estExemple, let premiere = liste.first?.date {         // la première part dans `dans` secondes, les autres gardent leur écart
            let decalage = Date().addingTimeInterval(dans).timeIntervalSince(premiere)
            liste = liste.map { Echeance(date: $0.date.addingTimeInterval(decalage), titre: $0.titre, corps: $0.corps) }
        }
        #endif
        Notifications.remplacer(par: liste)
    }

    /// La photo juste avant celle-ci, lue dans le dossier des photos ; nil quand il n'y en a pas.
    private func villagePrecedent(avant photo: Snapshot, reference: ReferenceData) -> Village? {
        guard let precedente = store.list().last(where: { $0.date < photo.date }), let texte = store.text(of: precedente),
              let export = try? VillageExport.parse(texte) else { return nil }
        return Village(export: export, reference: reference, joueur: equipements)
    }

    private func plan(village: Village, export: VillageExport, reference: ReferenceData, estExemple: Bool) -> PlanAffiche? {
        guard village.status != .unknownTownHall else { return nil }
        return PlanAffiche(village: village, export: export, reference: reference, conseils: conseils, profil: profil,
                           maintenant: PlanAffiche.horloge(village: village, estExemple: estExemple),
                           aujourdhui: estExemple ? Date() : nil,
                           rythme: estExemple ? nil : rythme)
    }

    /// Ce qu'il faut pour recalculer le plan avec une variante (questions de l'écran Demander, T21).
    func contexteQuestion(_ affiche: VillageAffiche, reference: ReferenceData) -> ContexteQuestion? {
        guard let plan = affiche.plan, let exportCourant else { return nil }
        return ContexteQuestion(village: affiche.village, export: exportCourant, reference: reference, advice: conseils,
                                profil: plan.profil, now: plan.maintenant)
    }

    /// Ce qu'il faut pour lire l'historique (écran Historique) ; nil sans données de référence.
    var sourceHistorique: (store: HistoryStore, contexte: HistoryContext)? { contexte.map { (historique, $0) } }

    /// Idem pour les mesures d'occupation : les heures sans jeu dans le fuseau de l'appareil, comme le plan (`PlanAffiche`).
    var sourceOccupation: (store: HistoryStore, contexte: HistoryContext)? {
        contexte.map { c in
            var profil = c.profile
            profil.quietHours?.timeZone = .current
            return (historique, HistoryContext(reference: c.reference, advice: c.advice, profile: profil))
        }
    }

    private var contexte: HistoryContext? {
        reference.map { HistoryContext(reference: $0, advice: conseils, profile: profil) }
    }

    /// Supprime une photo (geste confirmé par l'utilisateur) et remet l'écran sur la plus récente restante.
    /// Sans photo restante, l'app revient au premier lancement. Faux si le fichier ne s'efface pas.
    func supprimer(_ photo: Snapshot) -> Bool {
        guard let contexte else { return false }
        do { _ = try historique.delete(photo, context: contexte) } catch { return false }
        ticket = nil
        montees = [:]
        recalculerRythme()
        if let derniere = store.latest() {
            affiche = calculer(derniere.export, photo: derniere.snapshot)
        } else {
            affiche = nil
            exportCourant = nil
            historiqueOuvert = false
            PontWidget.retirer(partage: partage)
            publiee = nil
        }
        return true
    }

    /// La date du calcul : celle du plan, sinon l'heure de l'appareil (l'exemple se lit à la date de son export).
    var maintenant: Date { affiche?.plan?.maintenant ?? Date() }
    /// Date de la dernière révision des conseils (ISO 8601, jour).
    var dateConseils: String { conseils.date }

    /// Mesure le rythme sur les photos (hors de l'acteur principal : il faut relire les photos des 30 derniers jours)
    /// puis recalcule le plan quand il change.
    func recalculerRythme() {
        calculRythme?.cancel()
        guard let source = sourceOccupation else { rythme = nil; return }
        calculRythme = Task { [weak self] in
            let mesure = await Task.detached { source.store.rhythm(context: source.contexte) }.value
            guard !Task.isCancelled, let self, self.rythme != mesure else { return }
            self.rythme = mesure
            self.rafraichirPlan()
        }
    }

    /// Au retour au premier plan : les postes libérés, les échéances et la consigne suivent l'heure.
    func rafraichirPlan() {
        guard let affiche, let reference, let exportCourant else { return }
        // L6 : les actions « Lancé » se réappliquent avec le profil du moment.
        guard let villagePhoto = affiche.villagePhoto else { return }
        self.affiche = afficher(villagePhoto, export: exportCourant, photo: affiche.photo, changements: affiche.changements,
                                reference: reference)
    }

    // MARK: « Lancé » (T28)

    /// Marque lancée l'amélioration conseillée d'un poste libre, maintenant. Rien n'est écrit dans la photo.
    /// Refusée (poste occupé, exemplaire introuvable) : un message, et rien ne change.
    func marquerLance(_ pas: ScheduledStep, couloir: Int? = nil) {
        guard let affiche, let reference, let villagePhoto = affiche.villagePhoto else { return }
        let action = LocalAction(itemID: pas.step.itemID, level: pas.step.level,
                                 start: PlanAffiche.horloge(village: villagePhoto, estExemple: affiche.estExemple), lane: couloir)
        let essai = villagePhoto.applying(actions + [action], reference: reference, profile: profil)
        if let refus = essai.refused.first(where: { $0.action == action }) {
            refusLance = switch refus.reason {
            case .postBusy: "Pas marquée : d'après ta photo, aucun poste n'est libre pour elle."
            case .noIdleCopy: "Pas marquée : ta photo n'a pas d'exemplaire prêt pour ce niveau."
            case .beforeSnapshot: "Pas marquée : ta photo est plus récente, elle fait foi."
            }
            return
        }
        guard changerActions(actions + [action]) else { return }
        refusLance = nil
        retiree = nil
    }

    /// Retire une marque « Lancé » (geste sur le couloir) ; `annulerRetrait()` la remet.
    func retirerLance(_ action: LocalAction) {
        if changerActions(actions.filter { $0 != action }) { retiree = action }
    }

    func annulerRetrait() {
        guard let retiree, changerActions(actions + [retiree]) else { return }
        self.retiree = nil
    }

    /// Enregistre puis affiche. Faux (et rien ne change à l'écran) si le fichier ne s'écrit pas : une marque non gardée
    /// disparaîtrait au prochain lancement.
    private func changerActions(_ nouvelles: [LocalAction]) -> Bool {
        if affiche?.estExemple == false, !actionsStore.save(nouvelles) {        // l'exemple ne retient rien
            refusLance = "Pas enregistré : l'espace de l'app n'est pas accessible en écriture. Rien n'a changé."
            return false
        }
        actions = nouvelles
        rafraichirPlan()
        return true
    }

    /// Le tag du joueur, lu dans la dernière photo (jamais en dur) ; nil sans photo lisible. Sert à l'API officielle (T29).
    var tagJoueur: String? { store.latest()?.export.tag }

    /// Une lecture réussie du profil (T30) : elle est gardée avec sa date, et les équipements équipés passent en tête de la forge.
    func joueurLu(_ profil: ProfilJoueur, le date: Date) {
        joueur.enregistrer(profil, le: date)
        guard let reference else { return }
        guard let nouveaux = EquipementsJoueur(profil: profil, reference: reference), nouveaux != equipements else { return }
        equipements = nouveaux
        if let derniere = store.latest(), affiche?.estExemple == false {
            affiche = calculer(derniere.export, photo: derniere.snapshot)
        }
    }

    // MARK: Presse-papiers

    /// Au retour au premier plan. `hasStrings` et `changeCount` ne lisent rien et n'affichent aucune alerte.
    func rafraichirPressePapiers() {
        let presse = UIPasteboard.general
        if presse.changeCount != presseTraite { retour = nil }       // un nouveau texte efface l'ancien message
        presseTexteAColler = presse.hasStrings && presse.changeCount != presseTraite
    }

    func fermerRetour() { retour = nil }

    // MARK: Montées de niveau

    /// L'ancien niveau d'un élément qui vient de monter, la première fois qu'on le montre à cet endroit.
    func montee(id: Int, niveau: Int, lieu: String) -> Int? {
        guard let ancien = montees[id]?[niveau], monteesJouees.insert("\(lieu)-\(id)-\(niveau)").inserted else { return nil }
        return ancien
    }
}
