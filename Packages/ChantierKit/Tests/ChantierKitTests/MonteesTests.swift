import Testing
@testable import ChantierKit

// Montées de niveau entre deux photos (animation de l'app après un import).
struct MonteesTests {
    func e(_ id: Int, _ niveau: Int, _ n: Int = 1) -> Element {
        Element(itemID: id, level: niveau, count: n, maxLevel: 20, baseLevel: 18, upgradeEnds: nil, upgrading: false)
    }

    @Test func unExemplaireSurCinqMonte() {
        let m = Village.montees(de: [e(1, 10, 5)], vers: [e(1, 10, 4), e(1, 11)])
        #expect(m == [1: [11: 10]])
    }

    @Test func sautDeDeuxNiveauxEtRienPourLeReste() {
        let m = Village.montees(de: [e(1, 10), e(2, 5), e(3, 7)], vers: [e(1, 12), e(2, 5), e(3, 7)])
        #expect(m == [1: [12: 10]])
    }

    @Test func construitDepuisRienOuDepuisZero() {
        #expect(Village.montees(de: [], vers: [e(4, 1)]) == [4: [1: 0]])
        #expect(Village.montees(de: [e(4, 0)], vers: [e(4, 1)]) == [4: [1: 0]])
    }

    @Test func nouvelExemplaireSansPerteNAnimePas() {
        // Un deuxième canon apparaît au niveau 1 alors que le premier reste niveau 10 : pas de montée devinable.
        #expect(Village.montees(de: [e(1, 10)], vers: [e(1, 10), e(1, 1)]).isEmpty)
    }
}
