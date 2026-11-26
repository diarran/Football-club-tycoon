# Tester le jeu (environ 15 minutes)

## 1. Récupérer le fichier du jeu

1. Ouvre le lien de téléchargement que Claude t'a donné (il faut être connecté à GitHub).
   Sinon : sur GitHub, onglet **Actions** > **Construire la place** > le dernier passage
   avec une coche verte > en bas, **Artifacts** > `FootballClubTycoon-place`.
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

## 5. Ce qu'il faut vérifier

Note pour chaque point ✅ ou ❌. Si c'est ❌, fais une capture d'écran.

1. **Arrivée** : ton personnage apparaît sur ton terrain, près du portique au nom de
   ton club (pas sur la grande place, pas dans le vide).
2. **Écran** : en haut à gauche, l'écusson avec les initiales du club, le nom du club,
   la division et le solde **2 500 FC**.
3. **Menu** : le bouton **Club** ouvre le menu et la caméra montre ton club d'en haut.
   Le **X** rouge ferme le menu et la caméra revient derrière ton personnage.
4. **Tutoriel** : le bandeau en haut au centre change quand tu fais ce qu'il demande.
5. **Stade** : « Améliorer » le terrain fait baisser le solde et le terrain change
   d'aspect (bancs de touche, panneaux publicitaires).
6. **Effectif** : « Recruter » ajoute un joueur à l'effectif.
7. **Matchs** : lance un match. Une fenêtre de résultat s'affiche avec des FC gagnés.
8. **Nom** : dans **Accueil**, renomme le club. Le nouveau nom apparaît en haut à
   gauche et sur le portique.
9. **À 2 joueurs** : chaque joueur a un terrain différent, voit l'autre club dans
   **Classement** et peut l'affronter dans **Matchs**.
10. **Téléphone** : onglet **Test** > **Device** (icône de téléphone), choisis un
    téléphone. Les boutons restent lisibles et faciles à toucher.

Envoie ensuite ta liste (✅ / ❌ + captures + lignes rouges) dans le projet : on corrige.
