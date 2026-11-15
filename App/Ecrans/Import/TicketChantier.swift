import ChantierKit
import SwiftUI

/// Ce que l'import vient de changer : le reçu court qui s'ouvre après chaque photo (PLAN §1.3).
struct TicketAffiche: Identifiable {
    let photo: Snapshot
    let diff: PhotoDiff
    /// Pour chaque amélioration terminée : le niveau le plus haut du type dans la nouvelle photo (pour son image).
    let niveaux: [Int: Int]
    /// Les écarts entre les marques « Lancé » que l'import a effacées et ce que montre l'export (L7).
    let ecarts: [LaunchGap]
    var id: Date { photo.date }

    init(photo: Snapshot, diff: PhotoDiff, village: Village, ecarts: [LaunchGap] = []) {
        self.photo = photo
        self.diff = diff
        self.ecarts = ecarts
        niveaux = Dictionary(uniqueKeysWithValues: diff.finished.map { ($0.itemID, village.niveau(de: $0.itemID)) })
    }
}

/// Les phrases du ticket, les mêmes dans la feuille après import et dans la liste de l'Historique.
enum TexteTicket {
    /// « Cap : 2 j gagnés » ; nil quand une des deux photos n'a pas de cap.
    static func cap(_ decalage: TimeInterval?) -> String? {
        guard let decalage else { return nil }
        let secondes = Int(abs(decalage).rounded())
        guard secondes >= 60 else { return "Cap : inchangé" }
        return "Cap : " + Lisible.duree(secondes) + (decalage < 0 ? " gagnés" : " perdus")
    }

    static func termines(_ n: Int) -> String {
        n == 0 ? "Aucune amélioration terminée" : "\(n) amélioration\(n > 1 ? "s" : "") terminée\(n > 1 ? "s" : "")"
    }

    /// « 12 novembre, 9 h 48 » (avec l'année quand ce n'est pas la nôtre).
    static func jourHeure(_ date: Date, now: Date = Date()) -> String {
        let fr = Locale(identifier: "fr_FR")
        let memeAnnee = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: now)
        let base = Date.FormatStyle(date: .omitted, time: .omitted, locale: fr).day().month(.wide)
        let jour = date.formatted(memeAnnee ? base : base.year())
        let heure = date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: fr).hour(.defaultDigits(amPM: .omitted)).minute())
        return jour + ", " + heure.replacingOccurrences(of: ":", with: "\u{A0}h\u{A0}")
    }
}

/// La feuille du ticket : les améliorations terminées, avec leur image à leur nouveau niveau, et le cap.
struct TicketChantier: View {
    let ticket: TicketAffiche
    let reference: ReferenceData
    @Environment(\.dismiss) private var fermer
    @Environment(\.accessibilityReduceMotion) private var reduire
    @State private var apparu = false
    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Espace.l) {
                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    Text("Ticket de chantier").etiquetteChantier()
                    Text("Depuis ta photo du " + TexteTicket.jourHeure(ticket.diff.from))
                        .font(Theme.Police.detail)
                        .foregroundStyle(Theme.Couleur.texteDoux)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Text(TexteTicket.termines(ticket.diff.finished.reduce(0) { $0 + $1.count }))
                    .font(Theme.Police.titre)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Theme.Espace.m) {
                    ForEach(Array(ticket.diff.finished.enumerated()), id: \.element.itemID) { rang, fini in
                        ligne(fini, rang: rang)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    if let cap = TexteTicket.cap(ticket.diff.capShift) {
                        Text(cap).font(Theme.Police.chiffreGrand)
                    }
                    if let detail = autres { Text(detail).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux) }
                }

                if !ticket.ecarts.isEmpty { ecarts }

                Button("Fermer") { fermer() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Theme.Couleur.action)
                    .foregroundStyle(Theme.Couleur.surBois)
                    .frame(maxWidth: .infinity)
            }
            .padding(Theme.Espace.marge)
        }
        .pageChantier()
        .presentationBackground(Theme.Couleur.fond)
        .presentationDetents(tailleTexte.isAccessibilitySize ? [.large] : [.medium, .large])
        .sensoryFeedback(.success, trigger: apparu)
        .task { apparu = true }
    }

    /// Une amélioration terminée : son image au nouveau niveau, qui arrive l'une après l'autre.
    private func ligne(_ fini: PhotoDiff.ItemCount, rang: Int) -> some View {
        let niveau = ticket.niveaux[fini.itemID] ?? 0
        let nom = reference.item(fini.itemID)?.name ?? "#\(fini.itemID)"
        return HStack(spacing: Theme.Espace.m) {
            ZStack {
                if let image = Illustrations.image(fini.itemID, niveau: niveau) {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                        .shadow(color: Theme.Couleur.ombre, radius: 2, y: 2)
                        .overlay(alignment: .bottomLeading) { Pastille(texte: "\(niveau)") }
                }
            }
            .frame(width: 64, height: 64)
            .scaleEffect(apparu || reduire ? 1 : 0.4)
            .opacity(apparu ? 1 : 0)
            .animation(reduire ? .easeOut(duration: 0.3) : .spring(duration: 0.5, bounce: 0.5).delay(0.12 * Double(min(rang, 8))), value: apparu)
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(fini.count > 1 ? "\(nom) × \(fini.count)" : nom).font(Theme.Police.texte)
                Text("niveau \(niveau)").font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// L7 : ce que tu avais marqué « Lancé » et que l'export ne montre pas, et l'inverse. L'export fait foi : c'est dit, pas reproché.
    private var ecarts: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            Text("Écarts avec tes « Lancé »").etiquetteChantier()
            ForEach(Array(ticket.ecarts.enumerated()), id: \.offset) { _, ecart in
                let nom = reference.item(ecart.itemID)?.name ?? "#\(ecart.itemID)"
                let fois = ecart.count > 1 ? " × \(ecart.count)" : ""
                HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.s) {
                    Image(systemName: ecart.kind == .markedNotRunning ? "questionmark.circle" : "plus.circle")
                        .foregroundStyle(Theme.Couleur.elixirTexte)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(nom) \(ecart.level - 1) → \(ecart.level)\(fois)").font(Theme.Police.texte)
                        Text(ecart.kind == .markedNotRunning ? "marquée lancée, mais pas en cours dans l'export"
                                                             : "en cours dans l'export, sans avoir été marquée")
                            .font(Theme.Police.detail)
                            .foregroundStyle(Theme.Couleur.texteDoux)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("L'export fait foi : tes marques avant lui sont effacées.")
                .font(Theme.Police.detail)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuileChantier()
    }

    /// « 5 niveaux gagnés · 2 améliorations lancées ».
    private var autres: String? {
        var parts: [String] = []
        let n = ticket.diff.totalLevelsGained, l = ticket.diff.started.reduce(0) { $0 + $1.count }
        if n > 0 { parts.append("\(n) niveau\(n > 1 ? "x" : "") gagné\(n > 1 ? "s" : "")") }
        if l > 0 { parts.append("\(l) amélioration\(l > 1 ? "s" : "") lancée\(l > 1 ? "s" : "")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
