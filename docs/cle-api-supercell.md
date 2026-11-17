# Clé de l'API officielle de Supercell (facultatif)

Sans cette clé, l'app marche à l'identique. Avec elle, elle peut lire ton profil de joueur (trophées, record, ligue, victoires, dons, étoiles de guerre, succès, héros et équipements équipés). L'API ne donne ni les bâtiments, ni les murs, ni les améliorations en cours : l'export du village reste la source du plan.

## Comment ça passe

L'API de Supercell n'accepte qu'une clé liée à des adresses IP fixes, et un iPhone n'en a pas. L'app appelle donc `https://cocproxy.royaleapi.dev`, le relais communautaire de RoyaleAPI, qui transmet la requête à Supercell depuis une adresse IP fixe. Ce que l'app envoie : ton tag (celui de la dernière photo) et ta clé, en HTTPS, à cet hôte et à aucun autre. Elle fait au plus une lecture par ouverture de l'app et une par heure.

**Cette clé est utilisable par quiconque la connaît, à travers le même relais** : l'adresse déclarée sur la clé est celle du relais, pas celle de ton iPhone. Elle ne lit que des données publiques de joueurs, mais elle compte dans ton quota et porte ton compte développeur. Crée-en donc une **dédiée à cette app**, ne la réutilise nulle part, et révoque-la au moindre doute. Tes appels et ta clé passent aussi par le serveur du relais : c'est le prix de ne pas avoir de serveur à toi.

## Créer la clé

1. Va sur `https://developer.clashofclans.com`, crée un compte développeur (nom et e-mail) ou connecte-toi.
2. Ouvre « My Account », puis « Create New Key ».
3. Nom : `Village Planner`. Description : `app personnelle, lecture de mon profil`.
4. Adresses IP autorisées : `45.79.218.79`, l'adresse du relais (indiquée par RoyaleAPI dans `docs.royaleapi.com/proxy.html`). Vérifie-la sur cette page avant de créer la clé : si RoyaleAPI la change, l'app recevra des erreurs 403.
5. Valide, puis copie la clé (un long texte qui commence par `eyJ`).

## La mettre dans l'app

Réglages, section « Compte de jeu » : colle la clé, touche « Enregistrer dans le Trousseau ». Elle est rangée dans le Trousseau de cet iPhone, sans synchronisation iCloud, sous un compte distinct de celui de la clé du conseiller. L'app ne la réaffiche plus en clair. Une fois la clé collée, copie un autre texte (un mot, par exemple) pour vider le presse-papiers : avec le presse-papiers universel, la clé peut sinon être collée sur un autre appareil Apple connecté à ton compte. « Lire mon profil » fait une lecture. Si le tag de la dernière photo est introuvable, l'app te le dit : importe un export récent.

## La révoquer

- Dans l'app : « Effacer la clé » la retire du Trousseau.
- Sur le portail, « My Account », puis supprime la clé. C'est cette étape qui la rend inutilisable pour quelqu'un d'autre. Fais-la si tu as le moindre doute (téléphone perdu, clé copiée dans un message), puis recrée une clé et colle-la de nouveau.

## Si ça ne marche pas

| Message de l'app | Cause probable |
|---|---|
| Clé refusée (403) | La clé ne déclare pas l'adresse du relais, a été supprimée, ou est mal copiée. |
| Aucun joueur avec ce tag (404) | Le tag de la dernière photo est faux ou le compte a changé : importe un export récent. |
| Trop de requêtes (429) | Le quota de la clé est atteint (la clé sert ailleurs ?). Réessaie plus tard. |
| Maintenance (503) | Supercell est en maintenance du jeu. |
| Erreur du relais ou de l'API (502, 504…) | Le relais ou l'API est en panne. Réessaie plus tard. |

## Conditions d'utilisation

Le portail développeur renvoie, pour ses conditions, à la politique de contenu des fans de Supercell (`supercell.com/en/fan-content-policy/`, version du 27 septembre 2023), qui permet les « guide apps » non commerciales et gratuites. Ces conditions peuvent changer sans préavis : relis-les avant de créer ta clé. Les conditions propres au relais RoyaleAPI ne sont pas écrites sur la page de documentation du relais ; en cas de doute, demande sur leur serveur Discord (lien sur cette page).
