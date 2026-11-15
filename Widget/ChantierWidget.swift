import SwiftUI
import WidgetKit

/// Les trois widgets de Chantier (T25) : le petit (prochain poste libre), le moyen (les couloirs) et celui de l'écran
/// verrouillé (compte à rebours). Ils lisent l'état que l'app écrit dans le conteneur partagé ; aucun réseau.
@main
struct ChantierWidgetBundle: WidgetBundle {
    var body: some Widget {
        WidgetPetit()
        WidgetMoyen()
        WidgetVerrou()
    }
}

struct WidgetPetit: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChantierPetit", provider: Fournisseur()) { entree in
            VuePetit(entree: entree)
                .containerBackground(Teinte.fond, for: .widget)
        }
        .configurationDisplayName("Prochain poste libre")
        .description("Combien de postes sont libres, ou dans combien de temps le prochain se libère.")
        .supportedFamilies([.systemSmall])
    }
}

struct WidgetMoyen: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChantierMoyen", provider: Fournisseur()) { entree in
            VueMoyenne(entree: entree)
                .containerBackground(Teinte.fond, for: .widget)
        }
        .configurationDisplayName("Couloirs")
        .description("Tes ouvriers, ton labo et tes familiers : ce qui tourne et quand ça finit.")
        .supportedFamilies([.systemMedium])
    }
}

struct WidgetVerrou: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChantierVerrou", provider: Fournisseur()) { entree in
            VueVerrou(entree: entree)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Compte à rebours")
        .description("Le temps avant que le prochain poste se libère, sur l'écran verrouillé.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
