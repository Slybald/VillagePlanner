import ChantierKit
import Foundation

/// Le plan tel que les écrans Cap et Chantier le montrent : calculé une fois (à l'import, puis au retour au premier plan),
/// avec ce que la simulation suppose et ce que les export dit des potions et des assistants.
struct PlanAffiche {
    let plan: Plan
    /// Le plan « à ton rythme » (T24) : le même, avec le taux d'occupation mesuré ; nil tant que le rythme n'est pas mesuré.
    let planRythme: Plan?
    let rythme: Rhythm?
    let besoins: [ResourceNeed]
    /// Les pas restants, murs compris (les murs n'entrent pas dans le plan : P6).
    let pas: [UpgradeStep]
    let consigne: String
    let profil: Profile
    let photo: Date
    let fuseau: TimeZone

    var maintenant: Date { plan.now }

    init(village: Village, export: VillageExport, reference: ReferenceData, conseils: AdviceData,
         profil reglages: Profile, maintenant: Date, fuseau: TimeZone = .current, rythme: Rhythm? = nil) {
        // Les heures sans jeu suivent le fuseau de l'appareil (le défaut du paquet est Paris, pour des tests reproductibles).
        var profil = reglages
        profil.quietHours?.timeZone = fuseau
        // Sans `boosts`, la potion serait ignorée en silence ; sans `assistants`, les services aussi (S6).
        plan = makePlan(for: village, reference: reference, advice: conseils, profile: profil, now: maintenant,
                        boosts: export.boosts, assistants: Assistants(export: export, reference: reference))
        planRythme = rythme.map {
            makePlan(for: village, reference: reference, advice: conseils, profile: profil, now: maintenant,
                     boosts: export.boosts, assistants: Assistants(export: export, reference: reference), rhythm: $0)
        }
        self.rythme = rythme
        self.profil = profil
        pas = remainingSteps(of: village, reference: reference, profile: profil, now: maintenant)
        besoins = resourceNeeds(of: plan, remaining: pas)
        photo = village.date
        self.fuseau = fuseau
        consigne = ChantierKit.consigne(of: plan, photo: village.date, reference: reference, timeZone: fuseau)
    }

    /// La date du calcul. L'exemple a une date d'export ancienne : ses minuteurs se lisent à cette date.
    /// Débogage : `-decalage <heures>` avance l'horloge (captures d'un poste libre depuis un moment).
    static func horloge(village: Village, estExemple: Bool) -> Date {
        var maintenant = estExemple ? village.date : Date()
        #if DEBUG
        maintenant = maintenant.addingTimeInterval(UserDefaults.standard.double(forKey: "decalage") * 3600)
        #endif
        return maintenant
    }
}
