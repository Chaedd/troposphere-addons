# STO Red Flag — 0.1.0

Première version pour **World of Warcraft: Forever 1.60.1, build 70862, interface 16001** (version confirmée en jeu par le propriétaire du projet).

## Installation

Fermer WoW, extraire `dist/STORedFlag-0.1.0.zip` dans le dossier `Interface/AddOns` du client Forever. On doit obtenir `Interface/AddOns/STORedFlag/STORedFlag.toc`, sans dossier intermédiaire supplémentaire. Relancer le jeu puis activer STO Red Flag dans la liste des addons.

Le dossier source `STORedFlag` peut aussi être copié directement dans `Interface/AddOns`.

## Utilisation

- `/storf` ou `/redflag` : ouvrir la fenêtre de liste et les options.
- `/storf cible` : préremplir le nom du joueur ciblé, puis saisir le motif.
- `/storf add Nom-Royaume motif` : créer ou modifier son signalement.
- `/storf remove Nom-Royaume` : retirer son propre signalement.
- `/storf sync` : demander une synchronisation (au plus une demande par minute).

Dans la fenêtre : rechercher un joueur, faire défiler avec la molette, survoler pour voir tous les motifs, cliquer pour sélectionner son nom. Le motif est obligatoire et limité à 200 **octets** (les caractères accentués en utilisent plusieurs). Les options sont propres à chaque installation du compte ; les signalements sont attribués au personnage qui les crée.

Chaque membre peut publier un signalement par joueur. Plusieurs auteurs peuvent signaler la même personne ; le drapeau reste tant qu'un de leurs signalements est actif. Chacun peut modifier ou retirer le sien. Pas de suppression globale par un officier dans cette version.

## Affichages implémentés

- Cadres Blizzard de groupe et de raid, cible et focus : petit drapeau rouge à gauche du cadre, survol pour les motifs, clic pour ouvrir la fiche.
- Recherche de groupe Blizzard : chef des annonces et membres des candidatures, lorsque les API et noms sont disponibles. Le drapeau d'une annonce concerne son chef ; il ne garantit pas que tous les membres du groupe sont connus.
- Chat : drapeau après le nom de l'auteur, au début du message. Survol pour les motifs ; clic avec le comportement standard d'un lien de joueur. L'option agit sur les nouveaux messages ; les anciennes lignes restent telles qu'elles ont été affichées.
- Infobulle standard d'un joueur : ajout des motifs.

Les cinq emplacements s'activent indépendamment dans la fenêtre `/storf`.

**Limites de cette version :** les drapeaux des cadres (groupe, raid, cible, focus et recherche) sont masqués pendant le combat et se réaffichent ensuite. Les noms que le client protège ne sont pas exploités. Les interfaces de remplacement (ElvUI, Shadowed Unit Frames, etc.) n'ont pas d'adaptateur. L'intégration graphique et les échanges réels restent à valider dans le client Forever : les tests automatisés ne remplacent pas une session en jeu.

## Partage et stockage

Aucun service externe. Les communications utilisent les messages techniques d'addon, sans publication dans le chat lisible. Une demande en guilde déclenche des offres ; un seul pair est choisi et les deux côtés échangent leur historique en messages privés techniques. Les messages sont fragmentés, réassemblés et envoyés à débit limité (5 paquets/seconde par client). La synchronisation est demandée à la connexion puis toutes les cinq minutes. Les nouvelles modifications sont annoncées sur le canal technique de guilde.

Il faut qu'un autre utilisateur de l'addon soit connecté pour récupérer des données. Un ajout fait hors connexion des autres sera récupéré lors d'un échange ultérieur avec un détenteur de cet historique. Il n'existe pas de copie centrale garantie : un signalement perdu par tous les détenteurs ne peut pas être restauré.

Les données sont séparées par guilde, royaume d'origine et faction. Le nom complet `Nom-Royaume` évite de confondre deux personnages homonymes. Le nom de personnage est l'identité de cette version : un changement de nom ou transfert de royaume demande un nouveau signalement. Aucune identité de compte Battle.net n'est suivie.

Quitter la guilde désactive l'accès à sa liste et annule les échanges en attente. Son historique demeure dans les SavedVariables locales si le personnage rejoint ultérieurement la même guilde. Des personnages d'un même compte partagent le stockage correspondant à cette guilde sur cette installation. La limite est de 3 000 couples joueur/auteur par guilde, retraits compris.

Les retraits sont conservés comme marqueurs de suppression pour empêcher une ancienne copie de réactiver un signalement. La révision la plus récente l'emporte ; à révision identique, un retrait gagne et les autres conflits sont résolus de façon déterministe.

Les expéditeurs sont vérifiés contre le roster de guilde local. Un ajout en direct doit porter le nom de l'expéditeur. Les historiques relayés ne sont acceptés que pendant un échange négocié avec un membre de guilde. **Ce modèle suppose la confiance entre membres : il n'y a pas de signature cryptographique, et un client modifié peut fabriquer un historique relayé.** La distribution interne est une pratique de guilde, pas un contrôle d'accès du code. Les données déjà copiées chez un ancien membre ne peuvent pas être effacées à distance.

## Vérification en jeu (à effectuer avant diffusion à toute la guilde)

1. Installer sur deux comptes membres de la même guilde et ouvrir `/storf` : aucune erreur Lua.
2. Avec A, signaler une cible de test avec un motif reconnaissable. Avec B, vérifier le motif et l'auteur dans la liste puis au survol du drapeau.
3. Avec B, ajouter son propre motif au même joueur. Avec A, retirer le sien : le motif de B doit rester.
4. Déconnecter B, ajouter puis retirer un signalement avec A. Reconnecter B, attendre l'échange ou lancer `/storf sync` : l'ancien signalement ne doit pas revenir.
5. Vérifier cible, groupe, raid, annonces et candidatures de recherche, et chat avec un personnage de test consentant. Tester chaque option d'affichage.
6. Entrer puis sortir d'un combat : drapeaux de cadres masqués puis rétablis ; aucune erreur d'action interdite.
7. Recharger avec `/reload` : les données et options doivent persister.

Pour afficher les erreurs du client pendant cette recette : `/console scriptErrors 1` (rétablissement avec `/console scriptErrors 0`).

## Tests locaux

Depuis la racine, avec Lua 5.1+ : `lua tests/run.lua`. Ou installer le runtime de développement isolé : `npm install --prefix .tools --no-save --ignore-scripts fengari-node-cli`, puis lancer `./.tools/node_modules/.bin/fengari tests/run.lua` (`fengari.cmd` sous Windows). Le script doit terminer avec `PASS` ; le CLI Fengari peut renvoyer un code processus nul même en cas d'échec d'assertion.

Tests : validation et sérialisation UTF-8, limites de stockage, isolation entre royaumes, conflits, plusieurs auteurs, retraits persistants, simulation de clients connectés/déconnectés, synchronisation bidirectionnelle négociée, paquets hors ordre, doublons, filtrage des expéditeurs et auteurs, refus d'historiques non sollicités, séparation des guildes, compilation de tous les fichiers Lua. Aucune validation visuelle en client n'est revendiquée.

## Références techniques

Les noms de hooks et signatures sont recoupés avec le [code d'interface Blizzard : LFGList](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_GroupFinder/Mainline/LFGList.lua), le [chat](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrame.lua) et la [documentation générée de C_ChatInfo](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua). Ce miroir de la branche live n'est pas une preuve de compatibilité exhaustive avec le build Forever 70862. Les pools de cadres de groupe ont aussi été recoupés avec le code MoveAny installé sur le client Forever local, sans modification de cette installation.
