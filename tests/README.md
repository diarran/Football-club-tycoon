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
| `27_achievements` | succès : 20 succès calculés à partir du profil, prime versée une seule fois, anciens profils servis tout de suite, succès gardé après une baisse, profil abîmé réparé, badges Roblox seulement avec un numéro (une fois, nouvel essai après échec, déjà possédé), accueil + Prestige + bouton Récupérer |
| `18_friends` | clubs entre amis : amis Roblox repérés par le serveur, match amical sans mise (petit bonus limité par jour), primes d'invitation (une fois par ami, plafonnées, versées même si l'inviteur était absent), valeurs invalides refusées, carte Amis et bouton Match amical |
| `23_branding` | vraie identité visuelle : numéros d'images collés sous toutes les formes, version dessinée tant que l'image manque ou n'est pas chargée, logo et écusson du HUD, écussons du portique et du toit des bureaux, lien du jeu publié copiable dans la carte Amis |
| `24_tactics` | tactiques : 5 styles en pierre-feuille-ciseaux, style fixe des clubs fictifs, avantage dans la simulation, anciennes sauvegardes, replay 3D selon les styles, boutons et conseils de l'onglet Matchs |
| `26_weather` | météo et jour/nuit : même météo pour le serveur et le client, neige seulement en hiver, +1 léger au style avantagé (pour les deux équipes), projecteurs allumés la nuit, pluie/neige légères, option Effets météo des Paramètres, carte de l'onglet Matchs, résultat et replay |
| `28_reputation` | réputation du club : plancher (division, tribunes) et plafond (division), gains après les matchs, la coupe et les tournois, conférences de presse (sujets, délai entre deux, priorité de la montée, rien pendant le tutoriel, question qui expire), 3 réponses aux effets doux (énergie, billetterie, sponsors) sans perte d’argent, valeurs invalides refusées, anciens profils, textes FR/EN, carte de l’accueil et fenêtre de presse |
| `25_national_cup` | Coupe nationale : une édition par saison, 5 tours contre des clubs fictifs d'une division de plus à chaque tour, exploit (+50 %) contre plus fort, un tour toutes les 20 min, prime unique versée par le serveur, match neutre (ni énergie ni points), tirs au but, trophée, élimination puis nouvelle édition le lundi, anciens profils, carte de l'onglet Matchs |
| `22_onboarding` | 10 premières minutes : onglets Gestion / Classement / Prestige débloqués petit à petit (cadenas, explication, annonce), onglet et bouton mis en avant, 6 objectifs de départ (récompense vérifiée par le serveur, une seule fois, gardée après déconnexion), anciens profils |
| `25_injuries` | blessures et cartons : risque rare (plus fort si fatigué), durée courte en minutes réelles, médecin qui raccourcit les blessures, blessés et suspendus remplacés automatiquement puis de retour, suspension purgée en un match, jamais de blocage (tous blessés / tous suspendus), refus côté serveur, anciens profils, onglet Effectif et infirmerie du résultat |
| `26_identity` | identité du club : 14 couleurs, motifs (gratuits, par division, en FC Coins avec débit unique, ou via une tenue Prestige), écusson 1 à 6, tout validé par le serveur ; terrain, tribunes et drapeaux repeints, tenue des 22 joueurs du replay, liste des clubs vue par les autres ; objets Prestige prioritaires puis retirés au nouveau choix ; aucun effet sportif ; sauvegarde, anciens profils, valeurs abîmées ; écran Prestige et replay du vrai client |
| `19_leaderboard` | classement mondial : scores calculés par le serveur (semaine, niveau du club, trophées), écriture seulement si le score change et au plus toutes les 2 min, lecture du top 50 et noms en une requête, budget DataStore bas ou panne sans casse, départ du joueur, nouvelle semaine dans un nouveau tableau, panneau 3D de la place, onglet Classement ; `19_leaderboard_studio` : sans DataStore, classement de ce serveur |
| `20_soak` | endurance : 6 joueurs pendant 30 min avec toutes les nouveautés (matchs, défis, staff, sponsors), minuit et nouvelle saison en pleine partie, départ et retour, fermeture du serveur ; écritures DataStore et lectures du classement bien sous les limites Roblox |
| `31_stability_morning` | stabilité après les nouveautés du 27/11 (#24 à #30) : 6 joueurs pendant 45 min qui mélangent championnat, tactiques, coupe, entraînement, composition, blessures et suspensions forcées (aucun titulaire indisponible, profils sous 60 Ko, écritures DataStore sous les limites) ; coupe jamais perdue sur tapis vert quand tout l'effectif est blessé ; anciens profils d'avant #24 et valeurs abîmées ; fenêtre de résultat qui défile sur téléphone ; onglet Matchs avec le championnat avant la coupe |
| `32_performance` | performances téléphone : 6 terrains au maximum (installations niveau 5 + 10 bâtiments du mode Création niveau 3) sous 2 400 Parts, 1 100 ombres et 30 lumières chacun ; décor allégé (pas de contact, pas de rayons sur ce qu'on traverse, détails sans collision ni ombre, néon/verre/petites pièces sans ombre) ; sièges, pièces mobiles et invites intacts ; projecteurs lointains éteints la nuit côté client |
| `20_migration` | profils enregistrés avant les PR #15 à #22 : progression gardée, nouveaux champs ajoutés, pas de revenus inventés, tous les onglets s'affichent |
| `17_staff_sponsors` | staff du club (embauche validée par le serveur, niveaux, effets modérés), sponsors (offres renouvelées, 1 puis 2 contrats, prime par match, bonus d'objectif unique, fin de contrat), ancien profil migré, onglet Gestion |
| `18_ambiance` | ambiance sonore : sons de Studio d'abord puis sons intégrés à Roblox (muet si rien ne charge), public plus fort et chants dans un grand stade, confettis et son à chaque but du replay, clic des boutons, volume par paliers / muet / musique dans les Paramètres |
| `12_challenges_tournament` | défis entre clubs (mises plafonnées, refus, expiration, anti-spam, seul le club défié répond, 200 défis sans création de monnaie), tournoi du serveur à 2 joueurs (inscriptions, 8 clubs, forfaits, récompenses bornées, événement « tournoi gagné »), écran Matchs |
| `15_replay` | replay 3D des matchs : chronologie identique au score du serveur (buts, minutes, buteurs), 0 à 14 buts entre 30 et 60 s, aucun effet sur le tirage ni les récompenses, visiteurs prévenus, client : replay jusqu'au bout, « Passer », avance rapide, public selon les tribunes |
| `11_academy_vip` | centre de formation (jeunes repérés hors ligne, signature, libération, progression), espace VIP, anciens profils |
| `12_prestige` | personnalisation du club (achat validé par le serveur, conditions de division et de titres, porter/retirer, terrain 3D), salle des trophées (montées, titres de D1, records, tournois), sauvegarde, anciens profils, écran Prestige |
| `21_events` | événements de la semaine : un thème par semaine (4 en rotation), bonus de match calculé par le serveur et compris dans le total, points d'événement, 3 étapes récupérées une seule fois, objet d'événement gagné et porté mais jamais vendu, étapes oubliées versées le lundi suivant, Coupe du week-end (tournoi majoré + points le samedi et le dimanche), ancien profil, accueil, HUD et Prestige |
| `29_euro_cup` | Coupe d'Europe des clubs : D3 minimum, groupe de 8 clubs de vrais joueurs d'autres serveurs (les plus proches en force, photos abîmées ou de division trop basse ignorées), clubs fictifs en complément, calendrier complet en 7 journées, un match toutes les 30 min, primes exactes, match neutre, demi-finale 1er-4e, tirs au but, finale, trophée, élimination puis nouvelle édition le lundi, réservoir MemoryStore en panne, une lecture par minute, anciens profils, carte de l'onglet Matchs |
| `28_scenery` | rendu semi-réaliste : aménagement de chaque terrain (haies, arbres, lampadaires, drapeaux, parking), finitions des bâtiments (cadres de fenêtres, angles, acrotères, marquise, façade du stade), murs en vrais matériaux, budget de 1 400 Parts au niveau max dont au moins 20 % de détails masquables, option « Détails du décor » côté client (masque pour ce joueur seulement puis réaffiche) |
| `30_campus` | mode Création : 12 parcelles à débloquer (division + prix serveur), 5 bâtiments à 3 niveaux (e-sport, musée, bureau présidentiel, récupération, place des champions), construire / améliorer / tourner / déplacer vérifiés par le serveur, bonus appliqués aux matchs, sponsors, énergie et blessures, anciens profils réparés, onglet Création côté client |
| `16_daily` | cadeau du jour (série de 7 jours, jour manqué, minuit en ligne, pas de doublon), missions du jour (vraies actions, prime unique, mêmes missions après reconnexion, faisables), revenus hors ligne (plafond 8 h, horloge incohérente), saisons (points, classement, prime, trophée, saison sans match), anciens profils, écran d'accueil et fenêtre « Pendant ton absence… » |

## Lancer les tests sur son ordinateur

```
LUAU_BIN=/chemin/vers/luau node tests/run-tests.js          # tous les tests
LUAU_BIN=/chemin/vers/luau node tests/run-tests.js match    # seulement 05_match
```
