import ChantierKit
import SwiftUI

/// La section « Conseiller » des Réglages (T19) : la clé d'API, collée une fois puis rangée dans le Trousseau, jamais
/// réaffichée en clair ; un bouton pour la vérifier, un pour l'effacer ; les appels du jour et la dépense du mois.
struct SectionConseiller: View {
    private let cles: any SecretStore
    private let budgetStore: BudgetStore
    @State private var masque: String?
    @State private var saisie = ""
    @State private var budget = Budget()
    @State private var message: String?
    @State private var enCours = false

    init() { (cles, budgetStore) = Self.coffres() }

    /// Le Trousseau et les préférences ; en débogage, `-conseiller-exemple sans-cle|avec-cle` prend un coffre en mémoire
    /// (une fausse clé, jamais une vraie) et un budget d'exemple, sans rien toucher aux vrais.
    private static func coffres() -> (any SecretStore, BudgetStore) {
        #if DEBUG
        if let exemple = UserDefaults.standard.string(forKey: "conseiller-exemple") {
            let nom = "chantier-conseiller-capture"
            UserDefaults.standard.removePersistentDomain(forName: nom)
            let store = BudgetStore(defaults: UserDefaults(suiteName: nom) ?? .standard)
            if exemple == "avec-cle" {
                var b = Budget()
                for _ in 0..<4 { b.recordCall(at: Date(), calendar: .current) }
                b.recordCost(46_300_000, at: Date(), calendar: .current)
                store.save(b)
            }
            return (MemorySecretStore(exemple == "avec-cle" ? "factice-capture-0000-0000-0000-4F2A" : nil), store)
        }
        #endif
        return (KeychainStore(), BudgetStore())
    }

    var body: some View {
        Section {
            if let masque {
                LabeledContent("Clé d'API") {
                    Text(masque).font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux)
                        .accessibilityLabel("Enregistrée, masquée")
                }
                Button(action: verifier) {
                    HStack {
                        Text("Vérifier la clé")
                        if enCours { Spacer(); ProgressView() }
                    }
                }
                .foregroundStyle(Theme.Couleur.elixirTexte)
                .disabled(enCours)
                Button("Effacer la clé", role: .destructive, action: effacer)
                    .foregroundStyle(Theme.Couleur.action)
            } else {
                SecureField("Colle ta clé d'API", text: $saisie)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(enregistrer)
                let valide = APIKey.normalized(saisie) != nil
                Button("Enregistrer dans le Trousseau", action: enregistrer)
                    .foregroundStyle(valide ? Theme.Couleur.elixirTexte : Theme.Couleur.texteDoux)
                    .disabled(!valide)
            }
            if let message {
                Text(message).font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texte)
            }
            depense
            LabeledContent("Aujourd'hui") {
                Text("\(budget.callsToday) appel\(budget.callsToday > 1 ? "s" : "") sur \(Budget.callsPerDay)")
                    .font(Theme.Police.chiffreDetail)
            }
        } header: { Text("Conseiller").etiquetteChantier() } footer: {
            Text("La clé reste dans le Trousseau de cet iPhone, sans synchronisation iCloud. Plafonds : \(Budget.callsPerDay) appels par jour et 1\u{00A0}$ par mois ; au-delà, l'app garde la consigne du moteur. Conseil : une clé dédiée à l'app, avec une limite de dépense dans la Console Anthropic.")
                .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
        }
        .listRowBackground(Theme.Couleur.surface)
        .onAppear(perform: relire)
    }

    private var depense: some View {
        let limite = Double(Budget.monthlyLimit) / 1e9
        return VStack(alignment: .leading, spacing: Theme.Espace.s) {
            LabeledContent("Dépense du mois") {
                Text("\(budget.spentDollars.formatted(.number.precision(.fractionLength(2...3)))) $ sur \(limite.formatted()) $")
                    .font(Theme.Police.chiffreDetail)
            }
            Jauge(valeur: budget.spentDollars / limite, taille: .fine).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Gestes

    private func relire() {
        masque = (try? cles.read()).flatMap { $0 }.map(APIKey.masked)
        budget = budgetStore.load().at(Date(), calendar: .current)
    }

    private func enregistrer() {
        do {
            try cles.save(saisie)
            message = "Clé enregistrée dans le Trousseau."
        } catch {
            message = error == .invalidKey ? "Ce texte n'est pas une clé d'API." : "Le Trousseau a refusé la clé. Réessaie."
        }
        saisie = ""                                          // la clé ne reste pas dans le champ
        relire()
    }

    private func effacer() {
        do {
            try cles.delete()
            message = "Clé effacée."
        } catch { message = "Le Trousseau n'a pas pu effacer la clé. Réessaie." }
        relire()
    }

    private func verifier() {
        enCours = true
        message = nil
        let client = ClaudeClient(keys: cles, budget: budgetStore, calendar: .current)
        Task {
            do throws(ClaudeError) {
                try await client.checkKey(now: Date())
                message = "Clé acceptée : le conseiller est prêt."
            } catch { message = Self.texte(error) }
            enCours = false
            relire()
        }
    }

    /// Ce qui s'est passé et quoi faire. La consigne du moteur reste affichée partout ailleurs.
    static func texte(_ erreur: ClaudeError) -> String {
        switch erreur {
        case .noKey: "Aucune clé enregistrée."
        case .keychainUnavailable: "Le Trousseau ne répond pas. Déverrouille l'iPhone et réessaie."
        case .unauthorized: "Clé refusée par Anthropic. Vérifie-la dans la Console, ou colle une nouvelle clé."
        case .rateLimited: "Trop de requêtes. Réessaie dans une minute."
        case .serviceUnavailable(let statut): "Le service d'Anthropic ne répond pas (erreur \(statut)). Réessaie plus tard."
        case .rejected(let statut): "Requête refusée (erreur \(statut)). Vérifie les droits de la clé dans la Console."
        case .offline: "Pas de réseau. Réessaie une fois connecté."
        case .timeout: "Pas de réponse en 20 secondes. Réessaie plus tard."
        case .invalidResponse: "Réponse illisible. Réessaie plus tard."
        case .refusal: "Le modèle a décliné la demande."
        case .budgetReached(.daily): "Plafond du jour atteint (\(Budget.callsPerDay) appels). Il revient demain."
        case .budgetReached(.monthly): "Plafond du mois atteint (1\u{00A0}$). Il revient le mois prochain."
        }
    }
}
