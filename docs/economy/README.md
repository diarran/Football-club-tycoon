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


## Divisions D4 à D1 (26/11/2026)

La progression continue jusqu'à la **D1**, objectif long terme. Le rythme D7 → D5
du MVP ne change pas (~40 min pour un joueur actif).

| Division | Seuil de montée | Note des clubs fictifs | Prime de match | Prime en arrivant | Transfert (prix · notes) |
| --- | --- | --- | --- | --- | --- |
| D7 | 15 | 45 | ×1 | — | — |
| D6 | 36 | 56 | ×1 | 500 | — |
| D5 | 320 | 62 | ×1 | 1 500 | 6 000 · 52-60 |
| D4 | 650 | 73 | ×1,4 | 10 000 | 15 000 · 58-66 |
| D3 | 1 000 | 80 | ×1,8 | 25 000 | 30 000 · 65-73 |
| D2 | 1 500 | 86 | ×2,3 | 50 000 | 50 000 · 72-80 |
| D1 | — | 92 | ×3 | 100 000 | 80 000 · 78-86 |

- **Clubs fictifs** : 5 par division (note de −4 à +4 autour de la division). Le
  menu Matchs en propose jusqu'à 3 quand il n'y a pas assez de clubs humains ;
  un adversaire plus fort rapporte une prime plus grosse (±5 % par point).
- **Transferts** (à partir de la D5, effectif complet) : un joueur du niveau de la
  division remplace le moins bien noté. Il est toujours meilleur, et son potentiel
  est limité (+4) : il faut monter pour trouver mieux. C'est la grande dépense de
  fin de partie (~2,5 millions de FC Coins jusqu'à la D1).
- **Classement** : l'onglet affiche le classement de la division (clubs fictifs et
  humains de la même division, seuil de montée), puis les clubs du serveur.

| Mesure (médiane, 30 parties) | Joueur actif | Joueur occasionnel |
| --- | --- | --- |
| D5 | 40 min | 56 min |
| D4 | 3 h 40 | 5 h 10 |
| D3 | 9 h 55 | 14 h |
| D2 | 18 h 45 | 27 h |
| **D1** | **31 h 40** (~13 jours) | **45 h 40** (~6 mois) |
| Victoires D4 / D3 / D2 / D1 | 63 / 69 / 72 / 74 % | 64 / 69 / 73 / 74 % |
| Gain par match (hors prime de montée) | médiane 3 600, max 4 600 | idem |

Contrôles : D1 atteinte dans toutes les parties (aucun blocage), aucun match au-dessus
de 5 000, solde loin du plafond. Point ouvert : en D1, une fois l'effectif au
maximum du marché, les FC Coins s'accumulent (~2,5 millions) ; de nouvelles
dépenses (installations, salaires) pourront le combler.

## Dernier rapport (30 parties par profil)

# Simulation de l'économie (30 parties par profil)

Départ : 2500 FC Coins · prime de match V/N/D : 400/200/100 · recrue : 1500 · délai entre matchs : 60 s
Coût total de tout le contenu (installations + 4 recrues) : 338000

## Joueur actif (sessions de 40 min, pause de 6 h, un match toutes les 75 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 7.5 min | 10 min | 7 | 1 |
| Montée en D5 | 40 min | 46.3 min | 33 | 1 |
| Montée en D4 | 221.3 min | 237.5 min | 183 | 6 |
| Montée en D3 | 595 min | 626.3 min | 491 | 15 |
| Montée en D2 | 1125 min | 1178.8 min | 929 | 29 |
| Montée en D1 | 1903.1 min | 1950 min | 1570.5 | 48 |
| Pitch 2 (2500) | 22.5 min | 25 min | 19 | 1 |
| Pitch 3 (7500) | 122.5 min | 160 min | 102 | 4 |
| Pitch 4 (16000) | 182.5 min | 221.3 min | 151 | 5 |
| Pitch 5 (32000) | 333.8 min | 365 min | 276 | 9 |
| Stands 2 (3000) | 36.3 min | 38.8 min | 30 | 1 |
| Stands 3 (8000) | 132.5 min | 170 min | 110 | 4 |
| Stands 4 (18000) | 195.6 min | 288.8 min | 161.5 | 5 |
| Stands 5 (36000) | 350.6 min | 381.3 min | 289.5 | 9 |
| Training 2 (2000) | 16.3 min | 17.5 min | 14 | 1 |
| Training 3 (6000) | 53.8 min | 57.5 min | 45 | 2 |
| Training 4 (14000) | 160 min | 197.5 min | 132 | 4 |
| Training 5 (28000) | 303.8 min | 335 min | 251 | 8 |
| Offices 2 (2500) | 30 min | 32.5 min | 25 | 1 |
| Offices 3 (7000) | 115 min | 152.5 min | 95 | 3 |
| Offices 4 (15000) | 170.6 min | 208.8 min | 141.5 | 5 |
| Offices 5 (30000) | 319.4 min | 350 min | 263.5 | 8 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 40 min | 45 min | 33 | 1 |
| LockerRoom 4 (9000) | 140.6 min | 177.5 min | 116.5 | 4 |
| LockerRoom 5 (18000) | 211.3 min | 302.5 min | 175 | 6 |
| Shop 2 (4000) | 45 min | 48.8 min | 38 | 2 |
| Shop 3 (10000) | 148.8 min | 186.3 min | 123 | 4 |
| Shop 4 (20000) | 236.9 min | 320 min | 195.5 | 6 |
| Shop 5 (38000) | 363.8 min | 396.3 min | 301 | 10 |
| Recrue 1 (1500) | 1.3 min | 1.3 min | 2 | 1 |
| Recrue 2 (1500) | 3.8 min | 5 min | 4 | 1 |
| Recrue 3 (1500) | 7.5 min | 8.8 min | 7 | 1 |
| Recrue 4 (1500) | 10 min | 11.3 min | 9 | 1 |
| Tout acheté | 363.8 min | 396.3 min | 301 | 10 |

