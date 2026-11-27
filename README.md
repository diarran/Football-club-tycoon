# Football Club Tycoon

Jeu Roblox de tycoon et de gestion de club de football, multijoueur
(PC, mobile, tablette). Chaque joueur part d'un petit club amateur en D7,
développe son stade, recrute son effectif et lance des matchs simulés pour
monter dans les divisions. Monnaie : **FC Coins**.

👉 **Pour ouvrir le jeu dans Studio : [OUVRIR_DANS_STUDIO.md](OUVRIR_DANS_STUDIO.md)**

🚀 **Pour publier le jeu et y jouer sur téléphone : [GUIDE_PUBLICATION.md](GUIDE_PUBLICATION.md)**

🖼️ **Pour mettre le vrai logo et les écussons : [GUIDE_IMAGES.md](GUIDE_IMAGES.md)** · Jeu publié : https://www.roblox.com/games/75942746782438

✅ **Tests automatiques (sans Studio) : [tests/README.md](tests/README.md)**

## Structure du dépôt

```
src/
├── server/                     → ServerScriptService.Server (jamais envoyé aux joueurs)
│   ├── Main.server.lua         point d'entrée serveur
│   └── Services/
│       ├── PlayerDataService   profils : chargement, sauvegarde, verrou, versions
│       ├── EconomyService      seul endroit qui modifie les FC Coins
│       ├── ClubService         6 terrains, nom du club, liste des clubs
│       ├── BuildingService     améliorations des installations
│       ├── SquadService        effectif fictif, recrutement, énergie
│       ├── MatchService        simulation, récompenses, divisions
│       └── TutorialService     étapes du tutoriel guidé
├── client/                     → StarterPlayer.StarterPlayerScripts.Client
│   ├── Main.client.lua         point d'entrée client
│   └── Controllers/
│       ├── UIController        HUD et menus (Accueil, Stade, Effectif, Matchs…)
│       ├── CameraController    caméra hybride exploration / gestion
│       └── TutorialController  bandeau d'objectif du tutoriel
└── shared/                     → ReplicatedStorage.Shared (visible par tous)
    ├── Config.lua              constantes : solde de départ, délais, récompenses
    ├── ClubNames.lua           noms de clubs fictifs
    ├── Buildings.lua           installations, niveaux, prix, effets
    ├── Divisions.lua           D7 à D1, règles de montée, clubs fictifs
    ├── PlayerConfig.lua        postes, noms fictifs, notes, prix du recrutement
    ├── TutorialSteps.lua       textes des 6 étapes du tutoriel
    └── Net.lua                 RemoteEvents + limitation de fréquence
assets/                         modèles et ressources de développement
default.project.json            configuration Rojo
rokit.toml                      versions de Rojo, selene et StyLua
```

Le monde 3D (stade, tribunes, bâtiments) sera construit par
`src/server/World/WorldBuilder`. Tant que ce module n'existe pas,
`ClubService` crée des terrains simples pour que le jeu reste jouable.

## Règles d'architecture

- **Le serveur décide de tout** : prix, soldes, résultats de match et
  récompenses sont calculés côté serveur. Le client affiche et envoie des
  demandes, rien de plus.
- Chaque demande client est vérifiée (types, limites, coûts) et limitée en
  fréquence (`Net.lua`).
- Un débit de FC Coins se fait en une seule opération sans pause : deux
  clics rapides ne débitent pas deux fois.
- Les profils ont une version de schéma (`Config.DATA_SCHEMA_VERSION`) et
  des migrations dans `PlayerDataService`.
- Un module = une responsabilité. Pas de script géant.
- Aucun secret dans le dépôt. Les données des joueurs restent dans les
  DataStores Roblox.
- Tout est fictif : noms, clubs, écussons.

## Équilibrage

Les valeurs de départ (5 000 FC Coins, 3 joueurs, prix des améliorations,
récompenses de match) sont dans `src/shared/`. Ce sont des hypothèses de
test, à ajuster après les premières sessions.

## Outils pour développer

- `rojo serve` : synchronisation en direct avec Studio
- `rojo build -o FootballClubTycoon.rbxlx` : fabrique un fichier de place
- `stylua src` : met en forme le code
- `selene src` : vérifie le code

À chaque push, GitHub Actions construit la place et la met à disposition
dans l'onglet **Actions**.
