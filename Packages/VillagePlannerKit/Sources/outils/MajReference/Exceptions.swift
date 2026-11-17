import VillagePlannerKit

// Ce que la conversion ne peut pas déduire de la source. Une ligne par cas, avec sa raison.
// Les règles générales sont dans ClashKing.swift : la base des ouvriers (`village` ≠ "home") est
// écartée, super-troupes et troupes saisonnières sont marquées par la source, les défenses
// fabriquées sont lues sous la station, l'Aigle consommé par l'HDV 17 est retiré des nombres.

enum Exceptions {
    /// Types gardés dans la référence (un export qui les contient n'allume pas le bandeau V5),
    /// mais hors avancement.
    static let horsAvancement: [Int: Exclusion] = [
        1000083: .event,           // Sour Elixir Cauldron : bâtiment d'Halloween, sans niveau, jamais donné par l'HDV
        1000097: .craftedDefense,  // Crafting Station : support des défenses fabriquées (V8), sans niveau
    ]

    /// Types retirés du jeu, absents de reference.json.
    static let retires: [Int: String] = [
        // Aucun au 2026-11-09 : la source ne garde que les bâtiments en jeu. Exemple de ligne :
        // 1000999: "Nom : retiré le AAAA-MM-JJ (note de version)",
        :
    ]
}
