// Squelette du contrat §7.2. Le calcul de l'avancement est la tâche T05.

/// L'avancement d'une catégorie ou du total : fait, à faire, unité.
public struct Progress: Sendable {
    public init() {}
}

/// L'avancement par catégorie et au total.
public struct ProgressReport: Sendable {
    public init() {}
}

public func progress(of village: Village, reference: ReferenceData) -> ProgressReport {
    ProgressReport()                               // squelette : rempli par T05
}
