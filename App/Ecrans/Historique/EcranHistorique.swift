import Charts
import ChantierKit
import SwiftUI

/// Ce que l'écran montre : les photos lisibles, celles qui ne se relisent pas, et le ticket de chacune.
struct HistoriqueAffiche: Sendable {
    let listing: HistoryStore.Listing
    /// Le ticket de chaque photo (par son `timestamp`) ; absent pour la première.
    let tickets: [Int: PhotoDiff]
    /// L'occupation des postes depuis la photo d'avant (par `timestamp`) ; absente pour la première photo.
    let occupations: [Int: Occupation]
    /// Le taux des 30 derniers jours ; nil avant trois photos sur sept jours.
    let rythme: Rhythm?

    /// Lecture complète : à faire hors de l'acteur principal (les plans se calculent).
    nonisolated static func charger(_ store: HistoryStore, _ contexte: HistoryContext) -> HistoriqueAffiche {
        let listing = store.refresh(contexte)
        var tickets: [Int: PhotoDiff] = [:]
        for e in listing.entries.dropFirst() {
            tickets[e.timestamp] = store.ticket(for: Snapshot(date: e.date), context: contexte)
        }
        let paires = store.occupations(context: contexte)
        return HistoriqueAffiche(listing: listing, tickets: tickets,
                                 occupations: Dictionary(paires.map { (Int($0.to.timeIntervalSince1970), $0) }) { $1 },
                                 rythme: Rhythm.measure(paires))
    }
}

/// L'écran Historique (PLAN §3.4) : la courbe de l'avancement total, puis les photos avec leur ticket.
struct EcranHistorique: View {
    let reference: ReferenceData
    @Environment(ModeleApp.self) private var modele
    @State private var charge: HistoriqueAffiche?
    @State private var aSupprimer: Snapshot?
    @State private var echecSuppression = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                if let charge {
                    contenu(charge)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Espace.xl)
                }
            }
            .padding(.horizontal, Theme.Espace.marge)
            .padding(.vertical, Theme.Espace.l)
        }
        .pageChantier()
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
        .task { await recharger() }
        .alert("Supprimer cette photo ?", isPresented: confirmation, presenting: aSupprimer) { photo in
            Button("Supprimer la photo", role: .destructive) { supprimer(photo) }
            Button("Garder la photo", role: .cancel) {}
        } message: { photo in
            Text("La photo du \(TexteTicket.jourHeure(photo.date)) sera effacée de l'app. Tu ne pourras pas la récupérer. Ton village dans le jeu n'est pas touché.")
        }
        .alert("Photo non supprimée", isPresented: $echecSuppression) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Le fichier n'a pas pu être effacé. Rien n'a changé.")
        }
    }

    private var confirmation: Binding<Bool> {
        Binding(get: { aSupprimer != nil }, set: { if !$0 { aSupprimer = nil } })
    }

    private func recharger() async {
        guard let source = modele.sourceHistorique else { return }
        charge = await Task.detached { HistoriqueAffiche.charger(source.store, source.contexte) }.value
        #if DEBUG
        // Captures : `-historique-supprimer 1` ouvre la confirmation sur la troisième photo en partant de la fin.
        if UserDefaults.standard.bool(forKey: "historique-supprimer"), aSupprimer == nil,
           let e = charge?.listing.entries.dropLast(2).last {
            aSupprimer = Snapshot(date: e.date)
        }
        #endif
    }

    private func supprimer(_ photo: Snapshot) {
        if modele.supprimer(photo) { Task { await recharger() } } else { echecSuppression = true }
    }

    // MARK: Contenu

    @ViewBuilder private func contenu(_ charge: HistoriqueAffiche) -> some View {
        let points = charge.listing.entries.filter { $0.total != nil }
        if points.count >= 2 {
            CourbeAvancement(points: points)
        } else {
            ExplicationHistorique(nombre: charge.listing.entries.count)
        }
        if let rythme = charge.rythme {
            CarteOccupation(rythme: rythme)
        } else if let derniere = charge.occupations.values.max(by: { $0.to < $1.to }) {
            CarteOccupation(derniere: derniere)
        }
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Photos").etiquetteChantier()
            ForEach(lignes(charge)) { ligne in
                switch ligne {
                case .photo(let entree):
                    LignePhoto(entree: entree, ticket: charge.tickets[entree.timestamp], occupation: charge.occupations[entree.timestamp],
                               reference: reference) {
                        aSupprimer = Snapshot(date: entree.date)
                    }
                case .illisible(let photo):
                    LignePhotoIllisible(photo: photo) { aSupprimer = photo }
                }
            }
        }
    }

    private enum Ligne: Identifiable {
        case photo(PhotoSummary)
        case illisible(Snapshot)
        var date: Date {
            switch self { case .photo(let e): e.date; case .illisible(let s): s.date }
        }
        var id: Date { date }
    }

    /// De la plus récente à la plus ancienne.
    private func lignes(_ charge: HistoriqueAffiche) -> [Ligne] {
        (charge.listing.entries.map(Ligne.photo) + charge.listing.unreadable.map(Ligne.illisible)).sorted { $0.date > $1.date }
    }
}

// MARK: - Courbe

/// L'avancement total au fil des photos : une ligne d'or sur le ciel, la dernière valeur en gros.
struct CourbeAvancement: View {
    let points: [PhotoSummary]
    @Environment(\.dynamicTypeSize) private var tailleTexte

    private func pourcent(_ e: PhotoSummary) -> Double { (e.total ?? 0) * 100 }

