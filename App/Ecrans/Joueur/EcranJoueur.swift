import Charts
import VillagePlannerKit
import SwiftUI

extension ModeleApp {
    /// Lit le profil, le garde (historique et équipements) puis le rend. Un seul chemin pour le bouton des Réglages et pour l'écran Joueur.
    func lireProfil(avec client: ClientJoueur, tag: String?) async throws(JoueurError) -> ProfilJoueur {
        let maintenant = Date()
        let profil = try await client.lire(tag: tag, now: maintenant)
        joueurLu(profil, le: maintenant)
        return profil
    }
}

/// L'écran Joueur (PLAN §3.4, T30) : les valeurs de la dernière lecture, leurs courbes, les équipements équipés.
/// Sans clé ni lecture, il dit en deux phrases ce qu'il montrerait et où l'activer. Rien ne part sans clé.
struct EcranJoueur: View {
    @Environment(ModeleApp.self) private var modele
    @Environment(\.dismiss) private var fermer
    private let outils = SectionCompteDeJeu.Outils.partages
    @State private var lectures: [LectureJoueur] = []
    @State private var equipes: [HerosEquipe] = []
    @State private var cle = KeyState.absent
    @State private var message: String?
    @State private var enCours = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                if let derniere = lectures.last {
                    ValeursJoueur(lecture: derniere)
                    CourbesJoueur(lectures: lectures)
                    if !equipes.isEmpty, let reference = modele.reference { EquipementsEquipes(heros: equipes, reference: reference) }
                } else {
                    ExplicationJoueur(cle: cle, enCours: enCours, lire: lire, retour: { fermer() })
                }
                if let message { Text(message).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texte) }
                if !lectures.isEmpty { pied }
            }
            .padding(.horizontal, Theme.Espace.marge)
            .padding(.vertical, Theme.Espace.l)
        }
        .pagePlanner()
        .navigationTitle("Joueur")
        .navigationBarTitleDisplayMode(.inline)
        .task { await ouvrir() }
    }

    private var pied: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            if let derniere = lectures.last {
                Text("Dernière lecture : \(derniere.date.formatted(.dateTime.day().month(.wide).hour().minute()))")
                    .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
            }
            if case .present = cle {
                Button { Task { await lireEtRecharger() } } label: {
                    HStack { Text("Lire mon profil"); if enCours { ProgressView() } }
                }
                .foregroundStyle(Theme.Couleur.elixirTexte)
                .disabled(enCours)
            } else {
                Text("Pour continuer les courbes, colle une clé d'API dans Réglages, section Compte de jeu.")
                    .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
            }
        }
    }

    // MARK: Gestes

    private func ouvrir() async {
        recharger()
        // Une lecture à l'ouverture de l'écran : le client n'en permet qu'une par ouverture de l'app et une par heure.
        if case .present = cle { await lireEtRecharger() }
    }

    private func recharger() {
        cle = APIKey.state(of: outils.cles)
        lectures = modele.joueur.lectures()
        equipes = modele.joueur.equipes()
    }

    private func lire() { Task { await lireEtRecharger() } }

    private func lireEtRecharger() async {
        guard !enCours else { return }
        enCours = true
        message = nil
        do throws(JoueurError) {
            _ = try await modele.lireProfil(avec: outils.client, tag: outils.tagExemple ?? modele.tagJoueur)
        } catch {
            // Trop tôt : rien à dire, les dernières valeurs sont déjà à l'écran. Le reste s'explique.
            if case .tooSoon = error {} else { message = SectionCompteDeJeu.texte(error) }
        }
        enCours = false
        recharger()
    }
}

// MARK: - Sans lecture

