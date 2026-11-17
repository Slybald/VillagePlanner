import Testing
@testable import outils

@Suite struct AnonymiserTests {
    @Test func tagEnTeteEtEspacesConserves() throws {
        let sortie = try Anonymiser.anonymiser("{\"tag\" : \"#8AAA8\",\"timestamp\":1}")
        #expect(sortie == "{\"tag\" : \"#2PP\",\"timestamp\":1}")
    }

    @Test func tagImbriqueRemplace() throws {
        let sortie = try Anonymiser.anonymiser("{\"a\":{\"tag\":\"#8AAA8\"},\"tag\":\"#9BBB9\"}")
        #expect(sortie == "{\"a\":{\"tag\":\"#2PP\"},\"tag\":\"#2PP\"}")
    }

    @Test func autreTagMajusculesRefuse() {
        #expect(throws: Anonymiser.Erreur.self) {
            try Anonymiser.anonymiser("{\"tag\":\"#8AAA8\",\"note\":\"#7BBB7\"}")
        }
    }

    @Test func autreTagMinusculesRefuse() {
        #expect(throws: Anonymiser.Erreur.self) {
            try Anonymiser.anonymiser("{\"tag\":\"#8AAA8\",\"note\":\"#7bbb7\"}")
        }
    }

    @Test func aucunChampTagRefuse() {
        #expect(throws: Anonymiser.Erreur.self) { try Anonymiser.anonymiser("{\"timestamp\":1}") }
    }
}
