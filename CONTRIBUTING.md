# Publier un addon sur Troposphère

Ce guide s'adresse aux personnes qui ajoutent ou mettent à jour des addons dans ce dépôt.

> **À retenir :** tout ce qui est fusionné dans `main` est publié **immédiatement** chez tous les joueurs de Troposphère. C'est pour ça que `main` est protégée : chaque changement passe par une pull request relue avant d'être fusionnée.

## Avant de commencer

- Avoir un compte GitHub et avoir été ajouté comme **collaborateur** du dépôt. Demande à Chaedd.
- Avoir [Git](https://git-scm.com/download/win) installé.
- Récupérer le dépôt, une seule fois :

  ```bash
  git clone https://github.com/Chaedd/troposphere-addons.git
  cd troposphere-addons
  ```

## Comment un addon est rangé

Chaque sous-dossier de `addons/` est **un** addon. Troposphère le copie tel quel dans `World of Warcraft\_retail_\Interface\AddOns\` (ou la version Classic choisie par le joueur).

```
addons/
  MonAddon/
    MonAddon.toc        ← obligatoire, même nom que le dossier
    MonAddon.lua
    media/
      icone.tga
```

Règles :

- **Le dossier porte le même nom que le `.toc`**, comme pour n'importe quel addon WoW. Sinon le jeu ne le charge pas.
- Le nom du dossier contient seulement des lettres sans accent, des chiffres, des espaces, `_`, `-` ou `.`.
- **Pas de dossier en trop** : pas de `addons/MonAddon/MonAddon/MonAddon.toc`.
- **Pas de `.zip`** : on met les fichiers décompressés.
- Un addon livré en plusieurs dossiers (par exemple `MonAddon` et `MonAddon_Options`) donne **un dossier par addon** dans `addons/`. Le joueur les installe séparément.

## Fichiers requis

Tout le dossier est copié chez chaque joueur : n'y mets **que ce dont le jeu a besoin**.

**Obligatoire :**

- **`MonAddon.toc`**, avec le même nom que le dossier. C'est le seul fichier imposé.

**Ce que le jeu utilise :**

- Les **`.lua`** et **`.xml`** de l'addon. **Chacun doit être listé dans le `.toc`**, sinon WoW ne le charge pas, même s'il est bien installé.
- Les **médias** utilisés par le code : textures (`.tga`, `.blp`), sons (`.ogg`, `.mp3`), polices (`.ttf`).
- Les **bibliothèques** embarquées (dossier `Libs/` avec LibStub, Ace3…), elles aussi listées dans le `.toc`.

**À ne pas mettre :**

| À éviter | Pourquoi |
| --- | --- |
| `README.md`, `CHANGELOG.md`, documentation | Inutile en jeu. Décris l'addon dans `## Notes` et le changement dans ta pull request. |
| `.gitignore`, `.gitattributes`, `.editorconfig`, `.pkgmeta`, dossiers `.git/`, `.github/`, `.vscode/`, `.idea/` | Fichiers d'outils de développement. |
| Captures d'écran, fichiers sources de graphisme (`.psd`, `.xcf`, `.blend`…) | Gros et inutiles en jeu. Mets les captures dans la pull request. |
| Tests, scripts de build, fichiers de sauvegarde (`.bak`, `~`) | Inutiles en jeu. |
| `Thumbs.db`, `desktop.ini`, `.DS_Store` | Fichiers créés automatiquement par Windows ou macOS. |
| `.zip`, `.exe`, `.dll`, `.bat` | Archives et programmes : jamais dans un addon. |
| `WTF/`, fichiers `SavedVariables` | Ce sont les réglages d'un joueur, pas l'addon. |
| Fichiers personnels (logs, notes, identifiants) | Le dépôt est public. |

Seule exception : garde le fichier **`LICENSE`** si la licence de l'addon impose de le distribuer avec.

## Le fichier `.toc`

Troposphère affiche les informations du `.toc`. Exemple complet :

```
## Interface: 120000
## Title: Mon Addon
## Notes: Une phrase qui explique ce que fait l'addon.
## Author: TonPseudo
## Version: 1.0.0
## SavedVariables: MonAddonDB

Libs\LibStub\LibStub.lua
MonAddon.lua
MonAddon.xml
```

Les lignes `##` sont les informations ; les lignes suivantes sont les fichiers chargés par WoW, dans l'ordre et avec un chemin relatif au dossier de l'addon. `## SavedVariables` est facultatif : c'est le nom de la variable où l'addon sauvegarde ses réglages.

- **Title** : le nom affiché dans l'app. Les codes couleur WoW (`|cff...|r`) sont retirés à l'affichage.
- **Notes** : la description affichée sous le nom.
- **Version** : affichée aux joueurs, par exemple « v1.0.0 → v1.1.0 » lors d'une mise à jour. Augmente-la à chaque changement.
- **Interface** : le numéro de version du jeu. Pour connaître le bon, tape en jeu `/dump select(4, GetBuildInfo())`.

Si l'addon a des `.toc` différents par version du jeu (`MonAddon_Mainline.toc`, `MonAddon_Classic.toc`…), mets-les tous dans le dossier : WoW choisit le bon.

## Tester avant de publier

1. Copie ton dossier `addons/MonAddon` à la main dans `Interface\AddOns` de ton jeu.
2. En jeu, tape `/reload` et vérifie que l'addon marche, sans erreur Lua.
3. Supprime ensuite cette copie : Troposphère la verrait comme « Installé à la main ».

## Publier : ajout ou mise à jour

1. Pars d'une version à jour de `main` et crée une branche :

   ```bash
   git checkout main
   git pull
   git checkout -b ajout-monaddon
   ```

2. Ajoute ou modifie le dossier dans `addons/`, puis commite :

   ```bash
   git add addons/MonAddon
   git commit -m "Ajoute MonAddon 1.0.0"
   ```

3. Envoie la branche sur GitHub :

   ```bash
   git push -u origin ajout-monaddon
   ```

4. Sur la page du dépôt, clique sur **Compare & pull request**. Dis en une ou deux phrases ce que fait l'addon ou ce qui change, puis **Create pull request**.
5. Une autre personne relit et clique sur **Approve**. On fusionne ensuite avec **Merge pull request**.
6. C'est publié : les joueurs voient l'addon ou la mise à jour en cliquant sur **Rafraîchir** dans Troposphère.

Une pull request = un addon, c'est plus simple à relire.

Pousser directement sur `main` est refusé avec le message « Changes must be made through a pull request ». C'est normal : passe par une branche.

## Retirer un addon

Supprime son dossier dans une pull request. Attention : l'addon disparaît de la liste de Troposphère, mais **il reste installé chez les joueurs qui l'ont déjà**. Ils doivent alors supprimer le dossier à la main dans `Interface\AddOns`. Préviens-les si c'est important.

## Avant d'ouvrir la pull request

- [ ] Le dossier et le `.toc` ont le même nom.
- [ ] `## Title`, `## Notes`, `## Author` et `## Version` sont remplis.
- [ ] `## Version` est augmentée s'il s'agit d'une mise à jour.
- [ ] Chaque `.lua` et `.xml` est listé dans le `.toc`.
- [ ] L'addon a été testé en jeu, sans erreur Lua.
- [ ] Aucun fichier superflu : pas de README, `.gitignore`, `.git/`, captures, `.zip`, `.exe`, `SavedVariables` ni fichiers personnels (voir [Fichiers requis](#fichiers-requis)).
- [ ] Tu as le droit de publier cet addon (c'est le tien, ou sa licence l'autorise).

Ce dépôt est **public** : n'importe qui peut lire le code des addons.
