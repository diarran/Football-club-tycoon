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

| Mesure (médiane, 30 parties, avec centre de formation et VIP) | Joueur actif | Joueur occasionnel |
| --- | --- | --- |
| D5 | 39 min | 56 min |
| D4 | 3 h 40 | 5 h 20 |
| D3 | 10 h | 14 h |
| D2 | 19 h | 27 h |
| **D1** | **31 h 40** (~13 jours) | **45 h 50** (~6 mois) |
| Victoires D4 / D3 / D2 / D1 | 63 / 68 / 72 / 70 % | 65 / 68 / 72 / 71 % |
| Gain par match (hors prime de montée) | médiane 4 490, max 5 611 | idem |

Contrôles : D1 atteinte dans toutes les parties (aucun blocage), solde loin du
plafond. Le seuil d'alerte de 5 000 par match s'applique maintenant **hors bonus
de division** (prime de match ×1 à ×3, voulue et plafonnée) : 4 811 au plus.
Point ouvert : en D1, une fois l'effectif au maximum du marché, les FC Coins
s'accumulent (~3,5 millions) ; de nouvelles dépenses (salaires, entretien)
pourront le combler.

## Dernier rapport (30 parties par profil)

# Simulation de l'économie (30 parties par profil)

Départ : 2500 FC Coins · prime de match V/N/D : 400/200/100 · recrue : 1500 · délai entre matchs : 60 s
Coût total de tout le contenu (installations + 4 recrues) : 491500

## Joueur actif (sessions de 40 min, pause de 6 h, un match toutes les 75 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 8.8 min | 11.3 min | 8 | 1 |
| Montée en D5 | 38.8 min | 50 min | 32 | 1 |
| Montée en D4 | 220.6 min | 238.8 min | 182.5 | 6 |
| Montée en D3 | 583.8 min | 613.8 min | 482 | 15 |
| Montée en D2 | 1131.3 min | 1160 min | 934 | 29 |
| Montée en D1 | 1898.8 min | 1945 min | 1567 | 48 |
| Pitch 2 (2500) | 22.5 min | 25 min | 19 | 1 |
| Pitch 3 (7500) | 127.5 min | 148.8 min | 106 | 4 |
| Pitch 4 (16000) | 197.5 min | 216.3 min | 163 | 5 |
| Pitch 5 (32000) | 337.5 min | 368.8 min | 279 | 9 |
| Stands 2 (3000) | 35 min | 37.5 min | 29 | 1 |
| Stands 3 (8000) | 135.6 min | 157.5 min | 112.5 | 4 |
| Stands 4 (18000) | 207.5 min | 233.8 min | 172 | 6 |
| Stands 5 (36000) | 351.9 min | 383.8 min | 290.5 | 9 |
| Training 2 (2000) | 15.6 min | 17.5 min | 13.5 | 1 |
| Training 3 (6000) | 63.8 min | 67.5 min | 53 | 2 |
| Training 4 (14000) | 176.3 min | 197.5 min | 146 | 5 |
| Training 5 (28000) | 313.1 min | 343.8 min | 258.5 | 8 |
| Offices 2 (2500) | 28.8 min | 31.3 min | 24 | 1 |
| Offices 3 (7000) | 120 min | 141.3 min | 100 | 4 |
| Offices 4 (15000) | 187.5 min | 206.3 min | 155 | 5 |
| Offices 5 (30000) | 325 min | 357.5 min | 269 | 9 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 42.5 min | 48.8 min | 36 | 2 |
| LockerRoom 4 (9000) | 143.1 min | 162.5 min | 118.5 | 4 |
| LockerRoom 5 (18000) | 221.9 min | 286.3 min | 183.5 | 6 |
| Shop 2 (4000) | 48.8 min | 51.3 min | 41 | 2 |
| Shop 3 (10000) | 158.8 min | 178.8 min | 131 | 4 |
| Shop 4 (20000) | 289.4 min | 321.3 min | 239.5 | 8 |
| Shop 5 (38000) | 374.4 min | 406.3 min | 309.5 | 10 |
| Academy 2 (3500) | 38.8 min | 42.5 min | 32 | 1 |
| Academy 3 (9000) | 150.6 min | 170 min | 124.5 | 4 |
| Academy 4 (19000) | 280 min | 312.5 min | 231 | 7 |
| Academy 5 (36000) | 362.5 min | 395 min | 300 | 10 |
| VIP 2 (5000) | 56.3 min | 58.8 min | 47 | 2 |
| VIP 3 (12000) | 166.3 min | 187.5 min | 138 | 5 |
| VIP 4 (24000) | 300.6 min | 332.5 min | 248.5 | 8 |
| VIP 5 (45000) | 388.1 min | 420 min | 320.5 | 10 |
| Recrue 1 (1500) | 0 min | 1.3 min | 1 | 1 |
| Recrue 2 (1500) | 3.8 min | 5 min | 4 | 1 |
| Recrue 3 (1500) | 7.5 min | 8.8 min | 7 | 1 |
| Recrue 4 (1500) | 10 min | 11.3 min | 9 | 1 |
| Tout acheté | 388.1 min | 420 min | 320.5 | 10 |

