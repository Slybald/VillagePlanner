import ChantierKit
import Foundation
import Observation
import UIKit

/// Ce que les écrans montrent : un village calculé, et d'où il vient.
struct VillageAffiche {
    let village: Village
    let rapport: ProgressReport
    /// nil pour le village d'exemple, qui n'est jamais enregistré.
    let photo: Snapshot?
    var estExemple: Bool { photo == nil }
}

/// Un message au-dessus de l'écran : ce qui s'est passé, ce que l'app a gardé, quoi faire.
struct Retour: Equatable {
    let titre: String
    let detail: String
    let estErreur: Bool
}

enum OngletApp: String, Hashable {
    case cap, chantier, village
}

/// L'état de l'app : la dernière photo, l'exemple, le presse-papiers. Seul endroit qui touche au presse-papiers.
@MainActor @Observable
final class ModeleApp {
    let reference: ReferenceData?
    private(set) var affiche: VillageAffiche?
    private(set) var retour: Retour?
    /// Le presse-papiers contient du texte qu'on n'a pas encore traité (test silencieux, sans lecture).
    private(set) var presseTexteAColler = false
    var onglet: OngletApp = .cap

    private let store: SnapshotStore
    /// Les réglages de l'app (l'exemple est-il actif). En mode `-importer-fichier`, un jeu isolé : les vrais restent intacts.
    private let reglages: UserDefaults
    /// `changeCount` du presse-papiers au dernier collage : tant qu'il ne bouge pas, on ne reproposera pas le même texte.
    private var presseTraite: Int?
    private static let cleExemple = "exempleActif"

    init() {
        reference = try? ReferenceData.load()
        let arguments = UserDefaults.standard      // arguments de lancement (-ecran, -exemple…)
        var reglages = UserDefaults.standard
        var dossier = URL.applicationSupportDirectory.appending(path: "Photos")
        var fichiersDebug: [String] = []
        #if DEBUG
        // Débogage seulement : le fichier est importé dans un dossier neuf, sans trace entre deux lancements.
        // Plusieurs chemins séparés par « : » sont importés dans l'ordre (pour montrer un import refusé après un bon).
        if let chemin = arguments.string(forKey: "importer-fichier") {
            dossier = FileManager.default.temporaryDirectory.appending(path: "chantier-import-debug")
            try? FileManager.default.removeItem(at: dossier)
            fichiersDebug = chemin.split(separator: ":").map(String.init)
            let nom = "chantier-import-debug"
            UserDefaults.standard.removePersistentDomain(forName: nom)
            reglages = UserDefaults(suiteName: nom) ?? reglages
        }
        #endif
        store = SnapshotStore(directory: dossier)
        self.reglages = reglages

        if !fichiersDebug.isEmpty {
            for chemin in fichiersDebug {
                if let texte = try? String(contentsOfFile: chemin, encoding: .utf8) { importer(texte) }
            }
        } else if arguments.bool(forKey: "exemple") {
            chargerExemple(retenir: false)             // `-exemple 1` : pour les captures, rien n'est retenu
        } else if let derniere = store.latest() {
            affiche = calculer(derniere.export, photo: derniere.snapshot)
        } else if reglages.bool(forKey: Self.cleExemple) {
            chargerExemple(retenir: false)
        }
        if let ecran = arguments.string(forKey: "ecran"), let demande = OngletApp(rawValue: ecran) { onglet = demande }
        rafraichirPressePapiers()
    }

    // MARK: Import

    /// Texte collé avec le bouton système. Un texte qui n'est pas un export ne change rien.
    func importer(_ texte: String) {
        do throws(SnapshotStore.SaveError) {
            let resultat = try store.save(texte)
            guard let derniere = store.latest() else { throw .cannotWrite }
            affiche = calculer(derniere.export, photo: derniere.snapshot)
            reglages.removeObject(forKey: Self.cleExemple)    // le premier vrai import efface l'exemple
            onglet = .cap
            switch resultat {
            case .created(let photo) where photo != derniere.snapshot:
                retour = Retour(titre: "Photo plus ancienne", detail: "Elle est gardée, mais l'écran montre ta photo la plus récente.", estErreur: false)
            case .created: retour = nil
            case .alreadyStored:
                retour = Retour(titre: "Déjà enregistré", detail: "Cet export est déjà dans tes photos. Rien n'a changé.", estErreur: false)
            }
        } catch {
            retour = Self.message(pour: error, avecPhoto: affiche?.estExemple == false)
        }
        presseTraite = UIPasteboard.general.changeCount
        presseTexteAColler = false
    }

    private static func message(pour erreur: SnapshotStore.SaveError, avecPhoto: Bool) -> Retour {
        let garde = avecPhoto ? "Rien n'a changé : ta dernière photo reste affichée." : "Rien n'a changé."
        switch erreur {
        case .invalid(.empty):
            return Retour(titre: "Le texte est vide", detail: "\(garde) Copie l'export dans le jeu, puis reviens ici.", estErreur: true)
        case .invalid(.tooLarge):
            return Retour(titre: "Ce n'est pas un export de village", detail: "\(garde) Le texte est beaucoup trop long pour en être un.", estErreur: true)
        case .invalid(.notJSON):
            return Retour(titre: "Ce n'est pas un export de village", detail: "\(garde) Le texte est illisible ou coupé : copie l'export en entier, depuis le jeu.", estErreur: true)
        case .invalid(.notAVillageExport):
            return Retour(titre: "Ce n'est pas un export de village", detail: "\(garde) Dans le jeu : Data Export, puis Copier.", estErreur: true)
        case .cannotWrite:
            return Retour(titre: "Photo non enregistrée", detail: "L'espace de l'app n'est pas accessible en écriture. \(garde)", estErreur: true)
        }
    }

    // MARK: Exemple

    /// Le village embarqué : en mémoire seulement, jamais dans les photos.
    func chargerExemple(retenir: Bool = true) {
        guard let url = Bundle.main.url(forResource: "exemple-village", withExtension: "json"),
              let texte = try? String(contentsOf: url, encoding: .utf8),
              let export = try? VillageExport.parse(texte) else { return }
        affiche = calculer(export, photo: nil)
        if retenir { reglages.set(true, forKey: Self.cleExemple) }
        onglet = .cap
    }

    private func calculer(_ export: VillageExport, photo: Snapshot?) -> VillageAffiche? {
        guard let reference else { return nil }
        let village = Village(export: export, reference: reference)
        return VillageAffiche(village: village, rapport: progress(of: village, reference: reference), photo: photo)
    }

    // MARK: Presse-papiers

    /// Au retour au premier plan. `hasStrings` et `changeCount` ne lisent rien et n'affichent aucune alerte.
    func rafraichirPressePapiers() {
        let presse = UIPasteboard.general
        if presse.changeCount != presseTraite { retour = nil }       // un nouveau texte efface l'ancien message
        presseTexteAColler = presse.hasStrings && presse.changeCount != presseTraite
    }

    func fermerRetour() { retour = nil }
}
