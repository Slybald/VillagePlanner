import ChantierKit
import UIKit
import WidgetKit

/// Ce que l'app dit au widget (T25) : les minuteurs de la dernière photo, couloir par couloir, et l'image de chacun.
/// Écrit dans le conteneur partagé, puis recharge les chronologies : le widget change d'état à l'heure juste, sans
/// rafraîchissement. Sans conteneur (interrupteur `CHANTIER_WIDGETS=NO`, App Group refusé), rien n'est écrit.
enum PontWidget {
    /// Côté des images écrites pour le widget, en pixels (une cellule du moyen ou le petit à trois fois la densité).
    private static let cotePixels: CGFloat = 176

    /// `decalage` : en débogage seulement, avance les dates du plan de l'exemple jusqu'à maintenant (captures du widget).
    static func publier(plan: Plan, village: Village, reference: ReferenceData, partage: URL?, decalage: TimeInterval = 0) {
        guard let partage else { return }
        let dossierImages = WidgetEtat.dossierImages(dans: partage)
        try? FileManager.default.removeItem(at: dossierImages)
        try? FileManager.default.createDirectory(at: dossierImages, withIntermediateDirectories: true)

        func image(_ id: Int, _ niveau: Int) -> String? {
            let nom = "\(id)_\(niveau).png"
            guard let source = Illustrations.image(id, niveau: niveau) else { return nil }
            let rendu = UIGraphicsImageRenderer(size: CGSize(width: cotePixels, height: cotePixels), format: {
                let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
            }()).pngData { _ in
                let rapport = min(cotePixels / source.size.width, cotePixels / source.size.height)
                let taille = CGSize(width: source.size.width * rapport, height: source.size.height * rapport)
                source.draw(in: CGRect(x: (cotePixels - taille.width) / 2, y: (cotePixels - taille.height) / 2,
                                       width: taille.width, height: taille.height))
            }
            return (try? rendu.write(to: dossierImages.appending(path: nom), options: .atomic)) == nil ? nil : nom
        }

        let postes = Couloir.de(plan, village: village).map { couloir in
            WidgetEtat.Poste(
                genre: couloir.poste, numero: couloir.numero,
                imageLibre: image(couloir.emblem, couloir.niveauEmblem),
                travail: couloir.enCours.map { pas in
                    WidgetEtat.Travail(nom: reference.item(pas.step.itemID)?.name ?? "#\(pas.step.itemID)", niveau: pas.step.level,
                                       fin: pas.end.addingTimeInterval(decalage), image: image(pas.step.itemID, pas.step.level))
                })
        }
        WidgetEtat(photo: village.date.addingTimeInterval(decalage), postes: postes).ecrire(dans: partage)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Plus de photo : le widget invite à ouvrir l'app.
    static func retirer(partage: URL?) {
        guard let partage else { return }
        WidgetEtat.effacer(dans: partage)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
