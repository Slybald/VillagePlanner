import Foundation

/// Ce que devient un texte qu'on importe (écran, bouton de collage, action Raccourcis) : UN seul chemin pour tous.
public enum ResultatImport: Equatable, Sendable {
    /// Écrite ; `plusRecente` faux quand l'écran garde une photo plus récente.
    case enregistree(Snapshot, plusRecente: Bool)
    /// Même export qu'une photo déjà là : rien n'est écrit.
    case dejaPresente
    /// Rien n'est écrit.
    case refuse(SnapshotStore.SaveError)

    /// Valide, enregistre et met l'index à jour. Ne plante sur aucun texte (borné par `VillageExport.parse`).
    /// `actualiser` est appelé UNE fois, avec la photo la plus récente, quand l'import a réussi (ou que l'export était
    /// déjà là) et jamais quand il est refusé : c'est là que l'app recalcule, recharge le widget et replanifie.
    /// `actions` : une photo nouvelle efface d'abord les actions « Lancé » qui ne lui sont pas postérieures (L3).
    public static func importer(_ texte: String, dans historique: HistoryStore, context: HistoryContext,
                                actions: LocalActionStore? = nil,
                                actualiser: (Snapshot, VillageExport) -> Void = { _, _ in }) -> ResultatImport {
        let resultat: SnapshotStore.Outcome
        do { resultat = try historique.add(texte, context: context).outcome } catch { return .refuse(error) }
        guard let derniere = historique.photos.latest() else { return .refuse(.cannotWrite) }
        if case .created(let photo) = resultat { actions?.purge(importedAt: photo.date) }   // la photo se relit : elle fait foi
        actualiser(derniere.snapshot, derniere.export)
        switch resultat {
        case .created(let photo): return .enregistree(photo, plusRecente: photo == derniere.snapshot)
        case .alreadyStored: return .dejaPresente
        }
    }

    /// La phrase que l'action rend, en français. `cap` : la date du cap après l'import (nil : pas de plan ou tout est fait).
    public func phrase(cap: Date?, now: Date, timeZone: TimeZone) -> String {
        switch self {
        case .enregistree(_, let plusRecente):
            guard plusRecente else { return "Photo enregistrée, mais ta photo la plus récente reste affichée" }
            guard let cap else { return "Photo enregistrée" }
            return "Photo enregistrée, cap au " + Lisible.jour(cap, now: now, timeZone: timeZone)
        case .dejaPresente:
            return "Cet export est déjà dans tes photos"
        case .refuse(.invalid(.empty)):
            return "Le texte est vide"
        case .refuse(.invalid):
            return "Ce n'est pas un export"
        case .refuse(.cannotWrite):
            return "Photo non enregistrée : l'espace de l'app n'est pas accessible en écriture"
        }
    }
}
