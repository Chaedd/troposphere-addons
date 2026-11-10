# QuestTarget

> **Numérotation** : `<MAJEUR>.<MINEUR>.<CORRECTIF>`
> - MAJEUR : changement important ou incompatible.
> - MINEUR : nouvelle fonctionnalité.
> - CORRECTIF : corrections uniquement.

## 1.3.0 (2026-11-10)

### Nouveautés
- Fenêtre d'options accessible avec le bouton de minicarte, `/qtg` ou `/qtg options`. Fermeture avec Échap et déplacement par glisser-déposer.
- Activation du marquage et choix visuel parmi les huit signes : étoile, cercle, losange, triangle, lune, carré, croix et tête de mort. Les réglages sont enregistrés par personnage ; les profils existants conservent leur activation et la tête de mort par défaut.
- Le bouton de minicarte se déplace autour de celle-ci par glisser-déposer et conserve sa position.
- Les changements effectués en combat sont enregistrés immédiatement et appliqués aux actions sécurisées à la sortie du combat. La fenêtre indique ce délai.
- `/qtg skull` reste disponible et active ou désactive le marquage avec le signe choisi.

## 1.2.1 (2026-11-10)

### Corrections
- Le marquage passe par un bouton sécurisé Blizzard de type `raidtarget`, appelé par la macro de ciblage, au lieu d'un appel Lua à `SetRaidTarget` après le clic qui provoquait le blocage de l'addon.
- Cliquer à nouveau sur le même mob conserve la tête de mort (`action = set`). Seules les cibles vivantes attaquables trouvées par la recherche sont marquées ; l'ancienne cible reprise en cas d'échec ne l'est pas.
- `/qtg skull` reconstruit les macros hors combat. En combat, un message indique que la modification sera appliquée à la sortie du combat.
- La longueur de la commande de marquage est réservée dans la limite de 255 octets des macros.

Validation du client Forever à effectuer en jeu : clic et raccourci, même mob ciblé deux fois, recherche sans résultat, option activée/désactivée, combat et permissions de groupe. Les droits de marquage restent imposés par le jeu.

## 1.2.0 (2026-11-09)

### Nouveautés
- Une tête de mort est posée sur le mob ciblé par le bouton ou par le raccourci clavier. En groupe, le jeu ne l'accepte que si on est chef ou assistant.
- `/qtg skull` : activer / désactiver la tête de mort (activée par défaut).

## 1.1.4 (2026-11-09)

### Corrections
- Les boutons passaient devant les sacs et les autres fenêtres. Ils sont maintenant sur la même couche que le suivi des objectifs.

## 1.1.3 (2026-11-09)

### Corrections
- Les mobs « à tuer » n'étaient jamais ciblés en français : le nom lu dans l'objectif gardait l'espace insécable placée avant « : » (ex. « Bâtard des Carmines␣ »), et aucun mob ne portait ce nom exact. Ces espaces sont maintenant retirées.

## 1.1.2 (2026-11-09)

### Corrections
- Le bouton reciblait le cadavre qu'on venait de tuer : quand aucun mob n'était trouvé, il reprenait l'ancienne cible, même morte. Une ancienne cible morte est maintenant relâchée.
- En combat, la liste des mobs visibles est figée par le jeu et peut être périmée après un kill. Le bouton complète donc par un ciblage par nom, en relâchant les cadavres.
- Nouvelle commande `/qtg debug` : affiche les mobs vus et la macro de chaque bouton.

## 1.1.1 (2026-11-09)

### Corrections
- Erreur « Can't measure restricted regions » sur `NamePlate1:GetBottom()` : le jeu interdit de lire la position des barres de vie. Le tri n'utilise plus la position à l'écran mais la distance (moins de ~28 m avant les mobs plus loin).

## 1.1.0 (2026-11-09)

### Ciblage
- Le bouton ignore les mobs déjà engagés par d'autres joueurs (nom grisé, butin pour eux). Il préfère aussi les mobs hors combat aux mobs en combat contre quelqu'un d'autre.
- Il cible directement les mobs vivants visibles par leur barre de vie, en commençant par le plus proche à l'écran.
- Il faut afficher les barres de vie ennemies (touche V). Sans elles, le ciblage se fait par nom comme avant, et le jeu ne permet pas alors d'écarter les mobs déjà pris.
- L'infobulle du bouton indique combien de mobs libres sont visibles.

## 1.0.1 (2026-11-09)

### Corrections
- Les mobs morts ne restent plus ciblés : un cadavre est relâché aussitôt et le bouton essaie le mob suivant. Si aucun mob vivant n'est trouvé, l'ancienne cible est reprise.

## 1.0.0 (2026-11-09)
Première version, pour WoW Forever (client 16001).

- Un bouton (icône de visée) à gauche de chaque quête du suivi des objectifs, quand la quête a des mobs à cibler.
- **Clic gauche** : cible le mob le plus proche lié à la quête. Si aucun n'est à portée, l'ancienne cible est gardée.
- **Clic droit** : affiche dans le chat la liste des mobs de la quête.
- Mobs « à tuer » : lus dans le texte des objectifs.
- Mobs « à looter » : appris automatiquement en approchant les mobs (barres de vie ennemies, survol ou cible). Les mobs utiles à une quête affichent son titre dans leur infobulle. Ces noms sont gardés par personnage et oubliés quand la quête est rendue ou abandonnée.
- Raccourci clavier (Options > Raccourcis > AddOns > QuestTarget) : cible un mob de la quête suivie sur la carte, sinon de la première quête du suivi.
- Commandes : `/qtg` (aide), `/qtg list` (mobs appris), `/qtg reset` (tout oublier).
- Limite du jeu : en combat, les boutons ne peuvent ni bouger ni changer de liste. Ils se mettent à jour à la sortie du combat.