D1 : médiane 31.6 h de jeu (90 % avant 32.4 h), soit ~13.3 jours au rythme du profil
Victoires par division : D7 57 % · D6 41 % · D5 65.1 % · D4 65 % · D3 68.5 % · D2 72.1 % · D1 71.9 %
Transferts : médiane 61 (dépense 2.576e+06 FC Coins)

Gain par match : médiane 4490, max 5611 · victoires : 68.5 % · énergie la plus basse : 90 · solde final médian : 3.56281e+06
Gain par match hors bonus de division : max 4811 (seuil d'alerte 5 000)

## Joueur occasionnel (sessions de 15 min, pause de 24 h, un match toutes les 120 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 13 min | 14 min | 7.5 | 1 |
| Montée en D5 | 56 min | 68 min | 32 | 4 |
| Montée en D4 | 312 min | 342 min | 179 | 23 |
| Montée en D3 | 841 min | 878 min | 481.5 | 61 |
| Montée en D2 | 1625 min | 1650 min | 929 | 116.5 |
| Montée en D1 | 2746 min | 2794 min | 1570 | 197 |
| Pitch 2 (2500) | 32 min | 34 min | 19 | 3 |
| Pitch 3 (7500) | 180 min | 208 min | 103 | 13 |
| Pitch 4 (16000) | 280 min | 306 min | 160 | 20 |
| Pitch 5 (32000) | 490 min | 524 min | 280.5 | 35.5 |
| Stands 2 (3000) | 50 min | 54 min | 29 | 4 |
| Stands 3 (8000) | 191 min | 220 min | 109.5 | 14 |
| Stands 4 (18000) | 294 min | 328 min | 169 | 22 |
| Stands 5 (36000) | 511 min | 546 min | 292.5 | 37 |
| Training 2 (2000) | 24 min | 24 min | 14 | 2 |
| Training 3 (6000) | 92 min | 96 min | 53 | 7 |
| Training 4 (14000) | 250 min | 278 min | 143 | 18 |
| Training 5 (28000) | 455 min | 488 min | 260.5 | 33 |
| Offices 2 (2500) | 42 min | 44 min | 24 | 3 |
| Offices 3 (7000) | 168 min | 196 min | 96.5 | 12.5 |
| Offices 4 (15000) | 265 min | 292 min | 151.5 | 19 |
| Offices 5 (30000) | 473 min | 506 min | 270.5 | 34 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 64 min | 68 min | 37 | 5 |
| LockerRoom 4 (9000) | 201 min | 230 min | 115.5 | 15 |
| LockerRoom 5 (18000) | 311 min | 400 min | 178.5 | 23 |
| Shop 2 (4000) | 70 min | 76 min | 41 | 6 |
| Shop 3 (10000) | 223 min | 252 min | 127.5 | 16 |
| Shop 4 (20000) | 417 min | 456 min | 239 | 30.5 |
| Shop 5 (38000) | 544 min | 576 min | 311.5 | 39.5 |
| Academy 2 (3500) | 56 min | 60 min | 32 | 4 |
| Academy 3 (9000) | 211 min | 240 min | 121.5 | 16 |
| Academy 4 (19000) | 377 min | 442 min | 216 | 27.5 |
| Academy 5 (36000) | 527 min | 560 min | 301.5 | 38 |
| VIP 2 (5000) | 82 min | 84 min | 47 | 6 |
| VIP 3 (12000) | 237 min | 264 min | 135.5 | 17 |
| VIP 4 (24000) | 437 min | 472 min | 250.5 | 32 |
| VIP 5 (45000) | 562 min | 596 min | 322 | 41 |
| Recrue 1 (1500) | 0 min | 2 min | 1 | 1 |
| Recrue 2 (1500) | 6 min | 8 min | 4 | 1 |
| Recrue 3 (1500) | 12 min | 14 min | 7 | 1 |
| Recrue 4 (1500) | 14 min | 14 min | 9 | 2 |
| Tout acheté | 562 min | 596 min | 322 | 41 |

D1 : médiane 45.8 h de jeu (90 % avant 46.6 h), soit ~199.1 jours au rythme du profil
Victoires par division : D7 63.2 % · D6 42 % · D5 65.2 % · D4 64.8 % · D3 68.8 % · D2 72.3 % · D1 70.5 %
Transferts : médiane 59.5 (dépense 2.5695e+06 FC Coins)

Gain par match : médiane 4487, max 5597 · victoires : 68.7 % · énergie la plus basse : 90 · solde final médian : 3.53399e+06
Gain par match hors bonus de division : max 4811 (seuil d'alerte 5 000)

Aucune source de monnaie infinie ni blocage détecté.
