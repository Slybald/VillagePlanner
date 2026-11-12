import ChantierKit
import SwiftUI

/// L'écran Cap (PLAN §3.1). Avant le jalon 2 : pas de date ni de consigne, l'avancement total en grand
/// à la place de la date, puis les huit catégories.
struct EcranCap: View {
    let affiche: VillageAffiche
    let reference: ReferenceData
    @Environment(ModeleApp.self) private var modele
    @Environment(\.dynamicTypeSize) private var tailleTexte
    @Environment(\.accessibilityReduceMotion) private var reduire

    private var village: Village { affiche.village }

    var body: some View {
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
                            categories
                        } else {
                            inventaire
                        }
                    }
                    .padding(.horizontal, Theme.Espace.marge)
                    .padding(.vertical, Theme.Espace.l)
                }
            }
            .pageChantier()
            .toolbar {
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
            Terrain(hdv: village.townHall)
            GrandeDate(surtitre: "HDV \(village.townHall)",
                       date: "\(Int((total * 100).rounded()))\u{202F}%",
                       mouvement: "d'avancement total")
            Jauge(valeur: total)
        }
        .animation(reduire ? nil : .snappy, value: total)
    }

    private var colonnes: [GridItem] {
        // Deux colonnes, une seule aux tailles d'accessibilité.
        Array(repeating: GridItem(.flexible(), spacing: Theme.Espace.m, alignment: .top),
              count: tailleTexte.isAccessibilitySize ? 1 : 2)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Catégories").etiquetteChantier()
            LazyVGrid(columns: colonnes, alignment: .leading, spacing: Theme.Espace.m) {
                ForEach(ChantierKit.Category.ordreAffichage, id: \.self) { categorie in
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
                Text("Catégories").etiquetteChantier()
                LazyVGrid(columns: colonnes, alignment: .leading, spacing: Theme.Espace.m) {
                    ForEach(ChantierKit.Category.ordreAffichage, id: \.self) { categorie in
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
