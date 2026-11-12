# Exports de test

Tous ces fichiers portent le tag factice `#2PP`. Ils sont tirés de `reel-hdv16.json` (le vrai export, anonymisé par `swift run outils anonymiser <entrée> <sortie>`), avec une seule altération chacun. Le lecteur est `VillageExport.parse`. Ce tableau est le contrat de T03 : chaque fichier doit donner exactement le résultat écrit ici, sans jamais planter.

## Export réel

| Fichier | Résultat attendu |
|---|---|
| `reel-hdv16.json` | Lecture réussie, aucun avertissement. 46 entrées et 420 objets dans `buildings` (325 murs), 44 pièges, 30 troupes, 7 engins, 17 sorts, 6 héros (3 avec minuteur), 8 familiers (1 avec minuteur), 41 équipements, 3 assistants, 8 minuteurs dans le village principal. |

## Exports abîmés

| Fichier | Altération | Résultat attendu |
|---|---|---|
| `abime-01-vide.json` | fichier de 0 octet | erreur `empty` |
| `abime-02-tronque.json` | coupé au milieu | erreur `notJSON` |
| `abime-03-pas-un-export.json` | JSON valide, sans `timestamp` ni section connue | erreur `notAVillageExport` |
| `abime-04-sans-timestamp.json` | `timestamp` retiré | erreur `notAVillageExport` |
| `abime-05-niveau-negatif.json` | `lvl` de la troupe `4000000` (section `units`) à -3 | lecture réussie ; l'entrée `units`/`4000000` est écartée (absente du résultat), les autres sont intactes ; exactement 1 avertissement, qui nomme l'identifiant `4000000` et le champ `lvl` |
| `abime-06-cnt-zero.json` | `cnt` du piège `12000000` (section `traps`) à 0 | lecture réussie ; l'entrée `traps`/`12000000` est écartée ; exactement 1 avertissement, qui nomme l'identifiant `12000000` et le champ `cnt` |
| `abime-07-lvl-texte.json` | `lvl` du héros `28000000` (section `heroes`) écrit `"quatre-vingt-cinq"` | lecture réussie ; l'entrée `heroes`/`28000000` est écartée ; exactement 1 avertissement, qui nomme l'identifiant `28000000` et le champ `lvl` |
| `abime-08-5mo.json` | export valide (JSON bien formé) + champ `bourrage` de 5 Mo dans l'objet racine | erreur `tooLarge`, sans décodage (limite 1 Mo) : la taille est la seule raison du refus |

## Exports d'une version future

Aucun ne dépend du maximum actuel du jeu : les valeurs (`99`, `999`, identifiants inventés) sont hors de toute borne plausible.

| Fichier | Altération | Résultat attendu |
|---|---|---|
| `futur-01-section-inconnue.json` | section `guardians_futurs` ajoutée | lecture réussie ; la section `guardians_futurs` est conservée ; exactement 1 avertissement, qui nomme la section `guardians_futurs` |
| `futur-02-identifiant-inconnu.json` | troupe `77777777` ajoutée à la fin de `units` | lecture réussie ; l'entrée `units`/`77777777` est conservée ; 0 avertissement tant que T04 n'existe pas, puis exactement 1, qui nomme l'identifiant `77777777` et le champ `data` |
| `futur-03-champ-inconnu.json` | champ `champ_futur` sur le premier héros | lecture réussie ; champ conservé dans `extras` ; pas d'erreur |
| `futur-04-hdv-99.json` | hôtel de ville au niveau 99 | lecture réussie ; niveau 99 conservé tel quel |
| `futur-05-niveau-999.json` | `lvl` de la troupe `4000000` (section `units`) à 999 | lecture réussie ; l'entrée `units`/`4000000` est conservée avec le niveau 999 ; 0 avertissement tant que T04 n'existe pas, puis exactement 1, qui nomme l'identifiant `4000000` et le champ `lvl` |
| `futur-06-section-connue-vide.json` | `spells` vaut `[]` | lecture réussie ; section vide, aucun sort ; pas d'erreur |

Les avertissements « identifiant inconnu » et « niveau au-dessus du maximum » ne peuvent venir qu'après T04 (données de référence) ; avant, le lecteur n'en produit aucun.

Un avertissement nomme toujours l'identifiant (`data`) et le champ en cause ; « écartée » veut dire absente du résultat, jamais corrigée. `outils anonymiser` refuse d'écrire si un tag apparaît ailleurs que dans un champ `tag` (par exemple dans un texte).
