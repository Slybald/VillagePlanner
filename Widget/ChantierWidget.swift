import SwiftUI
import WidgetKit

/// Première étape de T25 : un widget qui lit un texte écrit par l'app dans le conteneur partagé (App Group).
/// Il sert à vérifier que le compte Apple accepte l'App Group ; les vrais widgets viennent ensuite.
@main
struct ChantierWidgetBundle: WidgetBundle {
    var body: some Widget { EssaiConteneur() }
}

struct EssaiConteneur: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EssaiConteneur", provider: Fournisseur()) { entree in
            Text(entree.texte)
                .font(.callout)
                .multilineTextAlignment(.center)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Essai du conteneur")
        .description("Affiche le texte écrit par l'app dans le conteneur partagé.")
        .supportedFamilies([.systemSmall])
    }
}

struct Entree: TimelineEntry {
    let date: Date
    let texte: String
}

struct Fournisseur: TimelineProvider {
    func placeholder(in context: Context) -> Entree { Entree(date: .now, texte: "Conteneur partagé") }

    func getSnapshot(in context: Context, completion: @escaping (Entree) -> Void) {
        completion(Entree(date: .now, texte: lireTexte()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entree>) -> Void) {
        completion(Timeline(entries: [Entree(date: .now, texte: lireTexte())], policy: .never))
    }

    /// Le groupe est « group.<identifiant de l'app> » ; celui du widget est « <identifiant de l'app>.widget ».
    private func lireTexte() -> String {
        let identifiantApp = (Bundle.main.bundleIdentifier ?? "").replacingOccurrences(of: ".widget", with: "")
        guard let dossier = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + identifiantApp) else {
            return "App Group indisponible"
        }
        return (try? String(contentsOf: dossier.appending(path: "essai.txt"), encoding: .utf8)) ?? "Ouvre l'app une fois"
    }
}
