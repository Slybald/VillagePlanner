import ChantierKit
import SwiftUI

@main
struct ChantierApp: App {
    var body: some Scene {
        WindowGroup {
            EcranProvisoire()
        }
    }
}

/// Écran provisoire, remplacé par l'écran Cap (T07).
struct EcranProvisoire: View {
    var body: some View {
        ContentUnavailableView {
            Label("Chantier", systemImage: "hammer")
        } description: {
            Text("Bientôt : colle l'export de ton village pour voir ton avancement dans \(Category.allCases.count) catégories.")
        }
    }
}

#Preview {
    EcranProvisoire()
}
