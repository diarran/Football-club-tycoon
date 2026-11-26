# Publier le jeu sur Roblox et y jouer sur ton téléphone (environ 20 minutes)

À faire **sur ton ordinateur** (PC ou Mac), dans **Roblox Studio**.
Ce n'est pas Android Studio : Android Studio ne sert pas pour Roblox.
Le téléphone ne sert qu'à la toute fin, pour jouer.

Avant de commencer : fais d'abord le test du [GUIDE_TEST.md](GUIDE_TEST.md), puis ouvre
le fichier `FootballClubTycoon.rbxlx` dans Roblox Studio (même méthode).

---

## Étape 1. Publier le jeu

1. Dans Roblox Studio, clique sur **File** (Fichier) en haut à gauche, puis
   **Publish to Roblox** (Publier sur Roblox).
2. Une fenêtre s'ouvre. Choisis **Create new experience** (Créer une nouvelle expérience).
3. Remplis :
   - **Name** (Nom) : `Football Club Tycoon`
   - **Description** : copie le texte français de la partie « Textes de la page du jeu »
     plus bas.
   - **Genre** : `Simulation` (ou `Tycoon` si le choix existe).
   - **Devices** (Appareils) : coche **Computer**, **Phone** et **Tablet**.
4. Clique sur **Create** (Créer). Attends le message « Published » / « Publié ».

Le jeu est maintenant sur Roblox, mais **personne d'autre que toi ne peut y jouer** :
il est privé par défaut. C'est ce qu'on veut pour tester.

> Plus tard, après chaque nouvelle version : ouvre le nouveau fichier, puis
> **File > Publish to Roblox** et choisis le jeu existant `Football Club Tycoon`
> (il ne faut pas en créer un nouveau, sinon les sauvegardes repartent de zéro).

## Étape 2. Activer la sauvegarde (accès aux API)

1. Onglet **Home** (Accueil) > bouton **Game Settings** (Paramètres du jeu).
2. À gauche, clique sur **Security** (Sécurité).
3. Active **Enable Studio Access to API Services** (le bouton devient bleu/vert).
4. Clique sur **Save** (Enregistrer) en bas.

Sans ça, dans Studio tu vois « Mode test : la progression n'est pas sauvegardée ».
**Dans le vrai jeu (sur ton téléphone), la sauvegarde marche toujours**, même sans ce réglage.

## Étape 3. Régler le nombre de joueurs et les appareils

Toujours dans **Game Settings** :

1. **Places** (ou **Places** > les trois petits points > **Edit**) : mets
   **Max Players** (nombre de joueurs maximum) à **6**. Le jeu a 6 terrains par serveur.
2. **Basic Info** (Infos de base) : vérifie que **Computer**, **Phone** et **Tablet**
   sont cochés dans **Playable Devices** (Appareils).
3. Clique sur **Save**.

## Étape 4. Ajouter l'icône et l'image du jeu

Les images sont dans le dépôt GitHub, dossier `assets/brand`, et dans les fichiers du
projet Claude (dossier `identite-visuelle`) :
- `icon-512.png` : l'icône (le petit carré)
- `thumbnail-1920x1080.png` : la grande image de présentation

1. **Game Settings** > **Basic Info**.
2. **Game Icon** (Icône) : clique sur le cadre, choisis `icon-512.png`.
3. **Thumbnails** (Miniatures) : clique sur **+**, choisis `thumbnail-1920x1080.png`.
4. **Save**.

Si ce n'est pas proposé dans Studio : va sur **https://create.roblox.com** >
**Creations** (Créations) > clique sur ton jeu > menu de gauche **Places** /
**Configure** > **Icon** et **Thumbnails**.
Roblox vérifie les images : elles peuvent mettre quelques minutes à apparaître.

## Étape 5. Jouer sur ton téléphone Android