    var body: some View {
        // Le cadre suit la courbe (sinon elle s'écrase au bas d'un axe de 0 à 100).
        let bas = max(0, (points.map(pourcent).min() ?? 0).rounded(.down) - 2)
        let haut = min(100, max(bas + 5, (points.map(pourcent).max() ?? 0).rounded(.up) + 2))
        let dernier = points.last
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Avancement total").etiquetteChantier()
            if let dernier {
                Text.pourcentageGrand(dernier.total ?? 0)
            }
            Chart(points) { e in
                AreaMark(x: .value("Date", e.date), yStart: .value("Base", bas), yEnd: .value("Avancement", pourcent(e)))
                    .foregroundStyle(Theme.Couleur.or.opacity(0.25))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", e.date), y: .value("Avancement", pourcent(e)))
                    .foregroundStyle(Theme.Couleur.or)
                    .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", e.date), y: .value("Avancement", pourcent(e)))
                    .foregroundStyle(Theme.Couleur.or)
                    .symbolSize(e.id == dernier?.id ? 120 : 50)
            }
            .chartYScale(domain: bas...haut)
            .chartPlotStyle { $0.clipped() }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { valeur in
                    AxisGridLine().foregroundStyle(Theme.Couleur.trait)
                    AxisValueLabel {
                        if let v = valeur.as(Double.self) { Text("\(Int(v))\u{202F}%") }
                    }
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                }
            }
            .chartXAxis {
                // Aux grandes tailles, seulement la première et la dernière date : les étiquettes ne se chevauchent pas.
                if tailleTexte.isAccessibilitySize {
                    AxisMarks(values: [points.first?.date, points.last?.date].compactMap { $0 }) { _ in etiquetteDate }
                } else {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in etiquetteDate }
                }
            }
            .frame(height: tailleTexte.isAccessibilitySize ? 260 : 200)
            .accessibilityElement()
            .accessibilityLabel(resume)
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }

    private var etiquetteDate: some AxisMark {
        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            .font(Theme.Police.detail)
            .foregroundStyle(Theme.Couleur.texteDoux)
    }

    private var resume: String {
        guard let a = points.first, let b = points.last else { return "" }
        func p(_ e: PhotoSummary) -> String { "\(Int(pourcent(e).rounded())) pour cent" }
        return "Courbe de l'avancement total : \(p(a)) le \(TexteTicket.jourHeure(a.date)), \(p(b)) le \(TexteTicket.jourHeure(b.date)), sur \(points.count) photos."
    }
}

/// Avec une seule photo : ce qui apparaîtra, sans graphique vide.
struct ExplicationHistorique: View {
    let nombre: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text(nombre <= 1 ? "Une seule photo pour l'instant" : "Pas encore de courbe").font(Theme.Police.titre)
            Text("Après ton prochain import, tu verras ici la courbe de ton avancement. Chaque photo aura aussi son ticket : les améliorations terminées depuis la photo d'avant, et de combien le cap a bougé.")
                .font(Theme.Police.texte)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }
}

// MARK: - Lignes

/// Une photo : sa date, son avancement, son ticket.
struct LignePhoto: View {
    let entree: PhotoSummary
    let ticket: PhotoDiff?
    let occupation: Occupation?
    let reference: ReferenceData
    let supprimer: () -> Void

    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        // Aux tailles d'accessibilité : la date seule sur sa ligne, puis le pourcentage et la corbeille.
        let grande = tailleTexte.isAccessibilitySize
        let date = Text(TexteTicket.jourHeure(entree.date)).font(Theme.Police.texte.weight(.semibold))
        let total = entree.total.map { Text.pourcentageGrand($0) }
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            if grande {
                date
                HStack {
                    if let total { total }
                    Spacer(minLength: Theme.Espace.s)
                    BoutonSupprimer(photo: entree.date, action: supprimer)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    date
                    Spacer(minLength: Theme.Espace.s)
                    if let total { total }
                    BoutonSupprimer(photo: entree.date, action: supprimer)
                }
            }
            ForEach(lignesTicket, id: \.self) { Text($0).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux) }
        }
        .padding(.leading, Theme.Espace.l)
        .padding(.vertical, Theme.Espace.s)
        .padding(.trailing, Theme.Espace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }

    private var lignesTicket: [String] {
        guard let ticket else { return ["Première photo : rien à comparer"] }
        var lignes: [String] = []
        let n = ticket.finished.reduce(0) { $0 + $1.count }
        var termines = TexteTicket.termines(n)
        if n > 0 {
            let noms = ticket.finished.compactMap { reference.item($0.itemID)?.name }
            termines += " : " + noms.prefix(3).joined(separator: ", ") + (noms.count > 3 ? " et \(noms.count - 3) autre\(noms.count > 4 ? "s" : "")" : "")
        }
        lignes.append(termines)
        if let cap = TexteTicket.cap(ticket.capShift) { lignes.append(cap) }
        if let ouvriers = occupation?.post(.builder) { lignes.append("Ouvriers au travail : " + TexteOccupation.taux(ouvriers)) }
        return lignes
    }
}

/// Une photo qui ne se relit pas : signalée, gardée, supprimable.
struct LignePhotoIllisible: View {
    let photo: Snapshot
    let supprimer: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Espace.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Couleur.action)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(TexteTicket.jourHeure(photo.date)).font(Theme.Police.texte.weight(.semibold))
                Text("Cette photo ne se relit pas. L'app la garde, mais elle ne compte ni dans la courbe ni dans les tickets.")
                    .font(Theme.Police.detail)
                    .foregroundStyle(Theme.Couleur.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            BoutonSupprimer(photo: photo.date, action: supprimer)
        }
        .padding(.leading, Theme.Espace.l)
        .padding(.vertical, Theme.Espace.s)
        .padding(.trailing, Theme.Espace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }
}

private struct BoutonSupprimer: View {
    let photo: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(Theme.Police.texte)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Supprimer la photo du \(TexteTicket.jourHeure(photo))")
    }
}
