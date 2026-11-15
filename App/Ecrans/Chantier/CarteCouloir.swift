import ChantierKit
import SwiftUI

/// Un couloir : l'ouvrier (ou le labo, ou les familiers), ce qu'il fait, ce qui vient ensuite. Toucher la carte déroule
/// toute sa file. Un poste dont le minuteur est passé est « libre depuis… », avec l'amélioration conseillée.
struct CarteCouloir: View {
    let couloir: Couloir
    let plan: PlanAffiche
    let reference: ReferenceData
    /// Les marques « Lancé » appliquées au village (T28).
    var lancees: LocalActionsResult? = nil
    @Binding var ouvert: Bool

    @Environment(ModeleApp.self) private var modele

    @Environment(\.accessibilityReduceMotion) private var reduire
    @Environment(\.dynamicTypeSize) private var tailleTexte
    @ScaledMetric(relativeTo: .body) private var image: CGFloat = 1

    private var titre: String {
        switch couloir.poste {
        case .builder: "Ouvrier \(couloir.numero + 1)"
        case .laboratory: "Labo"
        case .petHouse: "Familiers"
        case .blacksmith: "Forge"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduire ? nil : .snappy) { ouvert.toggle() }
            } label: {
                entete
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(ouvert ? "déroulé" : "replié")
            .accessibilityHint(ouvert ? "Replie la file" : "Déroule la file")

            corps.padding(.top, Theme.Espace.s)
            if ouvert { file }
        }
        .padding(Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)     // la file paresseuse peut être estimée plus haute que son contenu
        .tuileChantier()
    }

    /// Le nom du couloir et la flèche de dépliage.
    private var entete: some View {
        HStack(alignment: .top) {
            // Le nom au-dessus du compte : sur une seule ligne, « OUVRIER 1 » se coupait en pleine syllabe aux grandes tailles.
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(titre).etiquetteChantier()
                if !couloir.file.isEmpty {
                    Text("\(couloir.file.count) à lancer")
                        .font(Theme.Police.detail)
                        .foregroundStyle(Theme.Couleur.texteDoux)
                }
            }
            Spacer(minLength: Theme.Espace.s)
            Image(systemName: "chevron.down")
                .font(Theme.Police.detail.weight(.semibold))
                .foregroundStyle(Theme.Couleur.texteDoux)
                .rotationEffect(.degrees(ouvert ? 180 : 0))
                .accessibilityHidden(true)
        }
    }

    /// En cours : l'amélioration, puis la suivante. Libre : « libre depuis… », puis l'amélioration conseillée.
    @ViewBuilder private var corps: some View {
        if let encours = couloir.enCours {
            enCours(encours)
            if !ouvert, let suivant = couloir.file.first { puis(suivant) }
        } else {
            libre
            if !ouvert, let conseillee = couloir.file.first {
                Filet().padding(.vertical, Theme.Espace.s)
                LigneFile(pas: conseillee, reference: reference, plan: plan, alancer: conseillee.start <= plan.maintenant, taille: 40)
                if conseillee.start <= plan.maintenant { boutonLance(conseillee) }
                if let suivant = couloir.file.dropFirst().first { puis(suivant).padding(.top, Theme.Espace.s) }
            }
        }
    }

    /// L'amélioration en cours. Marquée « Lancé » : un appui long (ou l'action d'accessibilité) retire la marque.
    @ViewBuilder private func enCours(_ pas: ScheduledStep) -> some View {
        if let lancee = lancees?.launch(of: pas.step), pas.fromSnapshot {
            LigneFile(pas: pas, reference: reference, plan: plan, lancee: lancee)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Retirer la marque « Lancé »", systemImage: "arrow.uturn.backward", role: .destructive) {
                        modele.retirerLance(lancee.action)
                    }
                }
                .accessibilityAction(named: "Retirer la marque « Lancé »") { modele.retirerLance(lancee.action) }
                .accessibilityHint("Appui long pour retirer la marque")
        } else {
            LigneFile(pas: pas, reference: reference, plan: plan)
        }
    }

    /// « Lancé » : le joueur dit qu'il vient de la lancer dans le jeu ; l'app démarre le minuteur sans nouvel export.
    private func boutonLance(_ pas: ScheduledStep) -> some View {
        Button {
            withAnimation(reduire ? nil : .snappy) { modele.marquerLance(pas, couloir: couloir.numero) }
        } label: {
            Label("Lancé", systemImage: "hammer.fill").font(Theme.Police.chiffre)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Theme.Couleur.action)
        .foregroundStyle(Theme.Couleur.surBois)
        .sensoryFeedback(.success, trigger: lancees?.applied.count ?? 0)
        .padding(.top, Theme.Espace.s)
        .accessibilityHint("Dit à l'app que tu l'as lancée dans le jeu")
    }

    private func puis(_ pas: ScheduledStep) -> some View {
        let nom = reference.item(pas.step.itemID)?.name ?? "#\(pas.step.itemID)"
        return Text("puis \(nom) \(pas.step.level - 1) → \(pas.step.level)")
            .font(Theme.Police.detail)
            .foregroundStyle(Theme.Couleur.texteDoux)
            .padding(.top, Theme.Espace.xs)
            .accessibilityLabel("puis \(nom), du niveau \(pas.step.level - 1) au niveau \(pas.step.level)")
    }

    /// Le poste est libre : depuis quand si la photo le dit, et ce qui vient de finir.
    private var libre: some View {
        let disposition = tailleTexte.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Espace.s))
                                                          : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Espace.m))
        return disposition {
            Illustration(id: couloir.fini?.step.itemID ?? couloir.emblem,
                         niveau: couloir.fini?.step.level ?? couloir.niveauEmblem,
                         maximum: couloir.fini?.step.element.maxLevel,
                         taille: min(44 * max(image, 1), 70), avecPastille: couloir.fini != nil, lieu: "chantier")
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(couloir.fini.map { "Libre depuis " + Lisible.depuis($0.end, now: plan.maintenant, timeZone: plan.fuseau) } ?? "Libre")
                    .font(Theme.Police.texte.weight(.semibold))
                    .foregroundStyle(Theme.Couleur.elixirTexte)
                if let fini = couloir.fini {
                    let nom = reference.item(fini.step.itemID)?.name ?? "#\(fini.step.itemID)"
                    Text("\(nom) \(fini.step.level) est fini")
                        .font(Theme.Police.detail)
                        .foregroundStyle(Theme.Couleur.texteDoux)
                } else if couloir.file.isEmpty {
                    Text("Rien à lancer").font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Toute la file, dans l'ordre. Paresseuse : une file d'ouvrier compte des centaines de lignes.
    private var file: some View {
        VStack(alignment: .leading, spacing: 0) {
            Filet().padding(.vertical, Theme.Espace.m)
            Text("File d'attente").etiquetteChantier().padding(.bottom, Theme.Espace.s)
            if couloir.file.isEmpty {
                Text("Rien d'autre à lancer.").font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(couloir.file.enumerated()), id: \.offset) { i, pas in
                    LigneFile(pas: pas, reference: reference, plan: plan, alancer: i == 0 && couloir.estLibre && pas.start <= plan.maintenant,
                              taille: 40)
                        .padding(.vertical, Theme.Espace.s)
                    if i == 0 && couloir.estLibre && pas.start <= plan.maintenant { boutonLance(pas).padding(.bottom, Theme.Espace.s) }
                    if i < couloir.file.count - 1 { Filet() }
                }
            }
        }
    }
}