/// Pas encore de lecture : ce que l'écran montrerait, et le geste qui le remplit.
struct ExplicationJoueur: View {
    let cle: KeyState
    let enCours: Bool
    let lire: () -> Void
    let retour: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Ton profil de joueur").font(Theme.Police.titre)
            Text("Cet écran montrerait tes trophées, ta ligue, tes étoiles de guerre et tes dons, avec leur courbe, et les équipements que portent tes héros.")
                .font(Theme.Police.texte).foregroundStyle(Theme.Couleur.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
            switch cle {
            case .present:
                Text("Ta clé est enregistrée : aucune lecture n'a encore réussi.")
                    .font(Theme.Police.texte).fixedSize(horizontal: false, vertical: true)
                Button(action: lire) { HStack { Text("Lire mon profil"); if enCours { ProgressView() } } }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .tint(Theme.Couleur.action).foregroundStyle(Theme.Couleur.surBois)
                    .disabled(enCours)
            case .unavailable:
                Text("Le Trousseau ne répond pas. Déverrouille l'iPhone, puis rouvre cet écran.")
                    .font(Theme.Police.texte).fixedSize(horizontal: false, vertical: true)
            case .absent:
                Text("Pour l'activer, colle une clé d'API dans Réglages, section Compte de jeu : c'est facultatif, le reste de l'app marche sans.")
                    .font(Theme.Police.texte).fixedSize(horizontal: false, vertical: true)
                Button("Aller aux Réglages", action: retour)
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .tint(Theme.Couleur.action).foregroundStyle(Theme.Couleur.surBois)
            }
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuilePlanner()
    }
}

// MARK: - Valeurs

/// Les valeurs de la dernière lecture, en lignes (pas en grille de cases).
struct ValeursJoueur: View {
    let lecture: LectureJoueur

    private func nombre(_ n: Int?) -> String { n.map { $0.formatted(.number.locale(Locale(identifier: "fr_FR"))) } ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Maintenant").etiquettePlanner()
            ligne("Trophées", nombre(lecture.trophees))
            ligne("Record", nombre(lecture.record))
            ligne("Ligue", lecture.ligue ?? "—")
            ligne("Étoiles de guerre", nombre(lecture.etoilesGuerre))
            ligne("Dons", nombre(lecture.dons))
            ligne("Victoires en attaque", nombre(lecture.victoiresAttaque))
            ligne("Victoires en défense", nombre(lecture.victoiresDefense))
            if let t = lecture.succesTermines { ligne("Succès terminés", "\(t)") }
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuilePlanner()
        .accessibilityElement(children: .contain)
    }

    private func ligne(_ nom: String, _ valeur: String) -> some View {
        // Accessibilité : nom et valeur se lisent ensemble ; au très grand corps, la valeur passe sous le nom.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(nom).font(Theme.Police.texte)
                Spacer(minLength: Theme.Espace.s)
                Text(valeur).font(Theme.Police.chiffre).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(nom).font(Theme.Police.texte)
                Text(valeur).font(Theme.Police.chiffre).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Courbes

struct CourbesJoueur: View {
    let lectures: [LectureJoueur]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xl) {
            CourbeJoueur(titre: "Trophées", lectures: lectures, chiffre: \.trophees, couleur: Theme.Couleur.or)
            CourbeJoueur(titre: "Étoiles de guerre", lectures: lectures, chiffre: \.etoilesGuerre, couleur: Theme.Couleur.elixirTexte)
            CourbeJoueur(titre: "Dons", lectures: lectures, chiffre: \.dons, couleur: Theme.Couleur.herbe)
        }
    }
}

/// Un chiffre au fil des lectures : la dernière valeur, ce qu'elle a bougé, la courbe. Une seule lecture : pas de courbe vide.
struct CourbeJoueur: View {
    let titre: String
    let lectures: [LectureJoueur]
    let chiffre: KeyPath<LectureJoueur, Int?>
    let couleur: Color
    @Environment(\.dynamicTypeSize) private var tailleTexte

