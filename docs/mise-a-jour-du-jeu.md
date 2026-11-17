# Après une mise à jour du jeu

Les coûts, durées, nombres de bâtiments et niveaux maximums de l'app viennent de
`Packages/VillagePlannerKit/Sources/VillagePlannerKit/Reference/Ressources/reference.json`. Ce fichier est produit par
l'outil `maj-reference` à partir de [ClashKingInc/ClashKingAssets](https://github.com/ClashKingInc/ClashKingAssets)
(GPL-3.0), qui suit les fichiers du jeu un à cinq jours après chaque mise à jour, et contrôlé avec
[chiefpansancolt/clash-of-clans-data](https://github.com/chiefpansancolt/clash-of-clans-data) (MIT).
Il ne se modifie pas à la main.

Signes qu'il est en retard : l'app affiche le bandeau « le jeu a changé » (identifiant inconnu, niveau ou HDV
au-dessus du maximum connu).

## Procédure

1. **Attendre la source.** Vérifier que ClashKing a publié après la mise à jour :
   `gh api 'repos/ClashKingInc/ClashKingAssets/commits?path=assets/static_data&per_page=1' --jq '.[0].commit.committer.date'`.
2. **Lancer l'outil** depuis la racine du dépôt (il faut `gh` connecté) :
   `swift run --package-path Packages/VillagePlannerKit outils maj-reference`.
   Il télécharge les fichiers par `gh api` dans `Packages/VillagePlannerKit/.cache/` (ignoré par git), réécrit
   `reference.json` et écrit le rapport `Packages/VillagePlannerKit/.cache/maj-reference/rapport.md`.
   `--cache` refait la conversion sans réseau depuis le dernier téléchargement.
3. **Lire le rapport.** Éléments et niveaux ajoutés, valeurs changées depuis la version précédente, écarts
   avec la source de contrôle. Un nouveau type de bâtiment arrête l'outil : lui donner sa catégorie dans
   `Sources/outils/MajReference/ClashKing.swift`. Un bâtiment retiré, un événement ou une correction de la
   source va dans `Sources/outils/MajReference/Exceptions.swift`, une ligne par cas avec sa raison.
4. **Lancer les tests** : `swift test --package-path Packages/VillagePlannerKit`. Si les listes attendues de
   `ReferenceTests` changent (par exemple ce qui est déblocable et absent de l'export d'exemple), vérifier
   chaque ligne avant de la corriger.
5. **Ouvrir une PR** avec le rapport (ou son résumé) dans la description, fusionner, puis réinstaller l'app.
