# Tests automatiques

Ces tests vérifient le jeu **sans ouvrir Roblox Studio**. Ils tournent tout seuls
sur GitHub à chaque modification (onglet « Actions », workflow « Tests automatiques »).

## Comment ça marche

`tests/run-tests.js` assemble, pour chaque fichier `tests/specs/*.spec.luau` :

1. `tools/roblox-mock.luau` : une imitation minimale de l'API Roblox (Instance, Vector3…) ;
2. `tests/harness.luau` : horloge simulée, DataStore en mémoire (pannes et délais
   simulables), joueurs qui arrivent et partent, RemoteEvents qui enregistrent
   tout ce que le serveur envoie ;
3. **tous les vrais fichiers de `src/`**, rangés comme dans le jeu ;
4. le fichier de test.

Puis il l'exécute avec l'interpréteur [Luau](https://github.com/luau-lang/luau/releases).
Chaque fichier de test démarre sur un serveur neuf, avec le vrai `Main.server.lua`.
Le test `07_client` démarre aussi le vrai client (HUD, menus) et clique sur les boutons.

## Ce qui est couvert

| Fichier | Vérifie |
| --- | --- |
| `00_boot` | démarrage du serveur sans erreur, 6 terrains, remotes |
| `01_plots` | un terrain unique par joueur, 6 clubs maximum, terrain libéré au départ |
| `02_economy` | débit unique, prix serveur, valeurs client invalides, limite de fréquence, recrutement |
| `03_save` | sauvegarde, reconnexion, autosave, verrou de session, pannes du DataStore, fermeture |
| `04_temporary` | mode test sans DataStore (Studio) |
| `15_monetization` | boutique Robux : cachée sans ID, objets exclusifs purement visuels jamais vendus en FC Coins, fenêtre d'achat validée par le serveur, un reçu = un seul octroi (reçu rejoué, panne de sauvegarde, reconnexion, panne totale), boost coupé par défaut et plafonné, écran Prestige |
| `13_published` | jeu publié : vraie sauvegarde, même après une panne au démarrage |
| `05_match` | match validé par le serveur, délai, récompenses, montée D7 → D1, matchs entre clubs |
| `06_tutorial` | étapes du tutoriel, renommage filtré, instantané client |
| `07_client` | le vrai client branché sur le serveur : boutons, onglets, écran de téléphone |
| `08_concurrency` | arrivées simultanées, départ/retour rapide, sauvegardes en échec, matchs croisés |
| `09_locale` | français et anglais complets (aucune clé manquante), langue du compte Roblox, choix dans les Paramètres, boutons anglais lisibles sur téléphone |
| `10_progression` | 5 niveaux par installation, Boutique, modèles 3D au bon niveau |
| `11_divisions` | D7 → D1, clubs fictifs, primes croissantes, transferts validés par le serveur, classement de division |
| `10_progression` | 5 niveaux par installation, prix exacts, modèles 3D au niveau 5, Boutique |
| `16_staff_sponsors` | staff du club (embauche validée par le serveur, niveaux, effets modérés), sponsors (offres renouvelées, 1 puis 2 contrats, prime par match, bonus d'objectif unique, fin de contrat), ancien profil migré, onglet Gestion |
| `12_challenges_tournament` | défis entre clubs (mises plafonnées, refus, expiration, anti-spam, seul le club défié répond, 200 défis sans création de monnaie), tournoi du serveur à 2 joueurs (inscriptions, 8 clubs, forfaits, récompenses bornées, événement « tournoi gagné »), écran Matchs |
| `15_replay` | replay 3D des matchs : chronologie identique au score du serveur (buts, minutes, buteurs), 0 à 14 buts entre 30 et 60 s, aucun effet sur le tirage ni les récompenses, visiteurs prévenus, client : replay jusqu'au bout, « Passer », avance rapide, public selon les tribunes |
| `11_academy_vip` | centre de formation (jeunes repérés hors ligne, signature, libération, progression), espace VIP, anciens profils |
| `12_prestige` | personnalisation du club (achat validé par le serveur, conditions de division et de titres, porter/retirer, terrain 3D), salle des trophées (montées, titres de D1, records, tournois), sauvegarde, anciens profils, écran Prestige |

## Lancer les tests sur son ordinateur

```
LUAU_BIN=/chemin/vers/luau node tests/run-tests.js          # tous les tests
LUAU_BIN=/chemin/vers/luau node tests/run-tests.js match    # seulement 05_match
```
