# Importer l'export sans ouvrir l'app (Raccourcis)

Village Planner ajoute une action à l'app Raccourcis : **Importer un export**. Elle prend un texte, l'enregistre comme une nouvelle photo de ton village si c'est un export, et répond par une phrase :

- « Photo enregistrée, cap au 14 mars » ;
- « Cet export est déjà dans tes photos » ;
- « Ce n'est pas un export » (ou « Le texte est vide ») : rien n'est enregistré.

L'action recharge le widget et, si l'option est allumée dans les Réglages, replanifie les notifications. Elle ne lit jamais le presse-papiers : c'est le raccourci qui lui passe le texte.

## 1. Créer le raccourci

1. Dans le jeu, copie l'export du village (Réglages > Data Export > Copier).
2. Ouvre l'app Raccourcis, onglet Raccourcis, puis « + ».
3. Ajoute l'action **Obtenir le presse-papiers** (catégorie Presse-papiers).
4. Ajoute l'action **Importer un export** (cherche « Importer un export » ou ouvre Village Planner dans la liste des apps). Son paramètre « Texte de l'export » doit contenir la variable **Presse-papiers** : touche le paramètre, puis choisis la sortie de l'action précédente.
5. Ajoute, si tu veux voir la phrase : **Afficher le résultat** avec la sortie de « Importer un export ».
6. Nomme le raccourci « Importer Village Planner » et valide.

Le raccourci lit le presse-papiers : iOS peut afficher une alerte « Autoriser le collage » la première fois. Choisis « Toujours autoriser » pour Raccourcis.

## 2. Le lancer par le bouton Action

Sur un iPhone qui a le bouton Action : Réglages > Bouton Action > Raccourci > Choisir un raccourci > « Importer Village Planner ». Après avoir copié l'export dans le jeu, un appui long sur le bouton suffit.

(Sans bouton Action : Réglages > Accessibilité > Toucher > Toucher le dos, ou un widget Raccourcis sur l'écran d'accueil.)

## 3. L'automatisation « quand je ferme Clash of Clans »

1. Raccourcis > onglet Automatisation > « + » > **App**.
2. Choisis Clash of Clans, coche **Est fermée** (décoche « Est ouverte »), puis « Exécuter immédiatement ».
3. Choisis le raccourci « Importer Village Planner » (ou refais les deux actions ci-dessus).
4. Valide. Pense à copier l'export avant de quitter le jeu : l'automatisation importe ce que contient le presse-papiers à ce moment-là.

Si le presse-papiers ne contient pas un export, l'action répond « Ce n'est pas un export » et ne change rien.

## À vérifier sur ton iPhone

L'automatisation lit le presse-papiers sans que tu appuies sur rien : iOS peut afficher l'alerte de collage à chaque exécution, ou la laisser passer après « Toujours autoriser ». Ce comportement ne se teste pas sans iPhone.
