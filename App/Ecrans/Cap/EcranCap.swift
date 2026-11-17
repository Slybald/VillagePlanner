import VillagePlannerKit
import SwiftUI

/// L'écran Cap (PLAN §3.1). Avant le jalon 2 : pas de date ni de consigne, l'avancement total en grand
/// à la place de la date, puis les huit catégories.
struct EcranCap: View {
    let affiche: VillageAffiche
    let reference: ReferenceData
    @Environment(ModeleApp.self) private var modele
    @Environment(ModeleConseil.self) private var conseil
    /// Ouvrir les Réglages une fois l'écran Demander refermé (deux feuilles ne se relayent pas dans le même temps).
    @State private var reglagesApres = false
    @State private var defilement = ScrollPosition()
    @Environment(\.dynamicTypeSize) private var tailleTexte
    @Environment(\.accessibilityReduceMotion) private var reduire

    private var village: Village { affiche.village }

    var body: some View {
        @Bindable var modele = modele
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if affiche.estExemple { MarqueExemple() }
                    bandeau
                    VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                        if modele.retour != nil || modele.presseTexteAColler {
                            CartePressePapiers()
                        }
                        if let total = affiche.rapport.total {
                            avancement(total)
                            if let plan = affiche.plan {
                                consigne(plan)
                                hypotheses(plan)
                                bloquees(plan)
                            }
                            categories
                        } else {
                            inventaire
                        }
                    }
                    .padding(.horizontal, Theme.Espace.marge)
                    .padding(.vertical, Theme.Espace.l)
                }
            }
            .scrollPosition($defilement)
            #if DEBUG
            .task {       // captures : `-cap-defile <points>` fait défiler la page jusqu'à la consigne
                let y = UserDefaults.standard.double(forKey: "cap-defile")
                guard y > 0 else { return }
                try? await Task.sleep(for: .milliseconds(800))
                defilement.scrollTo(y: y)
            }
            #endif
            .pagePlanner()
            .sheet(isPresented: $modele.reglagesOuverts) { EcranReglages(reference: reference) }
            .sheet(item: $modele.ticket) { TicketPlanner(ticket: $0, reference: reference) }
            .navigationDestination(isPresented: $modele.historiqueOuvert) { EcranHistorique(reference: reference) }
            // Le conseil est demandé à l'ouverture et quand sa clé change ; pas pendant que les Réglages sont ouverts
            // (chaque réglage toucher changerait la clé) : à leur fermeture.
            .task(id: Declencheur(cle: conseil.cle(affiche, reference: reference, conseilsDate: modele.dateConseils),
                                  reglagesOuverts: modele.reglagesOuverts)) {
                guard !modele.reglagesOuverts else { return }
                conseil.rafraichir(affiche, reference: reference, conseilsDate: modele.dateConseils)
            }
            .sheet(isPresented: $modele.demanderOuvert, onDismiss: {
                if reglagesApres { reglagesApres = false; modele.reglagesOuverts = true }
            }) {
                EcranDemander(affiche: affiche, reference: reference) { reglagesApres = true; modele.demanderOuvert = false }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { modele.reglagesOuverts = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Réglages")
                }
                if let photo = affiche.photo {
                    ToolbarItem(placement: .topBarLeading) {
                        Text(photo.ageDescription(now: Date()))
                            .font(Theme.Police.detail)
                            .foregroundStyle(Theme.Couleur.texteDoux)
                            .fixedSize()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
    }

    // MARK: Bandeau

    @ViewBuilder private var bandeau: some View {
        switch village.status {
        case .ok:
            EmptyView()
        case .staleReference:
            BandeauAvertissement(titre: "Le jeu a changé", message: messageDonneesAnciennes)
        case .unknownTownHall:
            BandeauAvertissement(titre: "Hôtel de ville inconnu", message: messageHdvInconnu)
        }
    }

    private var messageDonneesAnciennes: String {
        let n = village.unknown.count
        let debut = "Données de référence du \(Self.date(reference.source.date))"
        if n > 0 {
            return "\(debut) : \(n) élément\(n > 1 ? "s" : "") inconnu\(n > 1 ? "s" : ""), exclu\(n > 1 ? "s" : "") des calculs."
        }
        return "\(debut). Ton village contient des sections ou des niveaux absents de ces données. Les chiffres touchés peuvent être faux."
    }

    private var messageHdvInconnu: String {
        if village.townHall < 1 {
            return "La photo ne contient pas d'hôtel de ville lisible. Voici son inventaire, sans pourcentage."
        }
        return "Ton HDV (\(village.townHall)) est plus haut que ceux que l'app connaît (jusqu'au \(reference.maxTownHall)). Voici l'inventaire de la photo, sans pourcentage."
    }

    /// « 9 novembre » depuis la date ISO 8601 de la référence.
    private static func date(_ iso: String) -> String {
        guard let date = try? Date(iso, strategy: .iso8601) else { return iso }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "fr_FR"))
            .day().month(.wide))
    }

    // MARK: Avancement

    private func avancement(_ total: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.l) {
            let autour = affiche.plan.map(environs) ?? []
            Terrain(hdv: village.townHall, autour: autour, libelle: libelleTerrain(autour))
            if let plan = affiche.plan {
                capTouchable(plan)
                if let rythme = plan.rythme, let tot = plan.plan.cap, let rythmique = plan.planRythme?.cap {
                    CarteRythme(auPlusTot: tot, aTonRythme: rythmique, maintenant: plan.maintenant, fuseau: plan.fuseau,
                                rythme: rythme)
                }
            } else {
                GrandeDate(surtitre: "HDV \(village.townHall)",
                           date: "\(Int((total * 100).rounded()))\u{202F}%",
                           mouvement: "d'avancement total")
            }
            VStack(alignment: .leading, spacing: Theme.Espace.s) {
                // Aux tailles d'accessibilité, le titre passe au-dessus du pourcentage : il ne se coupe plus en pleine syllabe.
                let disposition = tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Espace.xs))
                                                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                disposition {
                    Text("Avancement total").etiquettePlanner()
                    if !tailleTexte.isAccessibilitySize { Spacer() }
                    Text.pourcentageGrand(total)
                }
                Jauge(valeur: total).accessibilityHidden(true)      // le pourcentage est lu avec le titre
            }
            .accessibilityElement(children: .combine)
            if let plan = affiche.plan, let phrase = phraseDernierPoste(plan.plan) {
                Text(phrase).font(Theme.Police.texte)
            }
        }
        .animation(reduire ? nil : .snappy, value: total)
    }

    /// Toucher la date ouvre l'Historique (pas pour l'exemple, qui n'a pas de photo).
    @ViewBuilder private func capTouchable(_ plan: PlanAffiche) -> some View {
        if affiche.photo != nil {
            Button { modele.historiqueOuvert = true } label: {
                VStack(alignment: .leading, spacing: Theme.Espace.s) {
                    dateDuCap(plan)
                    HStack(spacing: Theme.Espace.xs) {
                        Text("Historique")
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .font(Theme.Police.detail.weight(.semibold))
                    .foregroundStyle(Theme.Couleur.elixirTexte)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre l'historique de tes photos")
        } else {
            dateDuCap(plan)
        }
    }

    /// La date du cap, en très grand : « HDV 16 terminé, le 14 mars », ce qu'elle exclut et sur quoi elle repose.
    private func dateDuCap(_ plan: PlanAffiche) -> some View {
        let hypothese = plan.plan.heroLimitApplied ? "avec ton profil" : "au plus tôt"
        if let cap = plan.plan.cap {
            // L'année, quand ce n'est pas la nôtre, va au-dessus : « le 10 novembre » tient sur une ligne en très grand.
            var calendrier = Calendar(identifier: .gregorian)
            calendrier.timeZone = plan.fuseau
            let annee = calendrier.component(.year, from: cap)
            let autre = annee != calendrier.component(.year, from: plan.maintenant)
            return GrandeDate(surtitre: "HDV \(village.townHall) terminé" + (autre ? " en \(annee)" : ""),
                              date: "le\u{00A0}" + Lisible.jour(cap, now: cap, timeZone: plan.fuseau),
                              mouvement: "dans " + Lisible.duree(Int(cap.timeIntervalSince(plan.maintenant).rounded(.up))),
                              mention: "hors murs et équipements · " + hypothese)
        }
        return GrandeDate(surtitre: "HDV \(village.townHall)", date: "Tout est fait",
                          mouvement: "Plus rien à améliorer.", mention: "hors murs et équipements")
    }

    /// « Hôtel de ville, niveau 16 sur 17. Dernières améliorations : Canon, niveau 14 sur 15 ; … »
    private func libelleTerrain(_ autour: [Environ]) -> String {
        let hdv = "Hôtel de ville, niveau \(village.townHall)"
        guard !autour.isEmpty else { return hdv }
        return hdv + ". Elles décident de la date : " + autour.map { "\(nom($0.id)), niveau \($0.niveau) sur \($0.maximum)" }.joined(separator: " ; ")
    }

    /// Les éléments dont dépend la date : les dernières améliorations du poste qui finit en dernier.
    private func environs(_ plan: PlanAffiche) -> [Environ] {
        guard let dernier = plan.plan.lastWorker else { return [] }
        var vus = Set<Int>()
        var out: [Environ] = []
        for pas in plan.plan.steps.filter({ $0.worker == dernier && $0.end > plan.maintenant }).sorted(by: { $0.end > $1.end }) {
            guard vus.insert(pas.step.itemID).inserted else { continue }
            out.append(Environ(id: pas.step.itemID, niveau: pas.step.element.level, maximum: pas.step.element.maxLevel))
            if out.count == 4 { break }
        }
        return out
    }

    // MARK: Consigne et hypothèses

    private func consigne(_ plan: PlanAffiche) -> some View {
        // G3 : le conseil du modèle s'il est accepté et à jour, sinon la consigne du moteur, sans un mot d'erreur.
        let cle = conseil.cle(affiche, reference: reference, conseilsDate: modele.dateConseils)
        return CarteConsigne(texte: conseil.consigne(moteur: plan.consigne, cle: cle, now: plan.maintenant),
                             reformulee: conseil.estConseil(cle: cle, now: plan.maintenant)) {
            modele.demanderOuvert = true
        }
    }

    private struct Declencheur: Hashable {
        let cle: String?
        let reglagesOuverts: Bool
    }

    /// Ce que la date suppose, en une ligne ; plus ce que la photo dit des potions et des minuteurs illisibles.
    private func hypotheses(_ plan: PlanAffiche) -> some View {
        var lignes = ["La date suppose que les ressources sont toujours là et que chaque poste relance dès qu'il est libre"
                      + (plan.profil.quietHours.map { ", sauf de \($0.start)\u{00A0}h à \($0.end)\u{00A0}h" } ?? "") + "."]
        if plan.plan.potionActive {
            lignes.append("Une potion est active dans ta photo : les fins réelles sont plus proches que ces dates.")
        }
        let n = plan.plan.unknownTimers
        if n > 0 {
            lignes.append("\(n) minuteur\(n > 1 ? "s" : "") de la photo \(n > 1 ? "sont illisibles et comptés" : "est illisible et compté") jusqu'à sa fin la plus tardive possible.")
        }
        return VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            ForEach(lignes, id: \.self) { Text($0) }
        }
        .font(Theme.Police.detail)
        .foregroundStyle(Theme.Couleur.texteDoux)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Les améliorations que la simulation ne lancera jamais (S7), une ligne par élément.
    @ViewBuilder private func bloquees(_ plan: PlanAffiche) -> some View {
        let premiers = plan.plan.blocked.reduce(into: [BlockedStep]()) { liste, b in
            if !liste.contains(where: { $0.step.itemID == b.step.itemID }) { liste.append(b) }
        }
        if !premiers.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Espace.s) {
                Text("Bloquées").etiquettePlanner()
                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    ForEach(Array(premiers.prefix(3).enumerated()), id: \.offset) { _, b in
                        Text("\(nom(b.step.itemID)) \(b.step.level) : \(raison(b.reason))").font(Theme.Police.detail)
                    }
                    if premiers.count > 3 {
                        Text("et \(premiers.count - 3) autre\(premiers.count > 4 ? "s" : "")")
                            .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                    }
                }
                .padding(Theme.Espace.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tuilePlanner()
            }
        }
    }

    private func nom(_ id: Int) -> String { reference.item(id)?.name ?? "#\(id)" }

    private func raison(_ raison: BlockedStep.Reason) -> String {
        switch raison {
        case .previousLevel: "attend son niveau précédent"
        case .noWorker: "aucun poste pour la lancer"
        case .requirement(let r): "exige \(nom(r.itemID)) \(r.level)"
        case .heroLimit: "ta limite de héros est à zéro"
        }
    }

    private var colonnes: [GridItem] {
        // Deux colonnes, une seule aux tailles d'accessibilité.
        Array(repeating: GridItem(.flexible(), spacing: Theme.Espace.m, alignment: .top),
              count: tailleTexte.isAccessibilitySize ? 1 : 2)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Catégories").etiquettePlanner()
            LazyVGrid(columns: colonnes, alignment: .leading, spacing: Theme.Espace.m) {
                ForEach(VillagePlannerKit.Category.ordreAffichage, id: \.self) { categorie in
                    let niveau = village.niveau(de: categorie.representant)
                    if let progression = affiche.rapport.categories[categorie], progression.hasWork {
                        TuileCategorie(categorie: categorie, niveau: niveau, valeur: progression.fraction)
                    } else {
                        // A4 : rien à faire à cet HDV, la catégorie sort de la moyenne.
                        TuileCategorie(categorie: categorie, niveau: niveau, texte: "rien à faire")
                    }
                }
            }
        }
        .animation(reduire ? nil : .snappy, value: affiche.rapport.total)
    }

    // MARK: HDV inconnu

    /// Ce que contient la photo, sans aucun pourcentage (V7).
    private var inventaire: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xl) {
            Terrain(hdv: min(max(village.townHall, 0), reference.maxTownHall))
            GrandeDate(surtitre: "Inventaire de la photo",
                       date: village.townHall >= 1 ? "HDV \(village.townHall)" : "HDV ?",
                       mouvement: "Pas de pourcentage pour cet HDV.")
            VStack(alignment: .leading, spacing: Theme.Espace.m) {
                Text("Catégories").etiquettePlanner()
                LazyVGrid(columns: colonnes, alignment: .leading, spacing: Theme.Espace.m) {
                    ForEach(VillagePlannerKit.Category.ordreAffichage, id: \.self) { categorie in
                        let n = village.elements
                            .filter { reference.item($0.itemID)?.category == categorie }
                            .reduce(0) { $0 + $1.count }
                        TuileCategorie(categorie: categorie, niveau: village.niveau(de: categorie.representant),
                                       texte: "\(n) élément\(n > 1 ? "s" : "")")
                    }
                }
            }
        }
    }
}
