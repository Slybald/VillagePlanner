import VillagePlannerKit
import SwiftUI
import WidgetKit

private func postesLibres(_ n: Int) -> String { n == 1 ? "poste libre" : "postes libres" }

/// Ce que dit un widget quand il n'y a pas de couloirs à montrer.
private struct MessagePlanner: View {
    let symbole: String
    let titre: String
    let detail: String
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 6) {
            Image(systemName: symbole).font(.system(size: compact ? 20 : 26, weight: .bold)).foregroundStyle(Teinte.elixirTexte)
            Text(titre).font(Teinte.titre(compact ? 17 : 20)).foregroundStyle(Teinte.texte).multilineTextAlignment(.center)
            Text(detail).font(Teinte.texte(compact ? 12 : 13)).foregroundStyle(Teinte.texteDoux)
                .multilineTextAlignment(.center).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Petit

/// Le petit : le nombre de postes libres ; sinon le prochain qui se libère, avec son image et son compte à rebours.
struct VuePetit: View {
    let entree: EntreePlanner

    var body: some View {
        switch entree.contenu {
        case .ouvrirApp:
            MessagePlanner(symbole: "hammer", titre: "Ouvre Village Planner", detail: "Colle un export pour voir tes postes.", compact: true)
        case .photoARefaire:
            MessagePlanner(symbole: "camera", titre: "Photo à refaire", detail: "Tous les minuteurs sont finis.", compact: true)
        case .postes(let lignes):
            let libres = lignes.libres
            if !libres.isEmpty {
                libresEtProchain(libres: libres, prochain: lignes.prochain)
            } else if let prochain = lignes.prochain, let travail = prochain.travail {
                prochainSeul(prochain, travail)
            } else {
                MessagePlanner(symbole: "hammer", titre: "Aucun poste", detail: "La photo n'en montre pas.", compact: true)
            }
        }
    }

    private func libresEtProchain(libres: [WidgetLigne], prochain: WidgetLigne?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("OUVRIERS").font(Teinte.titre(12)).tracking(1).foregroundStyle(Teinte.texteDoux)
            Spacer(minLength: 0)
            Text("\(libres.count)").font(Teinte.titre(54)).foregroundStyle(Teinte.elixirTexte).minimumScaleFactor(0.7)
            Text(postesLibres(libres.count)).font(Teinte.texte(16)).foregroundStyle(Teinte.texte)
            if let prochain, let travail = prochain.travail {
                Text("Prochain dans").font(Teinte.texte(11)).foregroundStyle(Teinte.texteDoux).padding(.top, 4)
                CompteARebours(fin: travail.fin, depuis: entree.date)
                    .font(Teinte.titre(15).monospacedDigit()).foregroundStyle(Teinte.texte)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func prochainSeul(_ ligne: WidgetLigne, _ travail: WidgetEtat.Travail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text("PROCHAIN POSTE LIBRE").font(Teinte.titre(11)).tracking(0.5).foregroundStyle(Teinte.texteDoux)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                ImagePlanner(nom: ligne.image, racine: entree.racine, cote: 34)
            }
            Spacer(minLength: 0)
            CompteARebours(fin: travail.fin, depuis: entree.date)
                .font(Teinte.titre(30).monospacedDigit()).foregroundStyle(Teinte.elixirTexte).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ligne.titre).font(Teinte.texte(15)).foregroundStyle(Teinte.texte)
            Text("\(travail.nom) \(travail.niveau)").font(Teinte.texte(12)).foregroundStyle(Teinte.texteDoux).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Moyen

/// Le moyen : les couloirs en tuiles, l'image de l'élément en cours et son compte à rebours.
struct VueMoyenne: View {
    let entree: EntreePlanner

    var body: some View {
        switch entree.contenu {
        case .ouvrirApp:
            MessagePlanner(symbole: "hammer", titre: "Ouvre Village Planner", detail: "Colle un export de ton village pour voir tes ouvriers, ton labo et tes familiers.")
        case .photoARefaire:
            MessagePlanner(symbole: "camera", titre: "Photo à refaire", detail: "Tous les minuteurs de ta dernière photo sont finis. Colle un nouvel export.")
        case .postes(let lignes):
            let colonnes = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
            LazyVGrid(columns: colonnes, spacing: 6) {
                ForEach(Array(lignes.prefix(8).enumerated()), id: \.offset) { _, ligne in
                    tuile(ligne)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func tuile(_ ligne: WidgetLigne) -> some View {
        HStack(spacing: 6) {
            ImagePlanner(nom: ligne.image, racine: entree.racine, cote: 28)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(ligne.titre).font(Teinte.texte(11)).foregroundStyle(Teinte.texteDoux).lineLimit(1)
                if let travail = ligne.travail {
                    CompteARebours(fin: travail.fin, depuis: entree.date)
                        .font(Teinte.titre(14).monospacedDigit()).foregroundStyle(Teinte.texte).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Libre").font(Teinte.titre(14)).foregroundStyle(Teinte.elixirTexte)
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(Teinte.surface, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Teinte.trait, lineWidth: 1.5) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Écran verrouillé

/// L'écran verrouillé : le compte à rebours du prochain poste, ou le nombre de postes libres.
struct VueVerrou: View {
    @Environment(\.widgetFamily) private var famille
    let entree: EntreePlanner

    var body: some View {
        switch famille {
        case .accessoryInline: inline
        default: rectangle
        }
    }

    @ViewBuilder private var inline: some View {
        switch entree.contenu {
        case .ouvrirApp: Text("Ouvre Village Planner")
        case .photoARefaire: Text("Photo à refaire")
        case .postes(let lignes):
            if !lignes.libres.isEmpty {
                Text("\(lignes.libres.count) \(postesLibres(lignes.libres.count))")
            } else if let travail = lignes.prochain?.travail {
                Text("Libre dans \(Text(timerInterval: entree.date...travail.fin, pauseTime: travail.fin, countsDown: true, showsHours: true))")
            } else {
                Text("Aucun poste")
            }
        }
    }

    @ViewBuilder private var rectangle: some View {
        switch entree.contenu {
        case .ouvrirApp:
            texte("Village Planner", "Ouvre l'app pour ajouter une photo.")
        case .photoARefaire:
            texte("Photo à refaire", "Les minuteurs sont finis.")
        case .postes(let lignes):
            let libres = lignes.libres
            VStack(alignment: .leading, spacing: 1) {
                Text(libres.isEmpty ? "Prochain poste libre" : "\(libres.count) \(postesLibres(libres.count))")
                    .font(.headline).widgetAccentable()
                if let prochain = lignes.prochain, let travail = prochain.travail {
                    CompteARebours(fin: travail.fin, depuis: entree.date)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(libres.isEmpty ? "\(prochain.titre) · \(travail.nom) \(travail.niveau)" : "Prochain : \(prochain.titre)")
                        .font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func texte(_ titre: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titre).font(.headline).widgetAccentable()
            Text(detail).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Aperçus (Xcode)

#Preview("Petit", as: .systemSmall) { WidgetPetit() } timeline: {
    EntreePlanner(date: .now, contenu: .postes(Exemple.lignes(depuis: .now)), racine: nil)
    EntreePlanner(date: .now, contenu: .photoARefaire, racine: nil)
}

#Preview("Moyen", as: .systemMedium) { WidgetMoyen() } timeline: {
    EntreePlanner(date: .now, contenu: .postes(Exemple.lignes(depuis: .now)), racine: nil)
}

#Preview("Verrou", as: .accessoryRectangular) { WidgetVerrou() } timeline: {
    EntreePlanner(date: .now, contenu: .postes(Exemple.lignes(depuis: .now)), racine: nil)
}
