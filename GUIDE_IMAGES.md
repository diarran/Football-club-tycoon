# Mettre le vrai logo et les écussons dans le jeu (environ 10 minutes)

Aujourd'hui le jeu **dessine** lui-même un logo écrit et des écussons avec les initiales
du club. Ça marche très bien. Ce guide sert à afficher les **vraies images** à la place :

- le **logo** en haut de l'écran d'accueil ;
- l'**écusson de chaque club** en haut à gauche de l'écran, sur le portique d'entrée
  du terrain et sur le toit des bureaux (niveau 5).

Roblox n'accepte que les images envoyées par **ton compte**. Claude ne peut pas le faire
à ta place. Tu envoies 7 images, tu copies 7 numéros, tu me les donnes dans le chat :
c'est tout.

---

## Étape 1. Récupérer les 7 images

Dans les fichiers du projet Claude, dossier **identite-visuelle** :

- `logo.png`
- dans le sous-dossier **ecussons** : `club-1.png`, `club-2.png`, `club-3.png`,
  `club-4.png`, `club-5.png`, `club-6.png`

Télécharge-les sur ton ordinateur, dans un même dossier (par exemple sur le Bureau).

(Elles sont aussi sur GitHub : dossier `assets/brand` pour le logo et
`assets/brand/crests` pour les écussons.)

## Étape 2. Les envoyer sur Roblox depuis Studio

1. Ouvre **Roblox Studio** et ouvre ton jeu **Football Club Tycoon** (celui que tu as publié).
2. En haut, onglet **Affichage** (ou **Fenêtre**) > **Gestionnaire de ressources**
   (en anglais : *View > Asset Manager*). Une fenêtre s'ouvre.
3. Dans cette fenêtre, clique sur **Importer** (petite flèche vers le haut, ou bouton
   *Bulk Import* / *Importation groupée*).
4. Sélectionne **les 7 images d'un coup** (maintiens **Ctrl** en cliquant), puis **Ouvrir**.
5. Attends quelques secondes : un dossier **Images** apparaît avec tes 7 images.

> Si Roblox affiche « en attente de vérification », c'est normal : il vérifie chaque
> image (quelques minutes, parfois une heure). Tu peux déjà copier les numéros.

## Étape 3. Copier les 7 numéros

Pour chaque image du dossier **Images** :

1. **Clic droit** sur l'image > **Copier l'ID dans le presse-papiers**
   (*Copy ID to Clipboard*).
2. Colle-le dans un message (Bloc-notes, ou directement dans le chat avec Claude).

Un numéro ressemble à `rbxassetid://123456789012` ou à `123456789012`. Les deux
formes conviennent, et un lien copié depuis le site Creator Hub aussi.

## Étape 4. Me les envoyer

Envoie un message dans le chat comme celui-ci (avec tes vrais numéros) :

```
logo : 111111111111
club-1 : 222222222222
club-2 : 333333333333
club-3 : 444444444444
club-4 : 555555555555
club-5 : 666666666666
club-6 : 777777777777
```

Je les colle dans le jeu (un seul endroit : `src/shared/Brand.lua`), je lance les tests,
puis tu n'as plus qu'à prendre le nouveau fichier du jeu et **republier**
(Fichier > Publier sur Roblox > ton jeu existant), comme d'habitude.

---

## Bon à savoir

- **Rien ne casse si une image manque ou n'est pas encore validée** : le jeu garde la
  version dessinée tant que l'image n'est pas prête, puis l'affiche toute seule.
- **L'icône et la grande image de la page du jeu** (`icon-512.png` et
  `thumbnail-1920x1080.png`) ne demandent pas de numéro : elles se mettent sur
  **create.roblox.com** > **Créations** > ton jeu > **Infos de base / Places** >
  **Icône** et **Miniatures** (voir l'étape 4 de [GUIDE_PUBLICATION.md](GUIDE_PUBLICATION.md)).
- **Le lien de ton jeu** est déjà dans le jeu (onglet Classement, carte Amis, pour que
  les joueurs puissent le copier et le partager) :
  https://www.roblox.com/games/75942746782438

## En cas de souci

- **Je ne trouve pas le Gestionnaire de ressources** : envoie-moi une capture d'écran du
  haut de Studio, je te dis où cliquer.
- **« Copier l'ID » n'existe pas** : fais un clic droit > **Propriétés** (ou ouvre
  l'image) et copie le grand nombre affiché ; ou envoie-moi une capture d'écran de la
  liste des images.
- **Une image est refusée par Roblox** : dis-le-moi, je t'en prépare une autre version.
