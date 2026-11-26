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


## Centre de formation et espace VIP (26/11/2026)

Deux installations « Après MVP » du document de conception (section 4), chacune
avec 5 niveaux. Toutes les valeurs sont dans `src/shared/Buildings.lua`.

| Installation | Niv. 2 | Niv. 3 | Niv. 4 | Niv. 5 | Effet (niv. 1 → niv. 5) |
| --- | --- | --- | --- | --- | --- |
| Centre de formation | 3 500 | 9 000 | 19 000 | 36 000 | un jeune toutes les 30 → 10 min, 1 → 3 places, potentiel 60-70 → 80-94, signature 400 → 800 |
| Espace VIP | 5 000 | 12 000 | 24 000 | 45 000 | billetterie +5 % → +25 %, loges 0 → 450 par match |

- **Jeunes du centre de formation** : repérés même hors ligne (calcul serveur à
  partir de l'heure), note modeste (36 à 52) mais fort potentiel ; ils
  progressent plus vite après chaque match (+15 % à +40 % de chance). Une
  signature coûte bien moins qu'un recrutement classique (1 500). Le bouton
  « Libérer le joueur » fait de la place (3 joueurs minimum). Les signatures ne
  sont pas jouées par le simulateur : c'est une dépense en plus, au choix.
- **Espace VIP** : premier essai à +35 % / 700 → gain maximal 5 271 par match,
  au-dessus du seuil d'alerte (5 000). Réduit à +25 % / 450 → **4 811 au plus**.

| Mesure (médiane, 100 parties) | Avant | Après |
| --- | --- | --- |
| D5, joueur actif | ~40 min | ~39 min (inchangé) |
| Tout acheté, joueur actif | ~4 h 10 (7ᵉ session) | ~5 h (8ᵉ session, ~246 matchs) |
| Tout acheté, joueur occasionnel | ~27 jours | ~31 jours (~7 h de jeu) |
| Gain par match | ~1 690, au plus ~3 800 | ~2 000, au plus ~4 800 |

## Dernier rapport (100 parties par profil)

# Simulation de l'économie (100 parties par profil)

Départ : 2500 FC Coins · prime de match V/N/D : 400/200/100 · recrue : 1500 · délai entre matchs : 60 s
Coût total de tout le contenu (installations + 4 recrues) : 491500

## Joueur actif (sessions de 40 min, pause de 6 h, un match toutes les 75 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 8.8 min | 11.3 min | 8 | 1 |
| Montée en D5 | 38.8 min | 47.5 min | 32 | 1 |
| Pitch 2 (2500) | 23.8 min | 26.3 min | 20 | 1 |
| Pitch 3 (7500) | 85 min | 87.5 min | 71 | 3 |
| Pitch 4 (16000) | 156.3 min | 161.3 min | 129 | 4 |
| Pitch 5 (32000) | 245 min | 252.5 min | 203 | 7 |
| Stands 2 (3000) | 36.3 min | 38.8 min | 30 | 1 |
| Stands 3 (8000) | 93.8 min | 97.5 min | 78 | 3 |
| Stands 4 (18000) | 166.3 min | 172.5 min | 138 | 5 |
| Stands 5 (36000) | 260 min | 267.5 min | 215 | 7 |
| Training 2 (2000) | 17.5 min | 18.8 min | 15 | 1 |
| Training 3 (6000) | 68.1 min | 71.3 min | 56.5 | 2 |
| Training 4 (14000) | 135 min | 140 min | 112 | 4 |
| Training 5 (28000) | 218.8 min | 226.3 min | 181 | 6 |
| Offices 2 (2500) | 30 min | 32.5 min | 25 | 1 |
| Offices 3 (7000) | 77.5 min | 80 min | 64 | 2 |
| Offices 4 (15000) | 145 min | 151.3 min | 120 | 4 |
| Offices 5 (30000) | 232.5 min | 240 min | 192 | 6 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 46.3 min | 50 min | 39 | 2 |
| LockerRoom 4 (9000) | 101.3 min | 105 min | 84 | 3 |
| LockerRoom 5 (18000) | 176.3 min | 182.5 min | 146 | 5 |
| Shop 2 (4000) | 53.8 min | 56.3 min | 45 | 2 |
| Shop 3 (10000) | 116.3 min | 120 min | 96 | 3 |
| Shop 4 (20000) | 196.3 min | 201.3 min | 162 | 5 |
| Shop 5 (38000) | 283.8 min | 291.3 min | 235 | 8 |
| Academy 2 (3500) | 40.6 min | 43.8 min | 34.5 | 2 |
| Academy 3 (9000) | 108.8 min | 112.5 min | 90 | 3 |
| Academy 4 (19000) | 186.3 min | 192.5 min | 154 | 5 |
| Academy 5 (36000) | 272.5 min | 280 min | 225 | 7 |
| VIP 2 (5000) | 60 min | 63.8 min | 50 | 2 |
| VIP 3 (12000) | 125 min | 130 min | 104 | 4 |
| VIP 4 (24000) | 206.3 min | 212.5 min | 171 | 6 |
| VIP 5 (45000) | 297.5 min | 306.3 min | 246 | 8 |
| Recrue 1 (1500) | 1.3 min | 1.3 min | 2 | 1 |
| Recrue 2 (1500) | 3.8 min | 5 min | 4 | 1 |
| Recrue 3 (1500) | 7.5 min | 8.8 min | 7 | 1 |
| Recrue 4 (1500) | 11.3 min | 12.5 min | 10 | 1 |
| Tout acheté | 297.5 min | 306.3 min | 246 | 8 |

Gain par match : médiane 1993, max 4811 · victoires : 55.3 % · énergie la plus basse : 90 · solde final médian : 78846

## Joueur occasionnel (sessions de 15 min, pause de 24 h, un match toutes les 120 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 14 min | 16 min | 8 | 1 |
| Montée en D5 | 56 min | 70 min | 33 | 5 |
| Pitch 2 (2500) | 34 min | 38 min | 20 | 3 |
| Pitch 3 (7500) | 124 min | 126 min | 71 | 9 |
| Pitch 4 (16000) | 224 min | 232 min | 129 | 17 |
| Pitch 5 (32000) | 354 min | 364 min | 203 | 26 |
| Stands 2 (3000) | 53 min | 56 min | 30.5 | 4 |
| Stands 3 (8000) | 136 min | 140 min | 78 | 10 |
| Stands 4 (18000) | 242 min | 248 min | 139 | 18 |
| Stands 5 (36000) | 376 min | 384 min | 215 | 27 |
| Training 2 (2000) | 26 min | 28 min | 15 | 2 |
| Training 3 (6000) | 98 min | 102 min | 57 | 8 |
| Training 4 (14000) | 196 min | 200 min | 112 | 14 |
| Training 5 (28000) | 318 min | 324 min | 182 | 23 |
| Offices 2 (2500) | 42 min | 46 min | 25 | 4 |
| Offices 3 (7000) | 112 min | 114 min | 64 | 8 |
| Offices 4 (15000) | 210 min | 216 min | 121 | 16 |
| Offices 5 (30000) | 336 min | 344 min | 192.5 | 24.5 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 70 min | 72 min | 40 | 5 |
| LockerRoom 4 (9000) | 146 min | 152 min | 84 | 11 |
| LockerRoom 5 (18000) | 254 min | 262 min | 146 | 19 |
| Shop 2 (4000) | 78 min | 82 min | 45 | 6 |
| Shop 3 (10000) | 168 min | 174 min | 96 | 12 |
| Shop 4 (20000) | 282 min | 290 min | 162 | 21 |
| Shop 5 (38000) | 410 min | 420 min | 235 | 30 |
| Academy 2 (3500) | 60 min | 64 min | 35 | 5 |
| Academy 3 (9000) | 156 min | 162 min | 90 | 12 |
| Academy 4 (19000) | 268 min | 276 min | 154 | 20 |
| Academy 5 (36000) | 392 min | 402 min | 225 | 29 |
| VIP 2 (5000) | 88 min | 92 min | 51 | 7 |
| VIP 3 (12000) | 182 min | 186 min | 104 | 13 |
| VIP 4 (24000) | 299 min | 308 min | 171.5 | 22 |
| VIP 5 (45000) | 430 min | 438 min | 246 | 31 |
| Recrue 1 (1500) | 2 min | 2 min | 2 | 1 |
| Recrue 2 (1500) | 6 min | 8 min | 4 | 1 |
| Recrue 3 (1500) | 12 min | 14 min | 7 | 1 |
| Recrue 4 (1500) | 16 min | 18 min | 10 | 2 |
| Tout acheté | 430 min | 438 min | 246 | 31 |

Gain par match : médiane 1899, max 4802 · victoires : 54 % · énergie la plus basse : 90 · solde final médian : 17934.5

Aucune source de monnaie infinie ni blocage détecté.
