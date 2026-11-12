# Installer l'app sur ton iPhone

Avec un compte Apple gratuit, sans payer les 99 $ par an du programme développeur. Il faut un Mac avec Xcode 26.6 ou plus récent, et un iPhone sous iOS 26 ou plus récent.

Limite à connaître : avec un compte gratuit, l'app expire au bout de **sept jours**. Elle ne s'ouvre plus tant qu'on ne l'a pas réinstallée (étape 8). Les photos enregistrées restent, tant qu'on réinstalle par-dessus sans supprimer l'app.

## 1. Ajouter ton compte Apple dans Xcode

Xcode > Réglages > Comptes > « + » > Identifiant Apple. Un compte gratuit suffit : Xcode crée une équipe « Personal Team ».

## 2. Écrire ton identifiant d'équipe dans le fichier de signature local

Le dépôt ne contient aucun identifiant d'équipe : il lit un fichier local, ignoré par git. Pour connaître ton identifiant, choisis l'équipe une fois dans Xcode :

1. Ouvre `Chantier.xcodeproj`, sélectionne la cible Chantier, onglet Signing & Capabilities, et choisis ton « Personal Team » dans Team.
2. Relève l'identifiant d'équipe (dix caractères, lettres et chiffres) avec cette commande, qui lit `DEVELOPMENT_TEAM` dans le projet :
   ```sh
   grep -m1 DEVELOPMENT_TEAM Chantier.xcodeproj/project.pbxproj
   ```
3. Crée le fichier local et mets-y cet identifiant à la place de `ABCDE12345` :
   ```sh
   cp Config/Signature.exemple.xcconfig Config/Signature.local.xcconfig
   ```
4. Remets Team à « None » dans Signing & Capabilities : l'équipe est désormais lue dans `Signature.local.xcconfig`, et le projet ne garde aucun changement à commiter. N'utilise pas `git checkout` sur le projet si tu as d'autres changements en cours.

Ne commite jamais `Signature.local.xcconfig`.

## 3. Brancher l'iPhone

Branche-le au Mac avec un câble, déverrouille-le et touche « Faire confiance » quand il le demande. Il apparaît ensuite dans la liste des destinations de Xcode.

## 4. Activer le mode développeur de l'iPhone

Réglages > Confidentialité et sécurité > Mode développeur > activer. L'iPhone redémarre, puis demande de confirmer. Cette ligne n'apparaît qu'après avoir branché l'iPhone à Xcode.

## 5. Lancer depuis Xcode

Ouvre `Chantier.xcodeproj`, choisis ton iPhone comme destination, puis Product > Run (⌘R). Si Xcode dit que l'identifiant de l'app `fr.slybald.chantier` n'est pas disponible, change-le dans l'onglet Signing & Capabilities de la cible Chantier (par exemple `fr.tonnom.chantier`) et ne commite pas ce changement.

## 6. Faire confiance au développeur

Au premier lancement, iOS refuse d'ouvrir l'app (« développeur non approuvé »). Sur l'iPhone : Réglages > Général > VPN et gestion de l'appareil > ton identifiant Apple > Faire confiance. Relance ensuite l'app.

## 7. Premier usage

Dans le jeu, ouvre ton profil, puis Réglages > Plus de réglages > Data Export > Copier. Reviens dans l'app et touche Coller. Aucune alerte d'iOS ne doit apparaître. Si une alerte « Autoriser le collage » s'affiche, note-le : c'est un défaut à corriger.

## 8. Au bout de sept jours

L'app ne s'ouvre plus. Branche l'iPhone et relance Product > Run (⌘R) depuis Xcode : l'app est réinstallée par-dessus, avec ses photos, et valable sept jours de plus. Ne supprime pas l'app avant : tu perdrais les photos enregistrées.
