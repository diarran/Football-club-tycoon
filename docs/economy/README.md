# Économie des FC Coins

Les valeurs de `src/shared/Config.lua`, `Buildings.lua` et `Divisions.lua` sont
équilibrées avec le simulateur `tools/economy-sim.js`. Il fait jouer des joueurs
types sur le **vrai code du jeu** (matchs, achats, sauvegarde entre deux sessions)
et mesure le rythme de progression. Il tourne aussi en CI à chaque push : il
échoue si un match rapporte une somme anormale ou si la D5 devient inatteignable.

```
LUAU_BIN=/chemin/vers/luau node tools/economy-sim.js 100        # 100 parties par profil
LUAU_BIN=/chemin/vers/luau node tools/economy-sim.js 30 --strict # comme la CI
```

Joueurs types (modifiables en haut de `tools/economy-sim.luau`) :
- **actif** : sessions de 40 min, pause de 6 h, un match toutes les 75 s ;
- **occasionnel** : sessions de 15 min, une par jour, un match toutes les 2 min.

Chacun achète ce qui est abordable, du moins cher au plus cher. Le simulateur lit
les niveaux dans `Buildings.Definitions` : de nouveaux niveaux d'amélioration
sont pris en compte sans le modifier.

## Équilibrage du 26/11/2026

| Mesure (médiane) | Avant | Après |
| --- | --- | --- |
| Premier achat | 0 min (3 achats d'office) | 0 min (1 achat, le 2ᵉ après ~2 matchs) |
| D6, joueur actif | 5 min | 9 min (8 matchs) |
| D5, joueur actif | 18 min, 1ʳᵉ session | 40 min (33 matchs), fin de 1ʳᵉ ou 2ᵉ session |
| D5, joueur occasionnel | 22 min, 2ᵉ session | 56 min, 5ᵉ session |
| Tout acheté, joueur actif | 45 min | 73 min (2ᵉ session) |
| Gain par match | ~1 340, jusqu'à 3 960 | ~620, au plus 1 450 |
| Victoires / énergie la plus basse (actif) | 33 % / 0 | 44 % / 90 |

Problèmes trouvés avant :
- la billetterie des tribunes niveau 3 rapportait ~3 200 par match (5 fois la
  prime de victoire) : tout le reste devenait gratuit ;
- les 5 000 FC Coins de départ payaient 3 achats immédiats ;
- un joueur actif vidait l'énergie de son équipe (0) et perdait 2 matchs sur 3 ;
- tout le contenu du MVP était fini en moins d'une heure.

Changements : départ 2 500 ; primes V/N/D 400/200/100 ; billetterie 1 FC Coin
par place (200 / 500 / 1 000 places) ; sponsors des bureaux niveau 2 : 150 ;
énergie −10 par match et +8 par minute ; montée D7 → D6 à 15 points, D6 → D5 à
36 points ; adversaires D6 note 56, D5 note 62.

Point ouvert : une fois tout acheté en D5, les FC Coins s'accumulent sans
dépense possible. Les futurs niveaux d'amélioration et divisions combleront ce vide.

## Dernier rapport (100 parties par profil)


Départ : 2500 FC Coins · prime de match V/N/D : 400/200/100 · recrue : 1500 · délai entre matchs : 60 s
Coût total de tout le contenu (installations + 4 recrues) : 39000

## Joueur actif (sessions de 40 min, pause de 6 h, un match toutes les 75 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 8.8 min | 11.3 min | 8 | 1 |
| Montée en D5 | 40 min | 48.8 min | 33 | 1 |
| Pitch 2 (2500) | 26.3 min | 28.8 min | 22 | 1 |
| Pitch 3 (7500) | 60 min | 63.8 min | 50 | 2 |
| Stands 2 (3000) | 38.8 min | 41.3 min | 32 | 1 |
| Stands 3 (8000) | 72.5 min | 76.3 min | 60 | 2 |
| Training 2 (2000) | 18.8 min | 20 min | 16 | 1 |
| Training 3 (6000) | 47.5 min | 51.3 min | 40 | 2 |
| Offices 2 (2500) | 32.5 min | 35 min | 27 | 1 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| Recrue 1 (1500) | 1.3 min | 1.3 min | 2 | 1 |
| Recrue 2 (1500) | 5 min | 6.3 min | 5 | 1 |
| Recrue 3 (1500) | 7.5 min | 10 min | 7 | 1 |
| Recrue 4 (1500) | 12.5 min | 13.8 min | 11 | 1 |
| Tout acheté | 72.5 min | 76.3 min | 60 | 2 |

Gain par match : médiane 622, max 1449 · victoires : 43.9 % · énergie la plus basse : 90 · solde final médian : 7299.5

## Joueur occasionnel (sessions de 15 min, pause de 24 h, un match toutes les 120 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 12 min | 16 min | 7 | 1 |
| Montée en D5 | 56 min | 70 min | 33 | 5 |
| Pitch 2 (2500) | 38 min | 42 min | 22 | 3 |
| Pitch 3 (7500) | 86 min | 92 min | 50 | 7 |
| Stands 2 (3000) | 56 min | 60 min | 33 | 5 |
| Stands 3 (8000) | 106 min | 110 min | 61 | 8 |
| Training 2 (2000) | 28 min | 28 min | 16 | 2 |
| Training 3 (6000) | 70 min | 74 min | 41 | 6 |
| Offices 2 (2500) | 46 min | 50 min | 27 | 4 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| Recrue 1 (1500) | 0 min | 2 min | 1 | 1 |
| Recrue 2 (1500) | 6 min | 10 min | 4 | 1 |
| Recrue 3 (1500) | 12 min | 14 min | 7 | 1 |
| Recrue 4 (1500) | 18 min | 20 min | 11 | 2 |
| Tout acheté | 106 min | 110 min | 61 | 8 |

Gain par match : médiane 618, max 1449 · victoires : 42.2 % · énergie la plus basse : 90 · solde final médian : 4497

Aucune source de monnaie infinie ni blocage détecté.
