# Installer l'app sur ton iPhone

Avec un compte Apple gratuit, sans payer les 99 $ par an du programme développeur. Il faut un Mac avec Xcode 26.6 ou plus récent, et un iPhone sous iOS 26 ou plus récent.

Limite à connaître : avec un compte gratuit, l'app expire au bout de **sept jours**. Elle ne s'ouvre plus tant qu'on ne l'a pas réinstallée (étape 9). Les photos enregistrées restent, tant qu'on réinstalle par-dessus sans supprimer l'app.

## 1. Ajouter ton compte Apple dans Xcode

Xcode > Réglages > Comptes > « + » > Identifiant Apple. Un compte gratuit suffit : Xcode crée une équipe « Personal Team ».

## 2. Écrire ton identifiant d'équipe dans le fichier de signature local

Le dépôt ne contient aucun identifiant d'équipe : il lit un fichier local, ignoré par git. Pour connaître ton identifiant, choisis l'équipe une fois dans Xcode :

1. Ouvre `Chantier.xcodeproj`, sélectionne la cible Chantier, onglet Signing & Capabilities, et choisis ton « Personal Team » dans Team. Fais la même chose pour la cible ChantierWidget.
2. Relève l'identifiant d'équipe (dix caractères, lettres et chiffres) avec cette commande, qui lit `DEVELOPMENT_TEAM` dans le projet :
   ```sh
   grep -m1 DEVELOPMENT_TEAM Chantier.xcodeproj/project.pbxproj
   ```
3. Crée le fichier local et mets-y cet identifiant à la place de `ABCDE12345` :
   ```sh
   cp Config/Signature.exemple.xcconfig Config/Signature.local.xcconfig
   ```
4. Remets Team à « None » dans Signing & Capabilities des deux cibles : l'équipe est désormais lue dans `Signature.local.xcconfig`, et le projet ne garde aucun changement à commiter. N'utilise pas `git checkout` sur le projet si tu as d'autres changements en cours.

Ne commite jamais `Signature.local.xcconfig`.

## 3. Brancher l'iPhone

Branche-le au Mac avec un câble, déverrouille-le et touche « Faire confiance » quand il le demande. Il apparaît ensuite dans la liste des destinations de Xcode.

## 4. Activer le mode développeur de l'iPhone

Réglages > Confidentialité et sécurité > Mode développeur > activer. L'iPhone redémarre, puis demande de confirmer. Cette ligne n'apparaît qu'après avoir branché l'iPhone à Xcode.

## 5. Lancer depuis Xcode

Ouvre `Chantier.xcodeproj`, choisis ton iPhone comme destination, puis Product > Run (⌘R). Si Xcode dit que l'identifiant de l'app `fr.slybald.chantier` n'est pas disponible, décommente la ligne `APP_BUNDLE_ID` dans ton `Config/Signature.local.xcconfig` et mets-y le tien (par exemple `fr.tonnom.chantier`). Le widget (`<id>.widget`) et l'App Group (`group.<id>`) en sont dérivés : rien d'autre à changer, rien à commiter.

## 6. Faire confiance au développeur

Au premier lancement, iOS refuse d'ouvrir l'app (« développeur non approuvé »). Sur l'iPhone : Réglages > Général > VPN et gestion de l'appareil > ton identifiant Apple > Faire confiance. Relance ensuite l'app.

## 7. Le widget et l'App Group (essai du conteneur partagé)

Le widget lit un fichier que l'app écrit dans un conteneur partagé, l'**App Group** `group.<identifiant de l'app>`. Cette première version n'affiche qu'un texte d'essai : elle sert à savoir si ton compte gratuit accepte l'App Group.

1. Dans Xcode, sélectionne la cible **Chantier**, onglet Signing & Capabilities. Vérifie : Team = ton Personal Team (ou « None » si tu as rempli `Signature.local.xcconfig`), et, dans la capacité **App Groups**, la case `group.fr.slybald.chantier` (ou `group.<ton identifiant>`) cochée. La capacité est déjà déclarée par `Config/Chantier.entitlements`. Si la case n'est pas cochée ou est rouge, touche l'actualisation (flèches) à côté de la liste.
2. Fais exactement la même vérification sur la cible **ChantierWidget**. Les deux cibles doivent porter **le même** groupe.
3. Lance l'app sur l'iPhone (étape 5), ouvre-la une fois. Elle écrit le texte d'essai au lancement.
4. Écran d'accueil de l'iPhone : appui long sur le fond > « + » > cherche « Chantier » > « Essai du conteneur » > Ajouter le widget.

**Ce que tu dois voir.** Le widget affiche « Conteneur partagé : OK, écrit par l'app à HH:MM ».
- « Ouvre l'app une fois » : le groupe existe mais l'app n'y a encore rien écrit. Ouvre l'app, puis attends ou retire et remets le widget.
- « App Group indisponible » : l'iPhone n'a pas accordé le groupe à l'app ou au widget. Regarde le message de Xcode (ci-dessous).

**Si le compte gratuit refuse l'App Group.** Xcode le dit au moment de signer (ou de choisir l'équipe), dans Signing & Capabilities, en rouge. Messages attendus, selon le cas : « Failed Registering Bundle Identifier. The app identifier "…" cannot be registered to your development team because it is not available » (identifiant déjà pris : change `APP_BUNDLE_ID`, voir l'étape 5), ou un message disant que l'équipe n'a pas accès à la capacité App Groups, ou « Provisioning profile … doesn't include the com.apple.security.application-groups entitlement ». Ces deux derniers textes sont de mémoire, non vus sur un compte gratuit ; recopie le message exact dans ta réponse.
- Si le refus vient seulement de l'identifiant : un `APP_BUNDLE_ID` à toi règle le problème. Chaque compte gratuit a son propre espace d'identifiants ; un identifiant lié à une capacité n'appartient qu'à une équipe (source : réponse d'un ingénieur Apple, [forum développeurs, fil 834802](https://developer.apple.com/forums/thread/834802)).
- Si le compte refuse l'App Group lui-même : le widget ne peut pas lire les photos, et il faudra le compte payant (99 $ par an, décision D2). Les sources se contredisent sur ce point : la liste officielle des capacités ([Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)) cite « App groups » mais le tableau des comptes gratuits n'en est pas lisible hors navigateur ; seul cet essai tranche.

## 8. Premier usage

Dans le jeu, ouvre ton profil, puis Réglages > Plus de réglages > Data Export > Copier. Reviens dans l'app et touche Coller. Aucune alerte d'iOS ne doit apparaître. Si une alerte « Autoriser le collage » s'affiche, note-le : c'est un défaut à corriger.

## 9. Au bout de sept jours

L'app ne s'ouvre plus. Branche l'iPhone et relance Product > Run (⌘R) depuis Xcode : l'app est réinstallée par-dessus, avec ses photos, et valable sept jours de plus. Ne supprime pas l'app avant : tu perdrais les photos enregistrées.