    private var points: [(date: Date, valeur: Int)] { LectureJoueur.serie(lectures, chiffre) }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text(titre).etiquettePlanner()
            if let dernier = points.last {
                Text(dernier.valeur.formatted(.number.locale(Locale(identifier: "fr_FR")))).font(Theme.Police.chiffreGrand)
                if let premier = points.first, points.count >= 2 {
                    let ecart = dernier.valeur - premier.valeur
                    Text("\(ecart >= 0 ? "+" : "−")\(abs(ecart).formatted(.number.locale(Locale(identifier: "fr_FR")))) depuis le \(premier.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                } else {
                    Text("Une seule lecture : la courbe apparaît à la prochaine.").font(Theme.Police.detail)
                        .foregroundStyle(Theme.Couleur.texteDoux).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Le service n'a pas donné ce chiffre.").font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
            }
            if points.count >= 2 { courbe(points) }
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuilePlanner()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resume(points))
    }

    private func courbe(_ points: [(date: Date, valeur: Int)]) -> some View {
        let valeurs = points.map(\.valeur)
        let (bas, haut) = (valeurs.min() ?? 0, valeurs.max() ?? 1)
        let marge = max(1, (haut - bas) / 8)
        return Chart {
            ForEach(points, id: \.date) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Base", bas - marge), yEnd: .value(titre, p.valeur))
                    .foregroundStyle(couleur.opacity(0.25)).interpolationMethod(.monotone)
                LineMark(x: .value("Date", p.date), y: .value(titre, p.valeur))
                    .foregroundStyle(couleur)
                    .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
            }
            if let dernier = points.last {
                PointMark(x: .value("Date", dernier.date), y: .value(titre, dernier.valeur)).foregroundStyle(couleur).symbolSize(120)
            }
        }
        .chartYScale(domain: (bas - marge)...(haut + marge))
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.Couleur.trait)
                AxisValueLabel().font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
            }
        }
        .chartXAxis {
            if tailleTexte.isAccessibilitySize {
                AxisMarks(values: [points.first?.date, points.last?.date].compactMap { $0 }) { _ in etiquetteDate }
            } else {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in etiquetteDate }
            }
        }
        .frame(height: tailleTexte.isAccessibilitySize ? 240 : 170)
    }

    private var etiquetteDate: some AxisMark {
        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
    }

    private func resume(_ points: [(date: Date, valeur: Int)]) -> String {
        guard let a = points.first, let b = points.last else { return "\(titre) : pas de chiffre." }
        if points.count < 2 { return "\(titre) : \(b.valeur), une seule lecture." }
        return "\(titre) : \(b.valeur) à la dernière lecture, \(a.valeur) le \(a.date.formatted(.dateTime.day().month(.wide))), sur \(points.count) lectures."
    }
}

// MARK: - Équipements

/// Les équipements que chaque héros porte (lus à la dernière lecture).
struct EquipementsEquipes: View {
    let heros: [HerosEquipe]
    let reference: ReferenceData

    private func element(_ nom: String, _ categorie: VillagePlannerKit.Category = .equipment) -> (id: Int?, nom: String) {
        let id = EquipementsJoueur.identifiant(nom, dans: reference, categorie: categorie)
        return (id, id.flatMap { reference.item($0)?.name } ?? nom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.l) {
            Text("Équipés").etiquettePlanner()
            ForEach(heros, id: \.heros) { h in
                let (idHeros, nomHeros) = element(h.heros, .heroes)
                VStack(alignment: .leading, spacing: Theme.Espace.s) {
                    HStack(spacing: Theme.Espace.m) {
                        image(idHeros, 44)
                        Text(nomHeros).font(Theme.Police.texte.weight(.semibold))
                    }
                    ForEach(h.equipements, id: \.self) { e in
                        let (id, nom) = element(e)
                        HStack(spacing: Theme.Espace.m) {
                            image(id, 32)
                            Text(nom).font(Theme.Police.texte)
                        }
                        .padding(.leading, Theme.Espace.l)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(nomHeros) porte \(h.equipements.map { element($0).nom }.formatted(.list(type: .and)))")
            }
        }
        .padding(Theme.Espace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuilePlanner()
    }

    @ViewBuilder private func image(_ id: Int?, _ taille: CGFloat) -> some View {
        if let id, let image = Illustrations.image(id, niveau: 1) {
            Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: taille, height: taille).accessibilityHidden(true)
        }
    }
}
