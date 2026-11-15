import ChantierKit
import SwiftUI

/// La section « Compte de jeu » des Réglages (T29) : la clé de l'API officielle, collée une fois puis rangée dans le Trousseau
/// (autre compte que celle du conseiller), jamais réaffichée en clair ; le tag vient de la dernière photo. Facultatif :
/// sans clé, rien ne change dans l'app. Une lecture par ouverture de l'app et une par heure au plus.
struct SectionCompteDeJeu: View {
    @Environment(ModeleApp.self) private var modele
    private let outils = Outils.partages
    @State private var etatCle = KeyState.absent
    @State private var saisie = ""
    @State private var message: String?
    @State private var enCours = false
    @State private var derniereLecture: Date?
    @State private var tagLu: String?

    /// Ce qui vit autant que le processus : le client (qui retient qu'une lecture est déjà partie depuis l'ouverture), le coffre et la cadence.
    struct Outils: Sendable {
        let cles: any SecretStore
        let cadence: CadenceStore
        let client: ClientJoueur
        /// En débogage seulement : un tag factice, sans photo.
        var tagExemple: String?
        var exemple: String?

        static let partages = Outils.creer()

        /// Le Trousseau et les préférences ; en débogage, `-joueur-exemple sans-cle|avec-cle|erreur` prend un coffre en mémoire
        /// (une fausse clé, jamais une vraie), le tag factice `#2PP` et un faux service (403 pour `erreur`), sans rien toucher aux vrais.
        private static func creer() -> Outils {
            #if DEBUG
            if let exemple = UserDefaults.standard.string(forKey: "joueur-exemple") {
                let nom = "chantier-joueur-capture"
                UserDefaults.standard.removePersistentDomain(forName: nom)
                let cadence = CadenceStore(defaults: UserDefaults(suiteName: nom) ?? .standard)
                let cles = MemorySecretStore(exemple == "sans-cle" ? nil : "factice-capture-0000-0000-0000-7C1D")
                let client = ClientJoueur(keys: cles, cadence: cadence, transport: ServiceExemple(statut: 403))
                return Outils(cles: cles, cadence: cadence, client: client, tagExemple: "#2PP", exemple: exemple)
            }
            #endif
            let cles = KeychainStoreJoueur()
            let cadence = CadenceStore()
            return Outils(cles: cles, cadence: cadence, client: ClientJoueur(keys: cles, cadence: cadence), tagExemple: nil, exemple: nil)
        }
    }

    #if DEBUG
    /// Le faux service des captures : il refuse toujours la clé.
    private struct ServiceExemple: HTTPTransport {
        let statut: Int
        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            (Data(#"{"reason":"accessDenied.invalidIp"}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: statut, httpVersion: nil, headerFields: nil)!)
        }
    }
    #endif

    private var tag: String? { outils.tagExemple ?? tagLu }

    var body: some View {
        Section {
            NavigationLink("Mon profil de joueur", value: "joueur")
            LabeledContent("Joueur") {
                Text(tag ?? "Pas encore de photo").font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux)
            }
            switch etatCle {
            case .present(let masque):
                LabeledContent("Clé d'API") {
                    Text(masque).font(Theme.Police.chiffreDetail).foregroundStyle(Theme.Couleur.texteDoux)
                        .accessibilityLabel("Enregistrée, masquée")
                }
                Button(action: lire) {
                    HStack {
                        Text("Lire mon profil")
                        if enCours { Spacer(); ProgressView() }
                    }
                }
                .foregroundStyle(Theme.Couleur.elixirTexte)
                .disabled(enCours)
                Button("Effacer la clé", role: .destructive, action: effacer)
                    .foregroundStyle(Theme.Couleur.action)
            case .unavailable:
                Label("Le Trousseau ne répond pas. Déverrouille l'iPhone, puis rouvre les Réglages.", systemImage: "lock.fill")
                    .font(Theme.Police.detail)
            case .absent:
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
            if let derniereLecture {
                LabeledContent("Dernière lecture") {
                    Text(derniereLecture, format: .dateTime.day().month().hour().minute()).font(Theme.Police.chiffreDetail)
                }
            }
        } header: { Text("Compte de jeu").etiquetteChantier() } footer: {
            Text("Facultatif : les statistiques de joueur (trophées, étoiles de guerre, dons) viennent de l'API officielle, par le relais cocproxy.royaleapi.dev. Crée une clé dédiée à l'app (marche à suivre dans docs/cle-api-supercell.md) : quiconque la connaît peut s'en servir à travers ce relais. Elle reste dans le Trousseau de cet iPhone ; seul ton tag part avec elle. Une lecture par ouverture de l'app et une par heure au plus.")
                .font(Theme.Police.detail).foregroundStyle(Theme.Couleur.texteDoux)
        }
        .listRowBackground(Theme.Couleur.surface)
        .onAppear(perform: relire)
        .task {
            #if DEBUG
            if outils.exemple == "erreur", message == nil { await lireSansBouton() }    // capture de l'état d'erreur
            #endif
        }
    }

