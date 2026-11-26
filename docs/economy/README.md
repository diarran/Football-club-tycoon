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

## Niveaux 4 et 5 + Boutique (26/11/2026)

Chaque installation a maintenant **5 niveaux**, et la **Boutique** (6ᵉ installation)
rapporte un revenu fixe à chaque match. Les prix des niveaux 2 (début de partie)
n'ont pas bougé : le rythme jusqu'à la D5 reste le même.

| Installation | Niv. 2 | Niv. 3 | Niv. 4 | Niv. 5 | Effet au niveau 5 |
| --- | --- | --- | --- | --- | --- |
| Terrain | 2 500 | 7 500 | 16 000 | 32 000 | avantage à domicile +4 |
| Tribunes | 3 000 | 8 000 | 18 000 | 36 000 | 2 500 places (1 FC Coin la place) |
| Entraînement | 2 000 | 6 000 | 14 000 | 28 000 | équipe +4, récupération ×2 |
| Bureaux | 2 500 | 7 000 | 15 000 | 30 000 | sponsors 600 par match |
| Vestiaires | 1 500 | 4 000 | 9 000 | 18 000 | visuel |
| Boutique | 4 000 | 10 000 | 20 000 | 38 000 | ventes 550 par match (25 au départ) |

| Mesure (médiane) | Avant | Après |
| --- | --- | --- |
| D5, joueur actif | 40 min | 40 min (inchangé) |
| Tout acheté, joueur actif | 73 min (2ᵉ session) | ~4 h 10 (7ᵉ session, ~210 matchs) |
| Tout acheté, joueur occasionnel | ~2 h | ~6 h (27ᵉ jour) |
| Gain par match | ~620, au plus 1 450 | ~1 690, au plus ~3 800 |

Un achat devient abordable toutes les 10 à 20 minutes de jeu jusqu'à la fin.
Le gain maximal (tout au niveau 5) reste sous le seuil d'alerte de 5 000 par
match. Après ~4 h, le vide « rien à acheter » revient : de nouvelles divisions
ou des dépenses récurrentes (salaires, entretien) seront la suite logique.


## Dernier rapport (100 parties par profil)

# Simulation de l'économie (100 parties par profil)

Départ : 2500 FC Coins · prime de match V/N/D : 400/200/100 · recrue : 1500 · délai entre matchs : 60 s
Coût total de tout le contenu (installations + 4 recrues) : 338000

## Joueur actif (sessions de 40 min, pause de 6 h, un match toutes les 75 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 8.8 min | 11.3 min | 8 | 1 |
| Montée en D5 | 40 min | 48.8 min | 34 | 2 |
| Pitch 2 (2500) | 25 min | 26.3 min | 21 | 1 |
| Pitch 3 (7500) | 77.5 min | 80 min | 64 | 2 |
| Pitch 4 (16000) | 138.8 min | 143.8 min | 115 | 4 |
| Pitch 5 (32000) | 221.3 min | 227.5 min | 183 | 6 |
| Stands 2 (3000) | 37.5 min | 40 min | 31 | 1 |
| Stands 3 (8000) | 86.3 min | 90 min | 72 | 3 |
| Stands 4 (18000) | 152.5 min | 157.5 min | 126 | 4 |
| Stands 5 (36000) | 239.4 min | 245 min | 197.5 | 6 |
| Training 2 (2000) | 17.5 min | 18.8 min | 15 | 1 |
| Training 3 (6000) | 57.5 min | 60 min | 48 | 2 |
| Training 4 (14000) | 115 min | 120 min | 95 | 3 |
| Training 5 (28000) | 190 min | 195 min | 157 | 5 |
| Offices 2 (2500) | 31.3 min | 33.8 min | 26 | 1 |
| Offices 3 (7000) | 67.5 min | 71.3 min | 56 | 2 |
| Offices 4 (15000) | 126.9 min | 131.3 min | 105.5 | 4 |
| Offices 5 (30000) | 205 min | 211.3 min | 170 | 6 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 42.5 min | 45 min | 36 | 2 |
| LockerRoom 4 (9000) | 95 min | 98.8 min | 79 | 3 |
| LockerRoom 5 (18000) | 161.9 min | 167.5 min | 134.5 | 5 |
| Shop 2 (4000) | 48.8 min | 51.3 min | 41 | 2 |
| Shop 3 (10000) | 103.8 min | 107.5 min | 86 | 3 |
| Shop 4 (20000) | 173.8 min | 178.8 min | 144 | 5 |
| Shop 5 (38000) | 253.1 min | 260 min | 209.5 | 7 |
| Recrue 1 (1500) | 0.6 min | 1.3 min | 1.5 | 1 |
| Recrue 2 (1500) | 3.8 min | 5 min | 4 | 1 |
| Recrue 3 (1500) | 7.5 min | 8.8 min | 7 | 1 |
| Recrue 4 (1500) | 12.5 min | 12.5 min | 11 | 1 |
| Tout acheté | 253.1 min | 260 min | 209.5 | 7 |

