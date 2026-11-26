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

## Défis et tournoi du serveur (26/11/2026)

- **Défis** : aucune monnaie créée. Les deux clubs misent la même somme (0, 100, 250,
  500 ou 1 000 FC Coins), le gagnant prend le pot, un nul rembourse. Le test
  `12_challenges_tournament` joue 200 défis à 2 joueurs : la somme des deux soldes
  ne change jamais.
- **Tournoi du serveur** : toutes les 15 minutes, 8 clubs. Récompenses fixes
  (vainqueur 1 200, finaliste 600, demi 300, quart 100) × bonus de division, donc au
  plus 3 600 par tournoi en D1, et un seul tournoi à la fois : les gains sont bornés
  par le temps, pas par le nombre de clics.
- Simulation (le joueur s'inscrit à chaque tournoi ouvert pendant sa session) :
  joueur actif ≈ 2 300 FC Coins par heure de jeu grâce aux tournois, soit une part
  faible des revenus de match. « Tout acheté » passe de ~394 à ~374 min, la D1 de
  31,9 h à 31,5 h : le rythme reste quasiment le même. Le joueur occasionnel
  (15 min par jour) tombe rarement sur un tournoi. Aucune source anormale détectée.

## Dernier rapport (30 parties par profil)

# Simulation de l'économie (30 parties par profil)

Départ : 2500 FC Coins · prime de match V/N/D : 400/200/100 · recrue : 1500 · délai entre matchs : 60 s
Coût total de tout le contenu (installations + 4 recrues) : 491500

## Joueur actif (sessions de 40 min, pause de 6 h, un match toutes les 75 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 7.5 min | 11.3 min | 7 | 1 |
| Montée en D5 | 40.6 min | 46.3 min | 34 | 1.5 |
| Montée en D4 | 216.3 min | 232.5 min | 179 | 6 |
| Montée en D3 | 583.8 min | 613.8 min | 482 | 15 |
| Montée en D2 | 1120.6 min | 1153.8 min | 925 | 28.5 |
| Montée en D1 | 1888.1 min | 1923.8 min | 1558.5 | 48 |
| Pitch 2 (2500) | 21.9 min | 23.8 min | 18.5 | 1 |
| Pitch 3 (7500) | 121.9 min | 143.8 min | 101 | 3.5 |
| Pitch 4 (16000) | 187.5 min | 210 min | 155 | 5 |
| Pitch 5 (32000) | 323.8 min | 356.3 min | 268 | 9 |
| Stands 2 (3000) | 34.4 min | 36.3 min | 28 | 1 |
| Stands 3 (8000) | 128.8 min | 153.8 min | 107 | 4 |
| Stands 4 (18000) | 198.1 min | 228.8 min | 163.5 | 5 |
| Stands 5 (36000) | 338.1 min | 368.8 min | 279.5 | 9 |
| Training 2 (2000) | 15 min | 16.3 min | 13 | 1 |
| Training 3 (6000) | 63.1 min | 66.3 min | 52.5 | 2 |
| Training 4 (14000) | 167.5 min | 192.5 min | 139 | 5 |
| Training 5 (28000) | 300 min | 331.3 min | 248 | 8 |
| Offices 2 (2500) | 28.8 min | 31.3 min | 24 | 1 |
| Offices 3 (7000) | 113.8 min | 136.3 min | 94 | 3 |
| Offices 4 (15000) | 177.5 min | 200 min | 147 | 5 |
| Offices 5 (30000) | 312.5 min | 343.8 min | 258 | 8 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 42.5 min | 46.3 min | 36 | 2 |
| LockerRoom 4 (9000) | 135.6 min | 160 min | 112.5 | 4 |
| LockerRoom 5 (18000) | 211.9 min | 290 min | 175.5 | 6 |
| Shop 2 (4000) | 48.8 min | 51.3 min | 41 | 2 |
| Shop 3 (10000) | 150.6 min | 173.8 min | 124.5 | 4 |
| Shop 4 (20000) | 268.8 min | 308.8 min | 222 | 7 |
| Shop 5 (38000) | 360.6 min | 392.5 min | 298 | 9.5 |
| Academy 2 (3500) | 39.4 min | 41.3 min | 32.5 | 1 |
| Academy 3 (9000) | 142.5 min | 166.3 min | 118 | 4 |
| Academy 4 (19000) | 245.6 min | 298.8 min | 203.5 | 7 |
| Academy 5 (36000) | 350 min | 380 min | 289 | 9 |
| VIP 2 (5000) | 55 min | 58.8 min | 46 | 2 |
| VIP 3 (12000) | 158.8 min | 182.5 min | 131.5 | 4.5 |
| VIP 4 (24000) | 286.9 min | 320 min | 237.5 | 8 |
| VIP 5 (45000) | 373.8 min | 405 min | 309 | 10 |
| Recrue 1 (1500) | 0 min | 1.3 min | 1 | 1 |
| Recrue 2 (1500) | 3.8 min | 5 min | 4 | 1 |
| Recrue 3 (1500) | 7.5 min | 8.8 min | 7 | 1 |
| Recrue 4 (1500) | 10 min | 11.3 min | 9 | 1 |
| Tout acheté | 373.8 min | 405 min | 309 | 10 |

D1 : médiane 31.5 h de jeu (90 % avant 32.1 h), soit ~13.3 jours au rythme du profil
Victoires par division : D7 64.7 % · D6 37.4 % · D5 67.3 % · D4 64.4 % · D3 68.8 % · D2 73.4 % · D1 73.2 %
Transferts : médiane 59.5 (dépense 2.4445e+06 FC Coins)

Gain par match : médiane 4497, max 5608 · victoires : 69.2 % · énergie la plus basse : 90 · solde final médian : 3.79482e+06
Tournoi du serveur : 2861 récompenses · médiane 540 · max 3600 (plafond 3600) · 2304.8 FC Coins par heure de jeu (médiane)
Gain par match hors bonus de division : max 4811 (seuil d'alerte 5 000)

## Joueur occasionnel (sessions de 15 min, pause de 24 h, un match toutes les 120 s)

| Étape | Temps de jeu (médiane) | 90 % des joueurs avant | Matchs | Session n° |
| --- | --- | --- | --- | --- |
| Premier achat | 0 min | 0 min | 0 | 1 |
| Montée en D6 | 14 min | 16 min | 8 | 1 |
| Montée en D5 | 57 min | 66 min | 33.5 | 5 |
| Montée en D4 | 319 min | 350 min | 182.5 | 23 |
| Montée en D3 | 853 min | 914 min | 488 | 61.5 |
| Montée en D2 | 1628 min | 1700 min | 931 | 117 |
| Montée en D1 | 2749 min | 2814 min | 1571.5 | 197 |
| Pitch 2 (2500) | 32 min | 36 min | 19 | 3 |
| Pitch 3 (7500) | 189 min | 236 min | 108.5 | 14 |
| Pitch 4 (16000) | 287 min | 336 min | 164.5 | 21 |
| Pitch 5 (32000) | 480 min | 548 min | 275 | 35 |
| Stands 2 (3000) | 52 min | 54 min | 30 | 4 |
| Stands 3 (8000) | 200 min | 246 min | 115 | 15 |
| Stands 4 (18000) | 303 min | 350 min | 173.5 | 22 |
| Stands 5 (36000) | 501 min | 570 min | 286.5 | 36 |
| Training 2 (2000) | 24 min | 26 min | 14 | 2 |
| Training 3 (6000) | 94 min | 98 min | 54 | 7 |
| Training 4 (14000) | 259 min | 304 min | 148.5 | 19 |
| Training 5 (28000) | 444 min | 514 min | 254 | 32 |
| Offices 2 (2500) | 42 min | 44 min | 24 | 3 |
| Offices 3 (7000) | 178 min | 224 min | 102 | 13 |
| Offices 4 (15000) | 273 min | 320 min | 156.5 | 20 |
| Offices 5 (30000) | 462 min | 532 min | 264.5 | 33.5 |
| LockerRoom 2 (1500) | 0 min | 0 min | 0 | 1 |
| LockerRoom 3 (4000) | 64 min | 66 min | 37 | 5 |
| LockerRoom 4 (9000) | 210 min | 256 min | 121 | 16 |
| LockerRoom 5 (18000) | 322 min | 452 min | 184.5 | 23.5 |
| Shop 2 (4000) | 72 min | 76 min | 42 | 6 |
| Shop 3 (10000) | 233 min | 278 min | 133.5 | 17 |
| Shop 4 (20000) | 412 min | 480 min | 236 | 30 |
| Shop 5 (38000) | 533 min | 602 min | 305.5 | 39 |
| Academy 2 (3500) | 57 min | 60 min | 33.5 | 5 |
| Academy 3 (9000) | 221 min | 266 min | 126.5 | 16 |
| Academy 4 (19000) | 393 min | 466 min | 225.5 | 29 |
| Academy 5 (36000) | 517 min | 586 min | 295.5 | 37 |
| VIP 2 (5000) | 84 min | 86 min | 48 | 6 |
| VIP 3 (12000) | 245 min | 290 min | 140.5 | 18 |
| VIP 4 (24000) | 428 min | 496 min | 245 | 31 |
| VIP 5 (45000) | 552 min | 624 min | 316 | 40 |
| Recrue 1 (1500) | 2 min | 2 min | 2 | 1 |
| Recrue 2 (1500) | 6 min | 8 min | 4 | 1 |
| Recrue 3 (1500) | 12 min | 14 min | 7 | 1 |
| Recrue 4 (1500) | 14 min | 16 min | 9 | 2 |
| Tout acheté | 552 min | 624 min | 316 | 40 |

D1 : médiane 45.8 h de jeu (90 % avant 46.9 h), soit ~199.1 jours au rythme du profil
Victoires par division : D7 58.6 % · D6 39.4 % · D5 64.6 % · D4 64 % · D3 68.7 % · D2 72 % · D1 72.2 %
Transferts : médiane 62.5 (dépense 2.502e+06 FC Coins)

Gain par match : médiane 4486, max 5597 · victoires : 68.2 % · énergie la plus basse : 90 · solde final médian : 3.51488e+06
Tournoi du serveur : 2 récompenses · médiane 200 · max 300 (plafond 3600) · 0 FC Coins par heure de jeu (médiane)
Gain par match hors bonus de division : max 4811 (seuil d'alerte 5 000)

Aucune source de monnaie infinie ni blocage détecté.

## Fin de partie : personnalisation et salle des trophées (26/11/2026)

Problème relevé par le simulateur : en D1 avec l'équipe au maximum, les FC Coins
s'accumulaient (solde médian ~3,7 millions) sans rien à acheter.

Nouvel onglet **Prestige** (`src/shared/Cosmetics.lua`, `CosmeticService`) :
29 objets purement visuels (document de conception, section 9 : aucun avantage
sportif), achetés en FC Coins et visibles par tous les visiteurs du terrain.

| Catégorie | Objets | Prix | Débloqués |
| --- | --- | --- | --- |
| Couleurs du club | 6 palettes | 25 000 → 900 000 | D5 → 2 titres de D1 |
| Éclairage du stade | 5 couleurs de projecteurs | 40 000 → 1 600 000 | D4 → 6 titres |
| Statue devant le stade | 6 statues | 60 000 → 2 500 000 | D4 → 10 titres |
| Tenue fictive | 6 maillots | 30 000 → 2 000 000 | D5 → 8 titres |
| Décorations | drapeaux, fleurs, palmiers, fontaine, arche, allée des étoiles | 20 000 → 1 500 000 | D6 → 5 titres |

Total du catalogue : ~17,6 millions de FC Coins.

**Salle des trophées** (`src/shared/Trophies.lua`) : pavillon vitré toujours présent
sur le terrain. Une coupe par montée (D6 → D1), par titre de champion de D1 et par
record (victoires, matchs, buts, défis et tournois gagnés). La D1 n'ayant pas de
montée, chaque tranche de 300 points en D1 donne un **titre de champion** et les
points repartent de zéro. Les titres débloquent les objets les plus prestigieux,
ce qui étale la fin de partie même pour un joueur qui a déjà beaucoup de pièces.
Aucun trophée ne rapporte de FC Coins.

Simulateur : une fois en D1 avec tout acheté, le joueur type continue et achète
la personnalisation, la moins chère d'abord. Alerte en CI si tout est acheté
moins de 15 h de jeu après la D1.

## Retour quotidien : cadeau, missions, hors ligne, saisons (26/11/2026)

Règles et montants : `src/shared/Daily.lua` (service : `DailyService`). Tout est
calculé par le serveur avec son horloge (`os.time()`, UTC), le client affiche seulement.

| Mécanique | Règle | Montant (×échelle de division) |
| --- | --- | --- |
| Cadeau du jour | 1 fois par jour UTC, série sur 7 jours ; un jour manqué remet la série au jour 1 sans rien retirer | 300, 400, 500, 650, 800, 1 000, **2 000** |
| Missions du jour | 3 tirées par joueur (gagner, jouer, marquer, améliorer, recruter), seulement si faisables ; nouvelles à minuit UTC | 400 à 800 chacune |
| Revenus hors ligne | revenus des installations (sans prime de match) pour 0,5 match par heure d'absence, à partir de 5 min, **plafond 8 h** | ~4 matchs d'installations au maximum |
| Saison de 7 jours | du lundi au lundi ; points de saison = points de division ; classement contre les 5 clubs fictifs de la division | 5 000 / 3 000 / 2 000 / 1 200 / 700 / 400 selon la place, trophée si 1re place |

Échelle de division : D7 ×1, D6 ×1,3, D5 ×1,6, D4 ×2,5, D3 ×3,5, D2 ×5, D1 ×6,5
(suit à peu près le gain moyen d'un match). Le jour de création du club, le solde de
départ tient lieu de cadeau du jour 1.

Simulateur (10 parties par profil), avant → après :

| | Joueur actif | Joueur occasionnel |
| --- | --- | --- |
| Montée en D5 | 43,8 → 40,6 min | 54 → 52 min |
| D1 | 31,9 → 31,6 h | 46,1 → 44,9 h |
| Tout le stade acheté | 394 → 355 min | 574 → 314 min (41 → 23 sessions) |
| Part des gains venant du retour quotidien (arrivée + missions) | 9 % | 42 % |

Le joueur occasionnel est celui que ces mécaniques visent : revenir chaque jour
fait nettement avancer son stade, sans changer le rythme sportif (D5 ~40 min,
D1 ~32 h pour un joueur actif). Nouvelle alerte en CI si plus de la moitié des gains
vient sans jouer. Aucune source de monnaie infinie détectée.
