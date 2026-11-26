# Tester le jeu (environ 20 minutes)

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

## 5. Ce qu'il faut vérifier (16 points)

Note pour chaque point ✅ ou ❌. Si c'est ❌, fais une capture d'écran.

1. **Arrivée** : ton personnage apparaît sur ton terrain, près du portique au nom de
   ton club (pas sur la grande place, pas dans le vide).
2. **Écran** : en haut à gauche, l'écusson, le nom du club, la division **D7** et le
   solde **2 500 FC**.
3. **Menu** : le bouton **Club** ouvre le menu et la caméra montre ton club d'en haut.
   Les **7 onglets** sont visibles sur une ligne (Accueil, Stade, Effectif, Matchs,
   Classement, Prestige, Paramètres). Le **X** rouge ferme le menu.
4. **Tutoriel** : le bandeau en haut au centre change quand tu fais ce qu'il demande.
5. **Stade** : « Améliorer » les **Vestiaires** (1 500 FC) fait baisser le solde et le
   bâtiment change d'aspect. La liste montre aussi la Boutique, le Centre de formation
   et l'Espace VIP.
6. **Effectif** : « Recruter » ajoute un joueur. Plus bas, le **Centre de formation**
   affiche les jeunes repérés que tu peux signer. « Pas assez de FC » est normal au début : joue un match.
7. **Matchs** : lance un match. Le menu se ferme et le **match se joue en 3D** sur ton
   terrain : 22 joueurs aux couleurs des deux clubs, le ballon, du public dans les
   tribunes, le score et la minute en haut de l'écran. Les buts marqués sont les mêmes
   que ceux de la fenêtre de résultat. À la fin (moins d'une minute), la fenêtre de
   résultat s'affiche avec les FC gagnés (match, billetterie, sponsors…). Le compte à
   rebours avant le match suivant défile.
8. **Replay : boutons** : au match suivant, clique **Avance rapide ×3** (le match va
   3 fois plus vite), puis **Passer** : le replay s'arrête, la caméra revient sur ton
   personnage et la fenêtre de résultat s'affiche tout de suite.
9. **Prestige** : l'onglet montre la salle des trophées et les objets de personnalisation,
   avec la division requise pour ceux qui sont encore verrouillés.
10. **Paramètres** : passe la langue en **English** : tout le menu et les panneaux du
   terrain changent de langue. Remets **Français**.
11. **À 2 joueurs** (section 4) : chaque joueur a un terrain différent et voit l'autre
    club dans **Classement**. Dans **Matchs**, le joueur 1 clique **Défier** ; le
    joueur 2 reçoit le défi et l'accepte : les deux voient le résultat.
12. **Tournoi** (à 2) : environ **3 minutes** après le Start, un message annonce
    l'ouverture des inscriptions. Dans **Matchs**, les deux joueurs cliquent
    **S'inscrire** (1 minute pour le faire) ; les tours s'enchaînent et un vainqueur est annoncé.
13. **Téléphone et sortie** : onglet **Test** > **Device**, choisis un téléphone : les
    8 onglets et les boutons restent lisibles. Pendant tout le test, la fenêtre
    **Sortie** ne doit montrer aucune ligne **rouge** ni orange commençant par `[Main]`.
14. **Replay vu par un visiteur** (à 2) : le joueur 2 marche jusqu'au terrain du
    joueur 1, puis le joueur 1 lance un match. Le joueur 2 voit le match se jouer sur ce
    terrain et le tableau d'affichage au-dessus de la tribune du fond, sans que sa
    caméra bouge.
15. **Objectifs du jour** : dans **Accueil**, trois cartes s'affichent : **Cadeau du jour**
    (série jour 1 / 7), **Missions du jour** (3 missions avec leur prime) et **Saison de
    la semaine** (classement de 6 clubs). Lance un match : la mission « Joue … matchs »
    avance d'un cran ; une mission accomplie affiche un message vert avec sa prime.
16. **Retour au jeu** (seulement si la sauvegarde est active, voir le guide de
    publication) : quitte le jeu, attends au moins **5 minutes**, relance-le. Une fenêtre
    **« Pendant ton absence… »** indique ce que tes installations ont rapporté ; le
    lendemain, elle montre aussi le **cadeau du jour 2 / 7**.
17. **Gestion : staff** : ouvre l'onglet **Gestion**. Les 4 postes (Entraîneur,
    Recruteur, Médecin, Directeur commercial) sont vacants. Clique **Embaucher** sur
    le Médecin (2 500 FC) : il passe au niveau 1, ton solde baisse et la ligne
    « Au niveau suivant » montre le prochain effet.
18. **Gestion : sponsors** : plus bas, 3 offres de sponsors fictifs. Clique **Signer le
    contrat** sur l'une d'elles : elle passe dans « Les contrats de sponsoring ».
    Joue un match : la fenêtre de résultat affiche « Contrats de sponsoring : +… »
    et, dans Gestion, le contrat indique un match de moins et la progression de son objectif.
20. **Classement mondial** : sur la place centrale, à gauche du point d'apparition, un
    grand panneau « CLASSEMENT MONDIAL » affiche un top 10 qui change de tableau toutes
    les 12 secondes. Dans l'onglet **Classement**, la carte « Classement mondial » a 3
    boutons (**Cette semaine**, **Meilleurs clubs**, **Trophées**). Dans Studio, elle
    indique « Mode test : seulement les clubs de ce serveur » ; une fois le jeu publié,
    elle montre tous les serveurs (mise à jour toutes les 2 minutes).

Envoie ensuite ta liste (✅ / ❌ + captures + lignes rouges) dans le projet : on corrige.
