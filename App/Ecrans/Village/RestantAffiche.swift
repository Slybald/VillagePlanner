import ChantierKit
import Foundation

/// Le temps et le coût restants de ce que l'écran Village montre (T10), calculés une fois par écran.
struct RestantAffiche {
    private let pas: [UpgradeStep]
    /// « Avec la réduction actuelle… » quand une réduction du profil court à la date du calcul.
    let mentionReduction: String?

    /// Le profil n'est pas réglable avant T17 : vide par défaut. Débogage : `-reduction <pourcentage>` (captures).
    static var profilParDefaut: Profile {
        #if DEBUG
        let pourcentage = UserDefaults.standard.integer(forKey: "reduction")
        if pourcentage > 0 {
            return Profile(builderReduction: Reduction(percent: pourcentage, endsAt: .distantFuture))
        }
        #endif
        return Profile()
    }

    /// L'exemple a une date d'export ancienne : ses minuteurs se lisent à cette date, pas à celle d'aujourd'hui.
    init(affiche: VillageAffiche, reference: ReferenceData, profil: Profile = Self.profilParDefaut) {
        let maintenant = affiche.estExemple ? affiche.village.date : Date()
        pas = remainingSteps(of: affiche.village, reference: reference, profile: profil, now: maintenant)
        mentionReduction = Lisible.reductions(profil, at: maintenant)
    }

    /// Une catégorie : « Reste 104 j 5 h · 162 M d'or ».
    func resume(_ categorie: ChantierKit.Category) -> String? {
        Lisible.resume(pas.filter { $0.category == categorie })
    }

    /// Un groupe d'exemplaires (même type, même niveau, même minuteur, comme `Elements.regroupes`).
    func complement(_ e: Element) -> String? {
        Lisible.resume(pas.filter {
            let s = $0.element
            return s.itemID == e.itemID && s.level == e.level && s.upgrading == e.upgrading && s.upgradeEnds == e.upgradeEnds
        }, exemplaires: e.count)
    }
}