Gain par match : médiane 1688, max 3799 · victoires : 55 % · énergie la plus basse : 90 · solde final médian : 73525

## Joueur occasionnel (sessions de 15 min, pause de 24 h, un match toutes les 120 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 12 min | 16 min | 7 | 1 |
| Montée en D5 | 56 min | 66 min | 32 | 4 |
| Pitch 2 (2500) | 34 min | 38 min | 20 | 3 |
| Pitch 3 (7500) | 112 min | 114 min | 64 | 8 |
| Pitch 4 (16000) | 200 min | 206 min | 115 | 15 |
| Pitch 5 (32000) | 320 min | 326 min | 183 | 23 |
| Stands 2 (3000) | 54 min | 56 min | 31 | 4 |
| Stands 3 (8000) | 125 min | 128 min | 71.5 | 9 |
| Stands 4 (18000) | 220 min | 224 min | 126 | 16 |
| Stands 5 (36000) | 344 min | 352 min | 197 | 25 |
| Training 2 (2000) | 26 min | 28 min | 15 | 2 |
| Training 3 (6000) | 84 min | 86 min | 48 | 6 |
| Training 4 (14000) | 166 min | 170 min | 95 | 12 |
| Training 5 (28000) | 272 min | 280 min | 156 | 20 |
| Offices 2 (2500) | 42 min | 48 min | 25 | 4 |
| Offices 3 (7000) | 98 min | 100 min | 56 | 7 |
| Offices 4 (15000) | 182 min | 188 min | 105 | 14 |
| Offices 5 (30000) | 295 min | 304 min | 169.5 | 22 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 62 min | 66 min | 36 | 5 |
| LockerRoom 4 (9000) | 136 min | 140 min | 78 | 10 |
| LockerRoom 5 (18000) | 234 min | 240 min | 134 | 17 |
| Shop 2 (4000) | 70 min | 74 min | 41 | 6 |
| Shop 3 (10000) | 148 min | 154 min | 85 | 11 |
| Shop 4 (20000) | 252 min | 258 min | 144 | 18 |
| Shop 5 (38000) | 365 min | 374 min | 209.5 | 27 |
| Recrue 1 (1500) | 1 min | 2 min | 1.5 | 1 |
| Recrue 2 (1500) | 6 min | 8 min | 4 | 1 |
| Recrue 3 (1500) | 12 min | 14 min | 7 | 1 |
| Recrue 4 (1500) | 16 min | 18 min | 10 | 2 |
| Tout acheté | 365 min | 374 min | 209.5 | 27 |

Gain par match : médiane 1607, max 3795 · victoires : 56.5 % · énergie la plus basse : 90 · solde final médian : 13737.5

Aucune source de monnaie infinie ni blocage détecté.
