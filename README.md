# Troposphère : addons World of Warcraft

<img src="icon.png" width="128" alt="Icône de Troposphère : un rat astronaute" />

Les addons de ce dépôt s'installent et se mettent à jour en un clic avec **Troposphère**.

## Installer Troposphère

1. Télécharger le dernier `Troposphere-Setup-x.y.z.exe` dans les [Releases](https://github.com/Chaedd/troposphere-addons/releases/latest) et le lancer.
2. Si Windows affiche « Windows a protégé votre ordinateur », cliquer sur **Informations complémentaires → Exécuter quand même**.
3. Cliquer sur **Installer** à côté d'un addon, puis taper `/reload` en jeu.

## Publier un addon

Chaque sous-dossier de `addons/` est un addon, copié tel quel dans `Interface\AddOns`. Le titre, la description, l'auteur et la version affichés dans l'app viennent du `.toc` (`## Title:`, `## Notes:`, `## Author:`, `## Version:`).

Dès qu'un changement est poussé sur `main`, Troposphère propose la mise à jour aux joueurs.
