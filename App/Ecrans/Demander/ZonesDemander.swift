import VillagePlannerKit
import SwiftUI

/// Une zone de saisie : un champ, et un bouton qui envoie.
private struct ChampEnvoi: View {
    let titre: String
    @Binding var texte: String
    let actif: Bool
    let envoyer: () -> Void
    @Environment(\.dynamicTypeSize) private var tailleTexte

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            TextField(titre, text: $texte, axis: .vertical)
                .font(Theme.Police.texte)
                .lineLimit(1...(tailleTexte.isAccessibilitySize ? 12 : 4))      // 400 caractères en très grande police : le texte saisi ne se coupe pas
                .padding(Theme.Espace.m)
                .background(Theme.Couleur.creux, in: .rect(cornerRadius: Theme.rayon))
                .submitLabel(.send)
                .onSubmit(envoyer)
            Button(action: envoyer) {
                if actif { ProgressView().frame(maxWidth: .infinity) } else { Text("Envoyer").frame(maxWidth: .infinity) }
            }
            .font(Theme.Police.texte.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(Theme.Couleur.action)
            .foregroundStyle(.white)
            .disabled(actif || texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(minHeight: 44)
        }
    }
}

/// Le profil en une phrase : l'app montre le profil obtenu, avec les différences, avant de l'appliquer.
struct ZoneProfilPhrase: View {
    @Bindable var modele: ModeleDemander
    let envoyer: () -> Void
    let appliquer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Décrire ton style de jeu").etiquettePlanner()
            Text("Écris une phrase, par exemple « attaque aérienne, un seul héros à la fois, je ne joue pas de 22 h à 6 h ». Rien n'est changé avant ta confirmation.")
                .font(Theme.Police.detail)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
            ChampEnvoi(titre: "Ma phrase", texte: $modele.phrase, actif: modele.profilEnCours, envoyer: envoyer)
            if let p = modele.propose { proposition(p) }
            if let m = modele.messageProfil {
                Text(m).font(Theme.Police.texte).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuilePlanner()
    }

    private func proposition(_ p: ProfilPropose) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            Text("Profil obtenu").font(Theme.Police.surtitre)
            ForEach(p.differences, id: \.self) { ligne in
                Text(ligne).font(Theme.Police.texte).fixedSize(horizontal: false, vertical: true)
            }
            Text("Les autres réglages ne bougent pas. Calculé par l'app à partir de ta phrase.")
                .font(Theme.Police.detail)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Espace.m) {
                Button("Annuler", role: .cancel) { modele.annulerProfil() }
                    .buttonStyle(.bordered)
                    .tint(Theme.Couleur.texteDoux)
                Button("Appliquer", action: appliquer)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Couleur.action)
                    .foregroundStyle(.white)
            }
            .font(Theme.Police.texte.weight(.semibold))
            .frame(minHeight: 44)
        }
        .padding(Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Couleur.surface, in: .rect(cornerRadius: Theme.rayon))
        .overlay(RoundedRectangle(cornerRadius: Theme.rayon).stroke(Theme.Couleur.contour, lineWidth: Theme.bord))
    }
}

/// Les questions sur le plan : une variante est recalculée par l'app, qui compose la comparaison.
struct ZoneQuestions: View {
    @Bindable var modele: ModeleDemander
    let envoyer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Poser une question").etiquettePlanner()
            Text("Par exemple « et avec un ouvrier de plus ? », « et si je priorise la défense ? », « et sans assistants ? ». Les dates viennent du calcul de l'app, la conversation s'efface à la fermeture.")
                .font(Theme.Police.detail)
                .foregroundStyle(Theme.Couleur.texteDoux)
                .fixedSize(horizontal: false, vertical: true)
            ChampEnvoi(titre: "Ma question", texte: $modele.question, actif: modele.questionEnCours, envoyer: envoyer)
            ForEach(modele.echanges.reversed()) { echange($0) }
        }
        .padding(Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tuilePlanner()
    }

    private func echange(_ e: EchangeQuestion) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            Text(e.question).font(Theme.Police.texte.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let c = e.comparaison {
                Text("Variante : \(c.variante.libelle)").font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                ForEach(c.lignes, id: \.self) { Text($0).font(Theme.Police.texte).fixedSize(horizontal: false, vertical: true) }
            }
            if let phrase = e.phrase {
                if !e.horsListe { Text("Explication générale").font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux) }
                Text(phrase.prefix(1).uppercased() + phrase.dropFirst() + ".")
                    .font(Theme.Police.texte)
                    .fixedSize(horizontal: false, vertical: true)
                if e.horsListe {
                    Text("D'après ton plan actuel, sans nouveau calcul.").font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
                }
            }
            if e.sansReponse {
                Text(e.erreur.map(ModeleDemander.message) ?? Questions.messageSansReponse)
                    .font(Theme.Police.texte)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Couleur.surface, in: .rect(cornerRadius: Theme.rayon))
        .overlay(RoundedRectangle(cornerRadius: Theme.rayon).stroke(Theme.Couleur.contour, lineWidth: Theme.bord))
        .accessibilityElement(children: .combine)
    }
}
