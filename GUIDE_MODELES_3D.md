# Mettre les modèles 3D faits dans Blender dans le jeu (environ 5 minutes par modèle)

Aujourd'hui, tous les bâtiments et véhicules du jeu sont construits en **blocs** par le
code. Ça marche partout. Ce guide sert à remplacer certains objets par un **modèle 3D
détaillé** fait dans Blender (formes arrondies, roues, jantes, vitres).

Roblox n'accepte que les modèles envoyés par **ton compte**. Claude ne peut pas le
faire à ta place. Tu importes le fichier, tu le publies, tu me donnes le numéro : c'est tout.
Si un numéro est faux ou vide, le jeu garde simplement la version en blocs.

Premier modèle disponible : **le bus du club** (dépôt des véhicules du mode Création).

---

## Étape 1. Récupérer le fichier

Dans les fichiers du projet Claude, dossier **modeles-3d** : `bus_du_club.fbx`
(l'image `bus_du_club.png` montre à quoi il ressemble).
Télécharge-le sur ton ordinateur. Il est aussi sur GitHub, dossier `assets/models`.

## Étape 2. L'importer dans Roblox Studio

1. Ouvre ton jeu dans Roblox Studio.
2. En haut, onglet **Accueil** (Home), clique sur **Importer 3D** (Import 3D).
3. Choisis `bus_du_club.fbx`. Une fenêtre d'aperçu s'ouvre : clique sur **Importer**.
4. Le bus apparaît dans la scène.

## Étape 3. Le publier sur Roblox

1. Dans la fenêtre **Explorateur** (à droite), clic droit sur le bus (`bus_du_club`).
2. Choisis **Enregistrer sur Roblox…** (Save to Roblox).
3. Donne-lui un nom (« Bus du club »), puis **Envoyer** (Submit).
4. Clic droit à nouveau sur le bus, puis **Copier l'ID de la ressource** (Copy Asset ID).
5. Tu peux ensuite supprimer le bus de la scène : le jeu le placera lui-même.

## Étape 4. Me donner le numéro

Colle simplement le numéro dans le chat Claude (par exemple « bus : 1234567890 »).
Je le mets dans le jeu (fichier `src/shared/Models.lua`) et je vérifie.

---

### Pour les développeurs

- Numéros : `src/shared/Models.lua` (`Models.ASSET_IDS`).
- Chargement : `src/server/World/ModelLoader.lua` charge les modèles en arrière-plan
  au démarrage (`InsertService:LoadAsset`), retire tout script, met le modèle à
  l'échelle de la place prévue, puis reconstruit les terrains. Tant que rien n'est
  chargé, `ModelLoader.Place` renvoie `nil` et le code garde sa version en Parts.
- Le jeu doit appartenir au même compte (ou groupe) que le modèle publié.
- Fabriquer un modèle : `tools/blender/bus_du_club.py`, lancé avec Blender ou le
  module Python `bpy` (`python3 tools/blender/bus_du_club.py -- assets/models`).
  Un objet par matériau pour que l'Importateur 3D crée des MeshParts simples.
