import AppIntents

/// L'action « Importer un export » de Raccourcis : le texte vient du raccourci (« Obtenir le presse-papiers »), jamais
/// de l'action elle-même, qui ne touche pas au presse-papiers. Même chemin d'import que l'app : `ModeleApp.importer`.
struct ImporterExportIntent: AppIntent {
    static let title: LocalizedStringResource = "Importer un export"
    static let description = IntentDescription("Enregistre l'export de ton village comme une nouvelle photo, sans ouvrir l'app.",
                                               categoryName: "Village")
    static let openAppWhenRun = false

    @Parameter(title: "Texte de l'export")
    var texte: String

    static var parameterSummary: some ParameterSummary { Summary("Importer \(\.$texte)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let phrase = ModeleApp.partage.importer(texte)
        return .result(value: phrase, dialog: IntentDialog(stringLiteral: phrase))
    }
}
