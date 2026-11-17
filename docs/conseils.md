# Mettre à jour les conseils de priorité

`Packages/VillagePlannerKit/Sources/VillagePlannerKit/Reference/Ressources/conseils.json` contient des **opinions** de guides
tiers (pas Supercell), pas des faits : quatre listes ordonnées d'identifiants (`defenses`, `laboratory`,
`equipment`, `pets`). Il est écrit à la main, séparément de `reference.json` (que l'outil `maj-reference` produit).

## Format

- `date` : jour de la dernière révision. L'app l'affiche.
- `fallback` : la règle pour les éléments absents d'une liste. Ils passent après elle, du moins cher au plus
  cher, puis par identifiant (`AdviceData.sorted`, `CostKey`). « Moins cher » : le coût du prochain niveau,
  comparé ressource par ressource de la plus rare à la plus commune (minerai étoilé, lumineux, brillant, élixir
  noir, élixir, or), sans taux de change ; un niveau sans coût vaut zéro ; sans prochain niveau, en dernier.
  Un identifiant absent du village ou réservé à un HDV supérieur est ignoré : la liste peut viser plusieurs HDV.
- Pour chaque liste : `criterion` (une phrase qui explique le classement), `sources` (adresses `https://`),
  `ids` (du plus prioritaire au moins prioritaire). Une liste n'a pas besoin d'être complète.

## Après un équilibrage

1. Mettre à jour `reference.json` d'abord (`docs/mise-a-jour-du-jeu.md`).
2. Chercher des guides **récents** (moins de trois mois, avec leur date) sur les ordres de défenses, de labo,
   d'équipements et de familiers. Quand deux guides se contredisent, garder le plus récent ou le plus détaillé
   et noter le désaccord dans la description de la PR.
3. Éditer les `ids` : chercher chaque identifiant par son nom dans `reference.json`, ne jamais en inventer.
   Un élément retiré du jeu sort de la liste.
4. Mettre à jour `date`, `sources` et, si le classement change de logique, `criterion`.
5. `swift test --package-path Packages/VillagePlannerKit` : `ConseilsTests` refuse un identifiant inconnu, un doublon,
   un identifiant de la mauvaise catégorie, un identifiant dans deux listes, une source ou un critère manquant.
6. Ouvrir une PR.