1. Sur ton ordinateur, va sur **https://create.roblox.com** > **Creations** > ton jeu.
   Clique sur les trois petits points > **Copy URL** (Copier l'adresse).
   L'adresse ressemble à `https://www.roblox.com/games/123456789/...`.
2. Envoie-toi cette adresse sur ton téléphone (par message ou par e-mail).
3. Sur le téléphone, installe l'appli **Roblox** depuis le **Play Store** et connecte-toi
   **avec le même compte** que dans Studio.
4. Ouvre le lien reçu sur le téléphone : la page du jeu s'ouvre dans l'appli Roblox.
   Appuie sur le gros bouton **▶ Jouer**.

Comme le jeu est privé, seul ton compte peut le lancer. C'est normal.

## Étape 6 (plus tard). Ouvrir le jeu à tout le monde

Ne le fais qu'une fois le test sur téléphone réussi.

1. **https://create.roblox.com** > **Creations** > ton jeu > **Questionnaire**
   (questionnaire de maturité) : réponds aux questions (le jeu n'a ni violence, ni
   achats d'argent réel, ni chat spécial). Roblox l'exige avant d'ouvrir le jeu.
2. Puis **Privacy** (Confidentialité) ou le bouton **Public** : choisis **Public**.

Pour faire tester à quelques amis seulement : laisse le jeu privé et, dans
**Game Settings** > **Permissions**, ajoute leurs comptes Roblox.

---

## Étape 7 (facultatif). Ouvrir la boutique Robux

Le jeu reste gratuit. La boutique ne vend que de l'apparence (4 objets exclusifs
du Prestige : couleurs néon, projecteurs rubis, statue de cristal, maillot
carbone), jamais d'avantage dans les matchs. Tant que tu ne fais rien, elle
reste **cachée** dans le jeu.

1. Va sur [create.roblox.com](https://create.roblox.com), ouvre **Football Club Tycoon**.
2. Dans le menu de gauche : **Monetization** puis **Developer Products**.
3. Clique **Create a Developer Product** et crée ces 4 produits (nom au choix, prix conseillé) :
   - « Couleurs néon » : 99 Robux
   - « Projecteurs rubis » : 79 Robux
   - « Statue de cristal » : 149 Robux
   - « Maillot carbone » : 99 Robux
4. Pour chaque produit, copie son **ID** (un grand nombre, bouton « Copy Product ID »).
5. Envoie-moi les 4 IDs dans le chat en disant lequel est lequel : je les colle
   dans le jeu (fichier `src/shared/Monetization.lua`) et la boutique apparaît
   dans l'onglet **Prestige**.

À savoir :
- Le paiement est vérifié par le serveur du jeu : un achat n'est donné qu'une
  fois, même si le joueur se déconnecte ou si la sauvegarde a un raté.
- Dans Studio, les achats sont des tests gratuits : rien n'est débité.
- Il existe aussi un « boost de revenus » (+50 % pendant 30 min). Il est
  **coupé** et le restera tant qu'on ne décide pas ensemble de l'ouvrir.
  Ne crée pas de produit pour lui pour l'instant.

## Textes de la page du jeu

### Français

- **Titre** : Football Club Tycoon
- **Description** :
  ⚽ Construis le club de football de tes rêves ! Améliore ton stade, tes tribunes et ton
  centre d'entraînement, recrute des joueurs et gagne des FC Coins. Joue des matchs
  simulés, monte de la division 7 jusqu'à la division 1, défie les autres clubs du serveur
  et remporte le tournoi. Jusqu'à 6 clubs par serveur. Ta progression est sauvegardée
  automatiquement. Jouable sur ordinateur, téléphone et tablette, en français et en anglais.
- **Mots-clés / tags** : Gestion, Simulation, Football, Tycoon, Multijoueur

### English (traduit avec DeepL)

- **Title**: Football Club Tycoon (le nom du jeu ne se traduit pas)
- **Description**:
  ⚽ Build the soccer club of your dreams! Upgrade your stadium, stands, and training
  center; recruit players; and earn FC Coins. Play simulated matches, climb from
  Division 7 to Division 1, challenge other clubs on the server, and win the tournament.
  Up to 6 clubs per server. Your progress is saved automatically. Playable on computers,
  phones, and tablets, in French and English.
- **Tags**: Management, Simulation, Soccer, Tycoon, Multiplayer

Pour ajouter l'anglais : **create.roblox.com** > ton jeu > **Localization**
(Traduction) > **Add language** > **English**, puis colle le titre et la description.

---

## Ce qui change une fois publié (déjà réglé dans le code)

- **Sauvegarde** : dans le jeu publié, la progression est toujours enregistrée
  (toutes les quelques minutes et quand tu quittes). Le message « Mode test » n'apparaît
  que dans Studio quand l'accès aux API est désactivé.
- **Panne de Roblox au démarrage** : le jeu publié ne passe jamais en « mode test ».
  Si la sauvegarde ne répond pas, il réessaie, et au pire il te demande de revenir
  plus tard, sans rien effacer.
- **Un seul serveur à la fois par joueur** : si tu lances le jeu sur l'ordinateur et le
  téléphone en même temps, le second attend que l'autre libère ta
  sauvegarde, ou te demande de réessayer (protection contre les pertes de progression).
- **Logo et écussons en image** (facultatif) : le jeu les dessine déjà tout seul. Pour
  utiliser les vraies images, il faudra les importer sur Roblox puis donner leurs numéros
  à Claude.

## En cas de souci

- **« Publish to Roblox » est grisé** : connecte-toi à Roblox dans Studio (en haut à droite).
- **Le lien ne s'ouvre pas dans l'appli** : ouvre l'appli Roblox, puis le lien depuis
  Chrome ; ou vérifie que c'est le même compte que dans Studio.
- **Message rouge ou écran bloqué** : fais une capture d'écran et envoie-la à Claude.
