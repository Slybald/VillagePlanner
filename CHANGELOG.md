# Journal des modifications

## [Non publié]

### Modifié
- L'app s'appelle « Village Planner » (anciennement Chantier) : nom sous l'icône, identifiant `fr.slybald.villageplanner`, projet `VillagePlanner.xcodeproj`, paquet `VillagePlannerKit`, interrupteurs `VILLAGEPLANNER_WIDGETS` et `VILLAGEPLANNER_VITESSE`. Identifiant, App Group et Trousseau changent : l'app n'était pas encore installée, rien à migrer.

### Ajouté
- Widgets (petit, moyen, écran verrouillé) : postes libres et comptes à rebours animés par le système, chronologie à l'heure juste, photos et index dans un conteneur partagé (App Group) avec déplacement sans perte ; interrupteur `VILLAGEPLANNER_WIDGETS` pour compiler sans widget.
- Icône de l'app (mètre pliant en forme de flèche) en clair, sombre et teinté ; icône en tête de l'écran À propos.
- README illustré (captures, installation, export, conseiller, compte de jeu, mention non officielle, crédits).
- Lecteur d'export tolérant, exports de test anonymisés et garde-fou d'anonymat.
- Données de référence du jeu, outil `maj-reference`, noms français et données de conseil.
- Village et avancement par hôtel de ville et par catégorie ; écran Village ; écrans Cap et Ouvriers.
- Import par collage, première photo, historique des photos, différences et ticket de travaux.
- Plan par poste selon le profil de jeu, simulation des ouvriers, du labo et des assistants, date du cap, ressources à réunir, taux d'occupation.
- Réglages du profil de jeu et des réductions.
- Conseiller : client Claude, clé dans le Trousseau, budget, consigne avec garde-fous, profil en une phrase, questions sur le plan.
- Compte de jeu : client de l'API officielle par le relais RoyaleAPI, écran Joueur et équipements équipés.
- Direction artistique « Village vivant » (polices Lilita One et Fredoka, licence OFL).
- Accessibilité : très grande police, VoiceOver, états limites.
- Squelette du dépôt : paquet `VillagePlannerKit` avec les contrats de types, outil `outils`, app provisoire, intégration continue.
