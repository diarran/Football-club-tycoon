# Identité visuelle — Football Club Tycoon

Tout est **fictif** (aucun vrai club, logo ou marque). Les images sont générées par
`node tools/brand/generate.js [capture-du-jeu.png]` (dessin en SVG, export PNG avec Playwright).

| Fichier | Usage |
| --- | --- |
| `logo.png` / `logo.svg` | Logo horizontal (fond transparent) : écusson + « FOOTBALL CLUB TYCOON ». |
| `emblem.png` | Écusson du jeu seul (512x512, transparent) : écran de chargement, HUD. |
| `icon-512.png` | Icône de l'expérience Roblox (512x512). |
| `thumbnail-1920x1080.png` | Miniature de la page Roblox (1920x1080), sur une capture du rendu 3D. |
| `palette.png` / `palette.json` | Palette, identique au HUD (`COLORS` dans `src/client/Controllers/UIController.lua`). |
| `crests/club-1..6.png` | Écussons des 6 clubs de départ, couleurs de `WorldConfig.CLUB_COLORS`. |
| `crests/layers/` | Calques blancs (256x256) pour composer les écussons des clubs générés. |

## Palette

| Rôle | Hex | Clé HUD |
| --- | --- | --- |
| Fond | `#121826` | `background` |
| Panneau | `#1C2436` | `panel` |
| Carte | `#283248` | `card` |
| Vert terrain (action principale) | `#2EAA5A` | `accent` |
| Vert foncé | `#1E7840` | `accentDark` |
| Or (FC Coins, titres) | `#F5C442` | `gold` |
| Texte | `#F0F4FA` | `text` |
| Texte secondaire | `#A0AABE` | `muted` |
| Erreur | `#DC5050` | `error` |

Police : Gotham Bold dans Roblox (Inter Black/ExtraBold pour les visuels hors jeu).

## Écussons des clubs générés

Chaque écusson = 3 `ImageLabel` superposés, teintés avec `ImageColor3` :

1. `shape-<forme>-outer.png` → couleur **secondaire** (le liseré) ;
2. `shape-<forme>-inner.png` → couleur **principale** ;
3. `emblem-<emblème>.png` → couleur **secondaire** ; le sigle du club (3 lettres) se met
   dans un `TextLabel` en dessous si besoin.

Formes : `classic`, `round`, `flat`, `heater`, `octagon`, `pointed`.
Emblèmes : `star`, `crown`, `bolt`, `wave`, `tower`, `wing`. Soit 36 combinaisons.
Il faudra importer ces PNG dans Roblox (Asset Manager) pour obtenir leurs `rbxassetid`.

Logo et écussons des 6 clubs : marche à suivre pour Nj dans [GUIDE_IMAGES.md](../../GUIDE_IMAGES.md) ;
les numéros se collent dans `src/shared/Brand.lua` (numéro seul, `rbxassetid://…` ou lien acceptés).
