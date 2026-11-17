import VillagePlannerKit
import SwiftUI

/// Les Réglages (PLAN §3.4) : le profil de jeu et les réductions en cours. Chaque changement est enregistré
/// et le plan se recalcule aussitôt (T17).
struct EcranReglages: View {
    let reference: ReferenceData
    @Environment(ModeleApp.self) private var modele
    @Environment(\.dismiss) private var fermer
    @State private var chemin: [String] = Self.cheminDeCapture()

    /// Débogage seulement : `-apropos 1` ouvre « À propos » au lancement (captures).
    private static func cheminDeCapture() -> [String] {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "apropos") ? ["apropos"] : UserDefaults.standard.bool(forKey: "joueur") ? ["joueur"] : []
        #else
        return []
        #endif
    }

    var body: some View {
        @Bindable var modele = modele
        NavigationStack(path: $chemin) {
            ScrollViewReader { proxy in
            Form {
                orientation($modele.profil)
                heros($modele.profil)
                heuresSansJeu($modele.profil)
                Section {
                    ReductionEditeur(titre: "Ouvriers", reduction: $modele.profil.builderReduction, maintenant: modele.maintenant)
                    ReductionEditeur(titre: "Laboratoire", reduction: $modele.profil.laboratoryReduction, maintenant: modele.maintenant)
                } header: { entete("Réductions en cours") } footer: {
                    note("Événement ou Pass Or : un pourcentage sur le coût et la durée, jusqu'à sa date de fin. L'export ne dit pas si une réduction est active.")
                }
                .id("reductions")
                seuil($modele.profil)
                epingles($modele.profil).id("epingles")
                SectionNotifications().id("notifications")
                SectionConseiller().id("conseiller")
                SectionCompteDeJeu().id("compte")
                Section {
                    NavigationLink("À propos", value: "apropos").listRowBackground(Theme.Couleur.surface)
                }
            }
            #if DEBUG
            .task { if let ancre = UserDefaults.standard.string(forKey: "reglages-defile") { proxy.scrollTo(ancre, anchor: .top) } }   // captures
            #endif
            .font(Theme.Police.texte)
            .scrollContentBackground(.hidden)
            .pagePlanner()
            .navigationDestination(for: String.self) { page in
                if page == "joueur" { EcranJoueur() } else { EcranAPropos() }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { fermer() } } }
            }
        }
    }

    private func entete(_ texte: String) -> some View { Text(texte).etiquettePlanner() }
    private func note(_ texte: String) -> some View { Text(texte).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux) }

    private func orientation(_ profil: Binding<Profile>) -> some View {
        Section {
            Picker("Orientation", selection: profil.orientation) {
                Text("Équilibré").tag(Orientation.balanced)
                Text("Attaque").tag(Orientation.attack)
                Text("Défense").tag(Orientation.defense)
            }
        } header: { entete("Profil de jeu") } footer: {
            note("Attaque : les héros passent avant les bâtiments qui débloquent. Défense : les défenses passent avant les héros.")
        }
        .listRowBackground(Theme.Couleur.surface)
    }

    private func heros(_ profil: Binding<Profile>) -> some View {
        Section {
            Picker("Héros en amélioration", selection: profil.heroLimit) {
                Text("Sans limite").tag(Int?.none)
                ForEach(1...5, id: \.self) { n in Text("\(n) à la fois").tag(Int?.some(n)) }
            }
        } footer: { note("Le nombre de héros que tu acceptes d'avoir en amélioration en même temps.") }
        .listRowBackground(Theme.Couleur.surface)
    }

    private func heuresSansJeu(_ profil: Binding<Profile>) -> some View {
        let actives = Binding(get: { profil.wrappedValue.quietHours != nil },
                              set: { profil.wrappedValue.quietHours = $0 ? .default : nil })
        return Section {
            Toggle("Heures sans jeu", isOn: actives)
            if let heures = profil.quietHours.wrappedValue {
                Picker("De", selection: Binding(get: { heures.start }, set: { profil.wrappedValue.quietHours?.start = $0 })) {
                    ForEach(0..<24, id: \.self) { Text("\($0)\u{00A0}h").tag($0) }
                }
                Picker("À", selection: Binding(get: { heures.end }, set: { profil.wrappedValue.quietHours?.end = $0 })) {
                    ForEach(0..<24, id: \.self) { Text("\($0)\u{00A0}h").tag($0) }
                }
            }
        } footer: { note("Le plan ne lance rien pendant ces heures, à l'heure de ton appareil.") }
        .listRowBackground(Theme.Couleur.surface)
    }

    private func seuil(_ profil: Binding<Profile>) -> some View {
        Section {
            Picker("Passer à l'HDV suivant", selection: profil.nextTownHallThreshold) {
                Text("Tout est terminé").tag(TownHallThreshold.complete)
                Text("Héros et labo terminés").tag(TownHallThreshold.heroesAndLab)
            }
            .pickerStyle(.inline)      // les deux choix en toutes lettres : le menu coupait « Tout est terminé » en très grande police
        } footer: { note("Monter tôt est une stratégie défendue par une partie des joueurs : à toi de choisir quand l'app le conseille.") }
        .listRowBackground(Theme.Couleur.surface)
    }

    private func epingles(_ profil: Binding<Profile>) -> some View {
        let noms = profil.wrappedValue.pinned.map { ($0, reference.item($0)?.name ?? "#\($0)") }.sorted { $0.1 < $1.1 }
        return Section {
            if noms.isEmpty {
                Text("Aucune épingle").foregroundStyle(Theme.Couleur.texteDoux)
            }
            ForEach(noms, id: \.0) { id, nom in
                HStack {
                    Label(nom, systemImage: "pin.fill")
                    Spacer()
                    Button { profil.wrappedValue.pinned.remove(id) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Couleur.texteDoux)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retirer l'épingle de \(nom)")
                }
            }
        } header: { entete("Épingles") } footer: {
            note("Un élément épinglé passe en tête de son poste. Pour en ajouter : écran Village, une catégorie, puis l'épingle d'un élément.")
        }
        .listRowBackground(Theme.Couleur.surface)
    }
}

/// Une réduction : activée, son pourcentage et sa date de fin ; dite finie quand la date est passée.
private struct ReductionEditeur: View {
    let titre: String
    @Binding var reduction: Reduction?
    let maintenant: Date

    var body: some View {
        let active = Binding(get: { reduction != nil },
                             set: { reduction = $0 ? Reduction(percent: 20, endsAt: maintenant.addingTimeInterval(7 * 86400)) : nil })
        Toggle(titre, isOn: active)
        if let r = reduction {
            Stepper(value: Binding(get: { r.percent }, set: { reduction = Reduction(percent: $0, endsAt: r.endsAt) }),
                    in: 5...90, step: 5) {
                Text("Réduction de \(r.percent)\u{00A0}%")
            }
            DatePicker("Fin", selection: Binding(get: { r.endsAt }, set: { reduction = Reduction(percent: r.percent, endsAt: $0) }),
                       displayedComponents: [.date, .hourAndMinute])
            if r.endsAt <= maintenant {
                Label("Terminée : elle ne s'applique plus au plan.", systemImage: "clock.badge.exclamationmark")
                    .font(Theme.Police.detail.weight(.semibold))
                    .foregroundStyle(Theme.Couleur.action)
            }
        }
    }
}
