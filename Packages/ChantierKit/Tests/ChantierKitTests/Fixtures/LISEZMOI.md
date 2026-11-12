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
| `abime-05-niveau-negatif.json` | `lvl` de la première troupe à -3 | lecture réussie ; cette entrée est écartée avec un avertissement (niveau invalide) |
| `abime-06-cnt-zero.json` | `cnt` du premier piège à 0 | lecture réussie ; cette entrée est écartée avec un avertissement (nombre invalide) |
| `abime-07-lvl-texte.json` | `lvl` du premier héros écrit `"quatre-vingt-cinq"` | lecture réussie ; cette entrée est écartée avec un avertissement (niveau illisible) |
| `abime-08-5mo.json` | export valide + champ `bourrage` de 5 Mo | erreur `tooLarge`, sans décodage (limite 1 Mo) |

## Exports d'une version future

Aucun ne dépend du maximum actuel du jeu : les valeurs (`99`, `999`, identifiants inventés) sont hors de toute borne plausible.

| Fichier | Altération | Résultat attendu |
|---|---|---|
| `futur-01-section-inconnue.json` | section `guardians_futurs` ajoutée | lecture réussie ; section conservée ; avertissement « section inconnue » |
| `futur-02-identifiant-inconnu.json` | troupe `77777777` ajoutée dans `units` | lecture réussie ; entrée conservée ; avertissement « identifiant inconnu » (une fois les données de référence chargées) |
| `futur-03-champ-inconnu.json` | champ `champ_futur` sur le premier héros | lecture réussie ; champ conservé dans `extras` ; pas d'erreur |
| `futur-04-hdv-99.json` | hôtel de ville au niveau 99 | lecture réussie ; niveau 99 conservé tel quel |
| `futur-05-niveau-999.json` | première troupe au niveau 999 | lecture réussie ; niveau 999 conservé ; avertissement « niveau au-dessus du maximum connu » (une fois les données de référence chargées) |
| `futur-06-section-connue-vide.json` | `spells` vaut `[]` | lecture réussie ; section vide, aucun sort ; pas d'erreur |

Les avertissements « une fois les données de référence chargées » viennent de T04 ; avant, le lecteur ne les produit pas.
