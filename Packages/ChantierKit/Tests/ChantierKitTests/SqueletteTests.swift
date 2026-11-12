import Foundation
import Testing
@testable import ChantierKit

// Les squelettes du §7.2 répondent sans planter (aucun fatalError atteignable depuis l'app).

@Test func exportVideEstRefuse() {
    #expect(throws: ExportError.empty) { try VillageExport.parse("  \n") }
}

@Test func squelettesRepondentSansPlanter() {
    let export = VillageExport(tag: "#2PP", date: Date(timeIntervalSince1970: 0),
                               sections: [:], idLists: [:], boosts: [:], warnings: [])
    let reference = ReferenceData()
    let village = Village(export: export, reference: reference)
    #expect(village.date == export.date)
    _ = progress(of: village, reference: reference)
    #expect(remainingSteps(of: village, reference: reference, profile: Profile(), now: Date(timeIntervalSince1970: 0)).isEmpty)
    _ = makePlan(for: village, reference: reference, advice: AdviceData(),
                 profile: Profile(), now: Date(timeIntervalSince1970: 0))
}