    // MARK: Gestes

    private func relire() {
        etatCle = APIKey.state(of: outils.cles)
        derniereLecture = outils.cadence.load().dernierAppel
        tagLu = modele.tagJoueur                             // lu une fois, pas à chaque frappe
    }

    private func enregistrer() {
        do {
            try outils.cles.save(saisie)
            message = "Clé enregistrée dans le Trousseau."
        } catch {
            message = error == .invalidKey ? "Ce texte n'est pas une clé d'API." : "Le Trousseau a refusé la clé. Réessaie."
        }
        saisie = ""                                          // la clé ne reste pas dans le champ
        relire()
    }

    private func effacer() {
        do {
            try outils.cles.delete()
            message = "Clé effacée."
        } catch { message = "Le Trousseau n'a pas pu effacer la clé. Réessaie." }
        relire()
    }

    private func lire() {
        Task { await lireSansBouton() }
    }

    private func lireSansBouton() async {
        enCours = true
        message = nil
        do throws(JoueurError) {
            let profil = try await modele.lireProfil(avec: outils.client, tag: tag)
            message = Self.resume(profil)
        } catch { message = Self.texte(error) }
        enCours = false
        relire()
    }

    static func resume(_ profil: ProfilJoueur) -> String {
        let trophees = profil.trophies.map { "\($0.formatted()) trophées" } ?? "profil lu"
        return "Lu : \(profil.name ?? "joueur"), \(trophees)."
    }

    /// Ce qui s'est passé et quoi faire.
    static func texte(_ erreur: JoueurError) -> String {
        switch erreur {
        case .noKey: "Aucune clé enregistrée."
        case .keychainUnavailable: "Le Trousseau ne répond pas. Déverrouille l'iPhone et réessaie."
        case .noTag: "Importe d'abord un export du village : le tag du joueur vient de la dernière photo."
        case .invalidTag: "Le tag de la dernière photo n'a pas la forme d'un tag de joueur."
        case .tooSoon(.thisLaunch): "Une lecture a déjà eu lieu depuis l'ouverture de l'app. Ferme-la puis rouvre-la."
        case .tooSoon(.hourly(let jusqua)): "Pas plus d'une lecture par heure : la prochaine est possible à \(jusqua.formatted(date: .omitted, time: .shortened))."
        case .rejectedKey: "Clé refusée. Vérifie qu'elle déclare l'adresse IP du relais, ou colle une nouvelle clé."
        case .notFound: "Aucun joueur avec ce tag. Importe un export récent."
        case .rateLimited: "Trop de requêtes. Réessaie plus tard."
        case .maintenance: "Le jeu est en maintenance. Réessaie plus tard."
        case .serverError(let statut): "Le relais ou l'API ne répond pas (erreur \(statut)). Réessaie plus tard."
        case .rejected(let statut): "Requête refusée (erreur \(statut))."
        case .offline: "Pas de réseau. Réessaie une fois connecté."
        case .timeout: "Pas de réponse en 20 secondes. Réessaie plus tard."
        case .invalidResponse: "Réponse illisible. Réessaie plus tard."
        }
    }
}
