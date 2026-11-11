// Annonce sur Discord les addons dont la version (## Version du .toc) a changé
// entre deux commits. Lancé par le workflow « Annoncer les addons ».
//
//   AVANT, APRES      : les deux commits à comparer
//   DISCORD_WEBHOOK   : l'URL du webhook ; si elle manque, le message est
//                       seulement affiché (pratique pour tester en local)
//
// Test en local :  AVANT=HEAD~3 APRES=HEAD node .github/scripts/annonce-addons.js

const { execFileSync } = require('child_process');

const REPO_URL = 'https://github.com/Chaedd/troposphere-addons';
const COULEUR_NOUVEAU = 0x57f287; // vert
const COULEUR_MAJ = 0x5865f2; // bleu Discord

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
}

function lireFichier(commit, chemin) {
  try {
    return git('show', `${commit}:${chemin}`);
  } catch {
    return null;
  }
}

function commitExiste(commit) {
  try {
    return git('cat-file', '-t', commit).trim() === 'commit';
  } catch {
    return false;
  }
}

// Champs « ## Clé: valeur » d'un .toc, sans BOM ni codes couleur WoW (|cffxxxxxx … |r).
function lireToc(texte) {
  const champs = {};
  for (const ligne of texte.replace(/^﻿/, '').split(/\r?\n/)) {
    const m = ligne.match(/^##\s*([^:]+):\s*(.*)$/);
    if (m) champs[m[1].trim()] = m[2].replace(/\|c[0-9a-fA-F]{8}|\|r/g, '').trim();
  }
  return champs;
}

// Le .toc principal de chaque addon : addons/<Nom>/<Nom>.toc, sinon le premier trouvé.
function tocsDesAddons(commit) {
  const fichiers = git('ls-tree', '-r', '--name-only', commit, '--', 'addons/')
    .split('\n')
    .filter((f) => /^addons\/[^/]+\/[^/]+\.toc$/i.test(f));
  const parAddon = new Map();
  for (const f of fichiers) {
    const dossier = f.split('/')[1];
    const estPrincipal = f.toLowerCase() === `addons/${dossier}/${dossier}.toc`.toLowerCase();
    if (!parAddon.has(dossier) || estPrincipal) parAddon.set(dossier, f);
  }
  return parAddon;
}

function couper(texte, max) {
  return texte.length > max ? texte.slice(0, max - 1) + '…' : texte;
}

function nouveautes(avant, apres, dossier) {
  const sujets = git('log', '--no-merges', '--format=%s', `${avant}..${apres}`, '--', `addons/${dossier}/`)
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean)
    .slice(0, 8);
  return sujets.map((s) => `• ${couper(s, 200)}`).join('\n');
}

async function envoyer(embeds) {
  const webhook = process.env.DISCORD_WEBHOOK;
  // Discord accepte 10 encadrés au plus par message.
  for (let i = 0; i < embeds.length; i += 10) {
    const message = { username: 'Troposphère', embeds: embeds.slice(i, i + 10) };
    if (!webhook) {
      console.log('DISCORD_WEBHOOK absent, message non envoyé :\n' + JSON.stringify(message, null, 2));
      continue;
    }
    const rep = await fetch(webhook, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    });
    if (!rep.ok) throw new Error(`Discord a répondu ${rep.status} : ${await rep.text()}`);
  }
}

async function main() {
  const avant = process.env.AVANT;
  const apres = process.env.APRES || 'HEAD';

  // Premier push d'une branche, ou commit « avant » inconnu (historique réécrit) : rien à comparer.
  if (!avant || /^0+$/.test(avant) || !commitExiste(avant)) {
    console.log('Pas de commit précédent à comparer, aucune annonce.');
    return;
  }

  const tocsAvant = tocsDesAddons(avant);
  const embeds = [];

  for (const [dossier, chemin] of tocsDesAddons(apres)) {
    const toc = lireToc(lireFichier(apres, chemin) || '');
    const version = toc.Version;
    if (!version) continue;

    const ancienChemin = tocsAvant.get(dossier);
    const ancienne = ancienChemin ? lireToc(lireFichier(avant, ancienChemin) || '').Version : null;
    if (ancienne === version) continue;

    const nom = toc.Title || dossier;
    const estNouveau = !ancienChemin;
    const lignes = [];
    if (toc.Notes) lignes.push(`*${couper(toc.Notes, 300)}*`);
    const liste = nouveautes(avant, apres, dossier);
    if (liste) lignes.push('', '**Nouveautés**', liste);
    lignes.push('', 'Mets-le à jour depuis l\'app Troposphère.');

    embeds.push({
      title: couper(estNouveau ? `🆕 Nouvel addon : ${nom} ${version}` : `⬆️ ${nom} passe en ${version}`, 256),
      url: `${REPO_URL}/tree/main/addons/${encodeURIComponent(dossier)}`,
      description: couper(lignes.join('\n'), 4000),
      color: estNouveau ? COULEUR_NOUVEAU : COULEUR_MAJ,
      fields: ancienne ? [{ name: 'Version', value: `${ancienne} → **${version}**`, inline: true }] : [],
      footer: toc.Author ? { text: `par ${toc.Author}` } : undefined,
      timestamp: new Date().toISOString(),
    });
  }

  if (embeds.length === 0) {
    console.log('Aucune version d\'addon n\'a changé, aucune annonce.');
    return;
  }
  await envoyer(embeds);
  console.log(`${embeds.length} addon(s) annoncé(s).`);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
