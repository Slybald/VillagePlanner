import Foundation
import Testing
@testable import ChantierKit

/// Le conseils.json embarqué, contrôlé contre reference.json.
@Suite struct ConseilsTests {
    static let reference = try! ReferenceData.load()
    static let conseils = try! AdviceData.load()
    static let categorie: [String: ChantierKit.Category] =
        ["defenses": .defenses, "laboratory": .laboratory, "equipment": .equipment, "pets": .pets]

    /// Les erreurs du fichier : identifiant inconnu, doublon, mauvaise catégorie, source ou critère manquant.
    static func problemes(_ a: AdviceData, _ r: ReferenceData) -> [String] {
        var p: [String] = []
        if a.date.isEmpty { p.append("date absente") }
        if a.fallback.isEmpty { p.append("règle de repli absente") }
        for nom in AdviceData.listNames {
            guard let liste = a.lists[nom] else { p.append("\(nom): liste absente"); continue }
            if liste.criterion.isEmpty { p.append("\(nom): critère absent") }
            if liste.sources.isEmpty || liste.sources.contains(where: { !$0.hasPrefix("https://") }) { p.append("\(nom): sources") }
            if liste.ids.isEmpty { p.append("\(nom): liste vide") }
            if Set(liste.ids).count != liste.ids.count { p.append("\(nom): doublon") }
            for id in liste.ids {
                guard let e = r.item(id) else { p.append("\(nom): identifiant inconnu \(id)"); continue }
                if e.category != categorie[nom] { p.append("\(nom): \(id) n'est pas de la catégorie \(nom)") }
            }
        }
        let tous = AdviceData.listNames.flatMap { a.lists[$0]?.ids ?? [] }
        if Set(tous).count != tous.count { p.append("identifiant dans deux listes") }
        return p
    }

    @Test func fichierValide() {
        #expect(Self.problemes(Self.conseils, Self.reference) == [])
        #expect(Self.conseils.lists.count == 4)
    }

    @Test func identifiantInexistantEstDetecte() {
        var listes = Self.conseils.lists
        let l = listes["pets"]!
        listes["pets"] = AdviceList(criterion: l.criterion, sources: l.sources, ids: l.ids + [99_999_999])
        let faux = AdviceData(date: Self.conseils.date, fallback: Self.conseils.fallback, lists: listes)
        #expect(Self.problemes(faux, Self.reference).contains("pets: identifiant inconnu 99999999"))
    }

    @Test func doublonEstDetecte() {
        var listes = Self.conseils.lists
        let l = listes["pets"]!
        listes["pets"] = AdviceList(criterion: l.criterion, sources: l.sources, ids: l.ids + [l.ids[0]])
        let faux = AdviceData(date: Self.conseils.date, fallback: Self.conseils.fallback, lists: listes)
        #expect(Self.problemes(faux, Self.reference).contains("pets: doublon"))
    }

    @Test func absentsClassesApresLaListeLeMoinsCherDAbord() {
        struct E { let id: Int; let cout: Int }
        let a = AdviceData(lists: ["pets": AdviceList(criterion: "x", sources: [], ids: [30, 10])])
        let r = a.sorted([E(id: 99, cout: 5), E(id: 10, cout: 900), E(id: 50, cout: 5), E(id: 30, cout: 800), E(id: 60, cout: 1)],
                         in: "pets", id: \.id, cost: \.cout)
        #expect(r.map(\.id) == [30, 10, 60, 50, 99])
    }

    @Test func formatInconnuEtFichierCorrompu() {
        #expect(throws: AdviceError.unsupportedFormat(9)) { try AdviceData.decode(Data(#"{"format":9}"#.utf8)) }
        #expect(throws: AdviceError.corrupt) { try AdviceData.decode(Data("pas du json".utf8)) }
    }
}
