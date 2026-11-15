import ChantierKit
import UserNotifications

/// Le seul endroit qui parle au centre de notifications d'iOS (T26). Les échéances viennent de `Echeances` (fonction pure) ;
/// ici, on ne fait que les poser. Aucune donnée du joueur n'y passe : le titre et le corps sont ceux de l'échéance.
enum Notifications {
    private static var centre: UNUserNotificationCenter { .current() }

    static func statut() async -> UNAuthorizationStatus { await centre.notificationSettings().authorizationStatus }

    /// Demande l'autorisation à iOS (la fenêtre n'apparaît qu'une fois) ; vrai si elle est accordée.
    static func autoriser() async -> Bool { (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false }

    static func annuler() { centre.removeAllPendingNotificationRequests() }

    /// Remplace tout ce qui est en attente par `echeances` (déjà plafonnées à vingt).
    static func remplacer(par echeances: [Echeance]) {
        annuler()
        let maintenant = Date()
        for e in echeances.prefix(Echeances.plafond) where e.date > maintenant {
            let contenu = UNMutableNotificationContent()
            contenu.title = e.titre
            contenu.body = e.corps
            contenu.sound = .default
            let declencheur = UNTimeIntervalNotificationTrigger(timeInterval: e.date.timeIntervalSince(maintenant), repeats: false)
            centre.add(UNNotificationRequest(identifier: "fin-\(Int(e.date.timeIntervalSince1970))", content: contenu, trigger: declencheur))
        }
    }
}
