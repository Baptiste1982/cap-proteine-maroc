#!/usr/bin/env node
/* Robot de saisie en série vers le CRM national Protéine — à lancer sur le PC de JB.
 *
 *   npm i playwright && npx playwright install chromium     (une fois)
 *   node saisir.mjs adhesions-a-saisir-AAAA-MM-JJ.json       (mode prudent : vous cliquez « Enregistrer »)
 *   node saisir.mjs adhesions-a-saisir-AAAA-MM-JJ.json --auto  (le robot enregistre lui-même)
 *
 * Le robot ne connaît AUCUN identifiant : il ouvre un navigateur, vous vous connectez
 * vous-même, puis il remplit les fiches selon correspondance.json. La session reste dans
 * .session/ sur ce PC (ignoré par git). Voir docs/saisie-en-serie-crm-proteine.md.
 */
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const ICI = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const AUTO = args.includes('--auto');
const fichier = args.find(a => !a.startsWith('--'));
if (!fichier) { console.error('Usage : node saisir.mjs <export.json> [--auto]'); process.exit(1); }

const fiches = JSON.parse(fs.readFileSync(fichier, 'utf8'));
const conf = JSON.parse(fs.readFileSync(path.join(ICI, process.env.CORRESPONDANCE || 'correspondance.json'), 'utf8'));
const champs = conf.champs.filter(c => c.label || c.selecteur);
if (!champs.length) { console.error('correspondance.json est vide : à compléter (voir docs/saisie-en-serie-crm-proteine.md).'); process.exit(1); }

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const lignes = rl[Symbol.asyncIterator]();
const demander = async q => { process.stdout.write(q); const r = await lignes.next(); return (r.value || '').trim().toLowerCase(); };

// Trouve le champ : sélecteur CSS s'il est donné, sinon le libellé affiché à l'écran.
function cible(page, c) {
  return c.selecteur ? page.locator(c.selecteur).first() : page.getByLabel(c.label, { exact: false }).first();
}
async function remplir(page, c, valeur) {
  const el = cible(page, c);
  if (!(await el.count())) return 'introuvable';
  if (c.type === 'case') { if (valeur && valeur !== 'Non') await el.check(); return 'ok'; }
  if (c.type === 'liste') {
    // d'abord le libellé exact de l'option, puis sa valeur technique
    try { await el.selectOption({ label: String(valeur) }); return 'ok'; } catch {}
    try { await el.selectOption(String(valeur)); return 'ok'; } catch {}
    return 'option absente';
  }
  await el.fill(String(valeur));
  return 'ok';
}

const ctx = await chromium.launchPersistentContext(path.join(ICI, '.session'), { headless: process.env.HEADLESS === '1', viewport: null, executablePath: process.env.PW_CHROMIUM || undefined });
const page = ctx.pages()[0] || await ctx.newPage();
if (conf.url_connexion) await page.goto(conf.url_connexion);
await demander('\n→ Connectez-vous dans la fenêtre, ouvrez le formulaire de création d\'un membre, puis appuyez sur Entrée ici. ');

const journal = [['ref', 'entreprise', 'resultat', 'champs non remplis']];
let faites = 0;
for (const [i, f] of fiches.entries()) {
  console.log(`\n[${i + 1}/${fiches.length}] ${f.ent_nom} — ${f.m_prenom} ${f.m_nom}`);
  if (i > 0 && conf.url_formulaire) await page.goto(conf.url_formulaire);
  const manques = [];
  for (const c of champs) {
    const v = f[c.cle]; if (v === '' || v == null) continue;
    const r = await remplir(page, c, v).catch(e => 'erreur : ' + e.message.split('\n')[0]);
    if (r !== 'ok') manques.push(`${c.label || c.selecteur} (${r})`);
  }
  if (manques.length) console.log('  ⚠ non remplis : ' + manques.join(' ; '));
  let rep;
  if (AUTO && !manques.length) {
    await page.getByRole('button', { name: conf.bouton_enregistrer || 'Enregistrer' }).first().click();
    await page.waitForLoadState('networkidle').catch(() => {});
    rep = '';
  } else {
    rep = await demander('  Vérifiez la fiche, cliquez « Enregistrer » dans le navigateur, puis Entrée (s = sauter, q = arrêter) : ');
  }
  if (rep === 'q') { journal.push([f.id, f.ent_nom, 'arrêté', manques.join(' ; ')]); break; }
  journal.push([f.id, f.ent_nom, rep === 's' ? 'sautée' : 'saisie', manques.join(' ; ')]);
  if (rep !== 's') faites++;
  if (i < fiches.length - 1 && !conf.url_formulaire && !AUTO)
    await demander('  Ouvrez un nouveau formulaire vide, puis Entrée. ');
}

const nom = path.join(path.dirname(path.resolve(fichier)), 'journal-saisie-' + new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-') + '.csv');
fs.writeFileSync(nom, '﻿' + journal.map(r => r.map(x => `"${String(x).replace(/"/g, '""')}"`).join(';')).join('\n'));
console.log(`\n${faites} fiche(s) saisie(s). Journal : ${nom}`);
console.log('Pensez à « Marquer saisie » dans le CRM CAP pour ces adhésions.');
rl.close(); await ctx.close();
