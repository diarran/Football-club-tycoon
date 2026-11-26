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
| `05_match` | match validé par le serveur, délai, récompenses, montée D7 → D5, matchs entre clubs |
| `06_tutorial` | étapes du tutoriel, renommage filtré, instantané client |
| `07_client` | le vrai client branché sur le serveur : boutons, onglets, écran de téléphone |
| `08_concurrency` | arrivées simultanées, départ/retour rapide, sauvegardes en échec, matchs croisés |

## Lancer les tests sur son ordinateur

```
LUAU_BIN=/chemin/vers/luau node tests/run-tests.js          # tous les tests
LUAU_BIN=/chemin/vers/luau node tests/run-tests.js match    # seulement 05_match
```
