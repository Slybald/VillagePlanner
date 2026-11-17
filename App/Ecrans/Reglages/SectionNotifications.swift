import SwiftUI
import UserNotifications

/// La section « Notifications » des Réglages (T26) : éteinte par défaut. L'autorisation d'iOS n'est demandée qu'au moment
/// où on allume l'option ; refusée, l'option se remet à éteint et la note dit où l'accorder.
struct SectionNotifications: View {
    @Environment(ModeleApp.self) private var modele
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let refusee = modele.autorisationNotifications == .denied
        Section {
            Toggle("Prévenir quand un poste se libère", isOn: Binding(get: { modele.notificationsActives },
                                                                      set: { modele.reglerNotifications($0) }))
        } header: { Text("Notifications").etiquettePlanner() } footer: {
            Group {
                if refusee {
                    Label("Les notifications sont refusées. Pour les autoriser : Réglages d'iOS, Notifications, Village Planner, puis « Autoriser les notifications ».",
                          systemImage: "bell.slash")
                        .foregroundStyle(Theme.Couleur.action)
                } else {
                    Text("Une notification à la fin de chaque minuteur de ta dernière photo, avec l'amélioration conseillée ensuite. Rien pendant tes heures sans jeu : elle attend leur fin.")
                }
            }
            .font(Theme.Police.detail)
            .foregroundStyle(refusee ? Theme.Couleur.action : Theme.Couleur.texteDoux)
        }
        .listRowBackground(Theme.Couleur.surface)
        .task { await modele.rafraichirAutorisationNotifications() }
        .onChange(of: phase) { if phase == .active { Task { await modele.rafraichirAutorisationNotifications() } } }
    }
}
