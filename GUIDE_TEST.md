# Tester le jeu (environ 31 minutes)

## 1. Récupérer le fichier du jeu

1. Clique sur ce lien : il télécharge toujours la **dernière version** construite
   (pas besoin d'être connecté) :
   https://nightly.link/diarran/Football-club-tycoon/workflows/build/main/FootballClubTycoon-place.zip
   Si le lien ne marche pas : sur GitHub, onglet **Actions** > **Construire la place** >
   le dernier passage avec une coche verte > en bas, **Artifacts** > `FootballClubTycoon-place`
   (https://github.com/diarran/Football-club-tycoon/actions/workflows/build.yml?query=branch%3Amain).
2. Un fichier `.zip` se télécharge. Double-clique dessus pour l'ouvrir : à l'intérieur se
   trouve `FootballClubTycoon.rbxlx`.

## 2. Ouvrir le jeu dans Roblox Studio

1. Installe Roblox Studio si besoin (https://create.roblox.com) et connecte-toi.
2. Double-clique sur `FootballClubTycoon.rbxlx` (ou, dans Studio : **Fichier** > **Ouvrir
   depuis un fichier**).
3. Ouvre la fenêtre des messages : onglet **Affichage** (View) > **Sortie** (Output).
   Les lignes en **rouge** sont des erreurs : copie-les si tu en vois.

## 3. Jouer seul

Clique sur **Play** (ou touche F5). Pour arrêter : **Stop** (Maj + F5).
Le message « Mode test : la progression n'est pas sauvegardée » est normal ici.

## 4. Jouer à 2

Onglet **Test** > dans la zone **Clients and Servers**, choisis **Local Server** et
**2 Players**, puis **Start**. Trois fenêtres s'ouvrent : le serveur et deux joueurs.
Joue dans les fenêtres des joueurs. Pour finir : **Cleanup** (ou Stop) dans la fenêtre
principale.

## 5. Ce qu'il faut vérifier (18 points, environ 31 minutes)

Note ✅ ou ❌ pour chaque point. Si c'est ❌, fais une capture d'écran.
Pendant tout le test, la fenêtre **Sortie** ne doit montrer **aucune ligne rouge**.

**Seul (Play)**

1. **Base** (déjà validée le 26/11) : ton personnage apparaît sur ton terrain, le haut
   de l'écran montre l'écusson, le club, **D7** et **2 500 FC** ; le bouton **Club**
   ouvre le menu.
2. **Début de partie** : les **8 onglets** sont visibles, mais **Gestion**,
   **Classement** et **Prestige** ont un cadenas 🔒 (un clic explique quand ils
   s'ouvrent). Le bouton **Club** et l'onglet à utiliser sont en **doré**. Suis le
   bandeau vert du tutoriel jusqu'au bout : un message annonce « Nouvel onglet
   débloqué : Gestion », puis le bandeau montre **Objectif de départ 1/6**. Fais une
   2e amélioration dans **Stade** : le bandeau devient doré, **Récupérer +250 FC**
   ajoute 250 FC et passe à l'objectif 2/6.
   Pour la suite du test, active ton **code admin** (point 8) : tous les onglets
   s'ouvrent d'un coup ; chacun s'ouvre sans erreur.
3. **Accueil** : cartes **Cadeau du jour**, **Missions du jour**, **Saison de la
   semaine** et **Soutiens le jeu**. La carte **Événement de la semaine** montre le
   thème, tes points et 3 étapes ; sous le solde (en haut à gauche), une ligne verte
   affiche l'événement et **« fin dans … »**. Après un match, le résultat indique
   **« +… points d'événement »**.
4. **Match en 3D** : lance un match dans **Matchs** ; il se joue sur ton terrain, les
   buts font jaillir des **confettis** avec un son. À la fin, la fenêtre de résultat
   s'affiche et la mission « Joue … matchs » avance.
4 bis. **Tactique** : en haut de **Matchs**, **5 boutons** (Équilibrée, Offensive,
   Défensive, Contre-attaque, Pressing) et une phrase dit ce que bat le style choisi.
   Sous chaque adversaire, une ligne **« Style de jeu : … »** et un conseil. Clique le
   style conseillé : la ligne devient verte **« ✓ Avantage tactique »** ; un style
   contré la rend rouge **« ✗ Attention »**. Joue avec l'avantage : le match 3D
   commence par **« … contre … : coup d'envoi ! »** et le résultat affiche
   **« Avantage tactique : … »**.
4 ter. **Coupe nationale** : dans **Matchs**, la carte **🏆 Coupe nationale** montre
   « 16es de finale : contre … (Division …, note …) », le style de l'adversaire et la
   prime. Clique **Lancer le match de coupe** : le match se joue en 3D, puis le
   résultat dit **« Qualifié ! +… FC Coins »** (ou « Éliminé… »). La carte affiche
   alors le tour joué (✅ ou ❌) et **« Prochain tour possible dans 20 min »** ;
   l'énergie des joueurs et les points de division n'ont pas bougé.
4 quater. **Réputation et presse** : dans **Accueil**, la carte **Réputation du club**
   montre « … / 100 · Club local » avec une barre dorée. Gagne un match par 3 buts
   d'écart ou plus (ou monte de division) : le résultat affiche **« Réputation : +… »**
   et **« Les journalistes veulent te parler ! »**. Clique **Continuer** : la fenêtre
   **🎤 Conférence de presse** pose une question avec **3 réponses** (humble,
   ambitieuse, provocante) et **Ne pas répondre**. Choisis une réponse : un message
   vert confirme l'effet, et la carte de l'accueil affiche le bonus (ex. « 🔥 Les fans
   sont chauds… »). Rien n'est jamais perdu en argent.
5. **Gestion** : **Embaucher** le Médecin (2 500 FC) fait baisser le solde ; **Signer
   le contrat** d'un sponsor le fait passer dans « Les contrats de sponsoring ».
6. **Prestige** : la salle des trophées et les objets de personnalisation s'affichent
   (la boutique Robux reste cachée tant que ses numéros ne sont pas renseignés).
7. **Classement** : la carte **Classement mondial** et ses 3 boutons (Cette semaine,
   Meilleurs clubs, Trophées) ; dans Studio elle dit « Mode test : seulement les clubs
   de ce serveur ». Sur la place, le grand panneau **CLASSEMENT MONDIAL** change de
   tableau toutes les 12 secondes.
8. **Paramètres** : **English** traduit tout le menu (aucun mot français), puis remets
   **Français**. **Volume du son** sur **Muet** coupe les sons. La carte **Code admin**
   est là (tu es le créateur) : ton code active l'argent illimité (**∞ FC**), le même
   code le désactive et rend ton solde.
8 bis. **Météo et jour/nuit** : en haut de **Matchs**, la carte **« Météo au stade : … »**
   dit le temps du moment (☀️ Beau temps, ☁️ Nuageux, 🌧️ Pluie, 💨 Vent ; ❄️ Neige
   seulement de décembre à février), le style avantagé (ex. « Pluie : toute équipe qui
   joue Défensive gagne +1 ») et la météo suivante. Le ciel suit : pluie qui tombe,
   léger brouillard. Une journée dure **20 minutes** : à la nuit, les **projecteurs**
   du stade et les lampadaires s'allument. Un match de nuit ou sous la pluie commence
   par « … · 🌧️ Pluie · 🌙 Nuit » et le résultat l'affiche. Dans **Paramètres**,
   **Effets météo** sur **Désactivé** fait disparaître la pluie et le brouillard
   (le jour/nuit reste).
9. **Téléphone** : onglet **Test** > **Device**, choisis un téléphone : les onglets
   passent sur **2 rangées de 4**, tous lisibles, et le contenu reste dessous.
9 bis. **Entraînement** : dans **Effectif**, clique **Entraîner** sous un joueur : le
   solde baisse, sa ligne **XP** augmente et le bouton passe en **Repos**. Recrute
   jusqu'à 6 joueurs : **Faire jouer** sur un remplaçant le rend **Titulaire** à la
   place d'un autre (il y a toujours 5 titulaires).
9 ter. **Blessures et cartons** : dans **Effectif**, la carte de composition explique
   « Blessures et cartons ». Joue une dizaine de matchs d'affilée (les joueurs se
   fatiguent) : de temps en temps, la fenêtre de résultat montre une partie
   **Infirmerie** (🤕 blessé quelques minutes, 🟨 carton jaune, 🟥 carton rouge).
   Dans **Effectif**, ce joueur est marqué **Indisponible** avec le temps de retour,
   et un remplaçant joue à sa place. Après le match suivant, « ✅ … a purgé sa
   suspension » s'affiche pour un joueur suspendu.

**À 2 joueurs (Local Server, 2 Players)**

10. **Deux clubs** : chaque joueur a son terrain et voit l'autre dans **Classement**.
11. **Défi** : dans **Matchs**, le joueur 1 clique **Défier** ; le joueur 2 accepte :
    les deux voient le résultat.
12. **Visiteur** : le joueur 2 va sur le terrain du joueur 1, qui lance un match : le
    joueur 2 voit le match se jouer, sans que sa caméra bouge.
13. **Tournoi** : environ **3 minutes** après le Start, inscris les deux joueurs dans
    **Matchs** ; un vainqueur est annoncé.

**Dans le jeu publié (sauvegarde active)**

14. **Retour au jeu** : joue un peu, quitte, attends **5 minutes** et reviens : ton
    solde, ton staff et tes contrats sont toujours là, et une fenêtre **« Pendant ton
    absence… »** indique ce que ton club a rapporté.

Envoie ensuite ta liste (✅ / ❌ + captures + lignes rouges) dans le projet : on corrige.
