import Foundation

// Squelette du contrat §7.2. La simulation et le cap sont la tâche T13.

/// Le plan : améliorations datées, fin de chaque poste, cap, ressources à réunir,
/// améliorations bloquées avec leur raison (S7).
public struct Plan: Sendable {
    public init() {}
}

/// Une amélioration datée.
public struct ScheduledStep: Sendable {
    public init() {}
}

/// `now` est toujours un paramètre : aucun calcul ne lit l'horloge.
public func makePlan(for village: Village, reference: ReferenceData, advice: AdviceData,
                     profile: Profile, now: Date) -> Plan {
    Plan()                                         // squelette : rempli par T13
}