D1 : médiane 31.7 h de jeu (90 % avant 32.5 h), soit ~13.3 jours au rythme du profil
Victoires par division : D7 66.1 % · D6 37.8 % · D5 65.2 % · D4 62.8 % · D3 69.1 % · D2 71.6 % · D1 74.3 %
Transferts : médiane 61.5 (dépense 2.572e+06 FC Coins)

Gain par match : médiane 3601, max 4599 · victoires : 68.4 % · énergie la plus basse : 90 · solde final médian : 2.57765e+06

## Joueur occasionnel (sessions de 15 min, pause de 24 h, un match toutes les 120 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 14 min | 16 min | 8 | 1 |
| Montée en D5 | 56 min | 70 min | 32.5 | 4.5 |
| Montée en D4 | 310 min | 344 min | 178 | 23 |
| Montée en D3 | 845 min | 882 min | 483.5 | 61 |
| Montée en D2 | 1623 min | 1666 min | 928 | 116.5 |
| Montée en D1 | 2736 min | 2788 min | 1564 | 196 |
| Pitch 2 (2500) | 32 min | 36 min | 19 | 3 |
| Pitch 3 (7500) | 185 min | 224 min | 106 | 13.5 |
| Pitch 4 (16000) | 270 min | 322 min | 155 | 20 |
| Pitch 5 (32000) | 474 min | 538 min | 271 | 34 |
| Stands 2 (3000) | 52 min | 56 min | 30 | 4 |
| Stands 3 (8000) | 198 min | 238 min | 113.5 | 14.5 |
| Stands 4 (18000) | 288 min | 342 min | 165 | 21 |
| Stands 5 (36000) | 497 min | 560 min | 284.5 | 36 |
| Training 2 (2000) | 24 min | 26 min | 14 | 2 |
| Training 3 (6000) | 78 min | 84 min | 45 | 6 |
| Training 4 (14000) | 236 min | 278 min | 135.5 | 17.5 |
| Training 5 (28000) | 428 min | 494 min | 245 | 31 |
| Offices 2 (2500) | 42 min | 46 min | 24.5 | 3.5 |
| Offices 3 (7000) | 172 min | 212 min | 99 | 13 |
| Offices 4 (15000) | 254 min | 294 min | 145.5 | 18.5 |
| Offices 5 (30000) | 451 min | 516 min | 258.5 | 33 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 56 min | 64 min | 33 | 5 |
| LockerRoom 4 (9000) | 209 min | 250 min | 120 | 15.5 |
| LockerRoom 5 (18000) | 308 min | 454 min | 176.5 | 22.5 |
| Shop 2 (4000) | 66 min | 70 min | 38 | 5 |
| Shop 3 (10000) | 221 min | 262 min | 127 | 16.5 |
| Shop 4 (20000) | 396 min | 474 min | 227 | 29 |
| Shop 5 (38000) | 517 min | 582 min | 295.5 | 37 |
| Recrue 1 (1500) | 2 min | 2 min | 2 | 1 |
| Recrue 2 (1500) | 6 min | 8 min | 4 | 1 |
| Recrue 3 (1500) | 12 min | 14 min | 7 | 1 |
| Recrue 4 (1500) | 14 min | 16 min | 9 | 2 |
| Tout acheté | 517 min | 582 min | 295.5 | 37 |

D1 : médiane 45.6 h de jeu (90 % avant 46.5 h), soit ~198 jours au rythme du profil
Victoires par division : D7 59 % · D6 38.8 % · D5 65.7 % · D4 64.2 % · D3 68.8 % · D2 72.9 % · D1 73.5 %
Transferts : médiane 60.5 (dépense 2.501e+06 FC Coins)

Gain par match : médiane 3602, max 4595 · victoires : 68.7 % · énergie la plus basse : 90 · solde final médian : 2.5037e+06

Aucune source de monnaie infinie ni blocage détecté.
