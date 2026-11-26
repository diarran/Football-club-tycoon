# Ouvrir le projet dans Roblox Studio

Deux méthodes. La première ne demande rien d'installer, la seconde garde
Studio synchronisé en direct avec le code du dépôt.

## Méthode 1 : ouvrir le fichier tout prêt (le plus simple)

1. Sur GitHub, ouvre l'onglet **Actions** du dépôt, puis le dernier passage
   réussi de « Construire la place » (coche verte).
2. En bas de la page, dans **Artifacts**, télécharge `FootballClubTycoon-place`
   et décompresse-le.
3. Double-clique sur `FootballClubTycoon.rbxlx` : il s'ouvre dans Studio.
4. Clique sur **Play** (F5). Le jeu démarre : ton terrain, le HUD avec tes
   FC Coins et le bouton **Club** à gauche.

Ce fichier est une copie : si le code change sur GitHub, retélécharge-le.

## Méthode 2 : synchronisation en direct avec Rojo

À faire une seule fois :

1. Installe **Rokit** (gestionnaire d'outils Roblox) :
   https://github.com/rojo-rbx/rokit#installation
2. Télécharge le dépôt (bouton vert **Code** > **Download ZIP** sur GitHub,
   ou GitHub Desktop) et ouvre un terminal dans le dossier du projet.
3. Lance `rokit install` (installe Rojo à la bonne version, voir `rokit.toml`).
4. Lance `rojo plugin install` (ajoute le plugin Rojo dans Studio).

À chaque séance :

1. Dans le dossier du projet, lance `rojo serve`. Laisse le terminal ouvert.
2. Ouvre Studio sur une place vide (**Baseplate**) ou sur ta place publiée.
3. Onglet **Plugins** > **Rojo** > **Connect**. Le code du dépôt apparaît dans
   `ServerScriptService`, `ReplicatedStorage` et `StarterPlayer`.
4. Clique sur **Play**.

Alternative sans terminal : installe Visual Studio Code et l'extension
« Rojo » (evaera). Ouvre le dossier du projet, puis la commande
« Rojo: Open menu » propose d'installer Rojo et le plugin, et de lancer la
synchronisation en un clic.

## Réglages de la place (une seule fois)

- **Publier** : File > Publish to Roblox.
- **Sauvegardes** : Home > Game Settings > Security > active
  « Enable Studio Access to API Services ». Sans ce réglage, le jeu tourne en
  « mode test » et la progression n'est pas sauvegardée (c'est affiché à l'écran).
- **6 joueurs maximum** : Game Settings > Places > nombre de joueurs maximum
  par serveur = 6 (un club par joueur).

## Tester à plusieurs

Onglet **Test** > **Clients and Servers**, choisis 2 joueurs ou plus, puis
**Start**. Chaque fenêtre est un joueur : vérifie que chacun reçoit un terrain
différent et qu'un club peut affronter l'autre dans l'onglet **Matchs**.
