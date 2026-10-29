#!/usr/bin/env node
/* Robot de saisie en série vers le CRM national Protéine (Espace Animateur) — à lancer sur le PC de JB.
 *
 *   npm i playwright && npx playwright install chromium        (une fois)
 *   node saisir.mjs adhesions-a-saisir-AAAA-MM-JJ.json --essai   (répétition à blanc : rien n'est écrit au national)
 *   node saisir.mjs adhesions-a-saisir-AAAA-MM-JJ.json           (mode prudent : pause à chaque étape)
 *   node saisir.mjs adhesions-a-saisir-AAAA-MM-JJ.json --auto    (enchaîne les étapes 1 à 3 sans pause)
 *
 * Pour chaque adhésion : retrouve le prospect (par son email) ou le crée, ouvre « Envoyer le contrat
 * membre pour signature », remplit Préparation, Entreprise, Personne membre et Contrat, puis S'ARRÊTE :
 * le robot n'enregistre jamais le contrat et ne lance jamais la signature. C'est vous qui relisez et cliquez.
 *
 * Connexion : le robot ne stocke aucun identifiant. Soit vous vous connectez vous-même dans la fenêtre,
 * soit vous posez CAP_NATIONAL_IDENTIFIANT et CAP_NATIONAL_MOT_DE_PASSE dans l'environnement du PC.
 * La session reste dans .session/ sur ce PC (ignoré par git). Correspondance des champs : correspondance.json.
 */
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const ICI = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const AUTO = args.includes('--auto');
const ESSAI = args.includes('--essai');
const fichier = args.find(a => !a.startsWith('--'));
if (!fichier) { console.error('Usage : node saisir.mjs <adhesions-a-saisir.json> [--essai | --auto]'); process.exit(1); }

const fiches = JSON.parse(fs.readFileSync(fichier, 'utf8'));
const C = JSON.parse(fs.readFileSync(path.join(ICI, process.env.CORRESPONDANCE || 'correspondance.json'), 'utf8'));
const ORIGINE = new URL(C.url_accueil).origin;

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const lignes = rl[Symbol.asyncIterator]();
const demander = async q => { process.stdout.write(q); const r = await lignes.next(); return (r.value || '').trim().toLowerCase(); };
const pause = async q => (AUTO ? '' : demander(q));
const dire = m => console.log('  ' + m);
// CAPTURES=<dossier> : une capture d'écran à chaque étape (pour vérifier une répétition).
const photo = async nom => { if (process.env.CAPTURES) await page.screenshot({ path: path.join(process.env.CAPTURES, nom + '.png'), fullPage: true }).catch(() => {}); };
const attendre = ms => new Promise(r => setTimeout(r, ms));
const sansAccent = t => String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[-'’.]/g, ' ').replace(/\s+/g, ' ').trim();

/* ─── Navigateur ───────────────────────────────────────────────────────── */
const ctx = await chromium.launchPersistentContext(path.join(ICI, '.session'), {
  headless: process.env.HEADLESS === '1', viewport: process.env.HEADLESS === '1' ? { width: 1400, height: 1000 } : null,
  executablePath: process.env.PW_CHROMIUM || undefined,
});
const page = ctx.pages()[0] || await ctx.newPage();

// Répétition à blanc : seules les LECTURES partent au national. Les deux enregistrements dont l'assistant a
// besoin pour avancer (entreprise, personne) reçoivent une fausse réponse ; tout le reste est bloqué.
const bloquees = [];
if (ESSAI) {
  await ctx.route(ORIGINE + '/**', r => {
    const req = r.request(), chemin = new URL(req.url()).pathname;
    if (req.method() === 'GET' || /\/(lister|liste|get|charger|rechercher|afficher|select|load|tester)[A-Za-z]*$/i.test(chemin)
        || /^\/(connexion|index)\//.test(chemin)) return r.continue();
    if (chemin === '/entrepriseProspectMembre/enregistrer') return r.fulfill({ json: { succes: true, id: 999999901 } });
    if (chemin === '/personneProspectMembre/enregistrer' && /idEntreprise=999999901/.test(req.postData() || ''))
      return r.fulfill({ json: { succes: true, id: 999999902 } });
    bloquees.push(req.method() + ' ' + chemin);
    return r.abort();
  });
  console.log('\n🧪 RÉPÉTITION À BLANC : aucune écriture ne partira vers le CRM national.');
}

async function connexion() {
  await page.goto(C.url_accueil, { waitUntil: 'networkidle' });
  if (!(await page.locator('input[name=login]').isVisible().catch(() => false))) return;
  const id = process.env.CAP_NATIONAL_IDENTIFIANT, mdp = process.env.CAP_NATIONAL_MOT_DE_PASSE;
  if (id && mdp) {
    await page.fill('input[name=login]', id); await page.fill('input[name=password]', mdp);
    await Promise.all([page.waitForLoadState('networkidle'), page.click('button[type=submit]')]);
  } else {
    await demander('\n→ Connectez-vous dans la fenêtre du navigateur, puis appuyez sur Entrée ici. ');
  }
  if (await page.locator('input[name=login]').isVisible().catch(() => false)) throw new Error('Connexion refusée par le CRM national.');
}

async function menu(...noms) {
  await page.goto(C.url_accueil, { waitUntil: 'networkidle' });
  await page.locator('.fa-bars').first().click().catch(() => {});
  await attendre(600);
  for (const n of noms) { await page.locator('a:visible', { hasText: n }).first().click(); await page.waitForLoadState('networkidle'); await attendre(1200); }
}

async function cadre(morceau) {
  for (let i = 0; i < 40; i++) {
    const f = page.frames().find(x => x.url().includes(morceau));
    if (f && await f.evaluate(() => !!window.jQuery && document.readyState === 'complete').catch(() => false)) return f;
    await attendre(500);
  }
  throw new Error('Fenêtre introuvable : ' + morceau);
}

/* ─── Outils exécutés DANS les fenêtres du national (jQuery y est chargé) ─ */
// Pose des valeurs. vides=true : ne remplace pas une valeur déjà présente et différente (elle est signalée).
async function poser(fr, champs, d, vides) {
  return fr.evaluate(({ champs, d, vides }) => {
    const $ = window.jQuery, out = { mis: [], ecarts: [], absents: [] };
    for (const [id, v] of Object.entries(champs)) {
      if (v === '' || v == null) continue;
      const el = $(`[oldid='${id}']`).add(`#${id}`).first();
      if (!el.length) { out.absents.push(id); continue; }
      const cur = String(el.val() || '').trim();
      if (vides && cur && cur.toLowerCase() !== String(v).toLowerCase()) { out.ecarts.push(`${id} : national « ${cur} », adhésion « ${v} »`); continue; }
      el.val(String(v)).trigger('change'); out.mis.push(id);
    }
    return out;
  }, { champs, d, vides });
}
// Choisit une valeur dans une liste à recherche (select2) d'après son libellé exact, via la liste du national.
async function choisir(fr, id, url, libelle) {
  return fr.evaluate(({ id, url, libelle }) => {
    const $ = window.jQuery;
    const n = t => String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[-'’.]/g, ' ').replace(/\s+/g, ' ').trim();
    const liste = $.ajax({ url, data: { libelle }, async: false, dataType: 'json' }).responseJSON || [];
    const hit = liste.find(x => n(x.libelle) === n(libelle));
    if (!hit) return null;
    const el = $('#' + id);
    if (!el.find(`option[value='${hit.id}']`).length) el.append(new Option(hit.libelle.trim(), hit.id, true, true));
    el.val(el.prop('multiple') ? [String(hit.id)] : String(hit.id)).trigger('change');
    return hit.libelle.trim();
  }, { id, url, libelle });
}
const etape = fr => fr.evaluate(() => window.jQuery('#formContact').steps('getCurrentIndex'));
const erreurs = fr => fr.evaluate(() => [...document.querySelectorAll('label.error')].filter(e => e.offsetParent && e.textContent.trim())
  .map(e => (e.closest('.form-group')?.querySelector('label:not(.error)')?.textContent.trim() || '?') + ' : ' + e.textContent.trim()));
const fermerDialogue = fr => fr.evaluate(() => { const $ = window.jQuery; const t = $('#dialogPersonneMini:visible .modal-body').text().trim(); $('#dialogPersonneMini').modal('hide'); return t; });

// Passe à l'étape suivante ; si le national refuse, on laisse la main pour corriger dans le navigateur.
async function avancer(fr, vers) {
  await fr.evaluate(() => window.jQuery('#formContact').steps('next'));
  await attendre(1500);
  while (await etape(fr) < vers) {
    const errs = await erreurs(fr), dlg = await fermerDialogue(fr);
    if (dlg) dire('ℹ ' + dlg.replace(/\s+/g, ' ').slice(0, 200));
    if (errs.length) dire('⚠ À corriger : ' + errs.join(' ; '));
    const r = await demander(`  Corrigez dans le navigateur, puis Entrée pour réessayer (s = sauter la fiche) : `);
    if (r === 's') return false;
    if (await etape(fr) >= vers) break;
    await fr.evaluate(() => window.jQuery('#formContact').steps('next')); await attendre(1500);
  }
  return true;
}

/* ─── Prospect ─────────────────────────────────────────────────────────── */
async function trouverProspect(email) {
  const champ = page.locator('#tableProspectMembreSansContrat_filter input');
  await champ.fill(''); await champ.fill(email); await attendre(2500);
  const ligne = page.locator('#tableProspectMembreSansContrat tbody tr').filter({ hasText: email });
  return (await ligne.count()) ? ligne.first() : null;
}
async function enAttenteDeSignature(email) {
  await page.click('#btTabProspectMembreAttenteSignature'); await attendre(2000);
  const champ = page.locator('#tableProspectMembreAttenteSignature_filter input');
  let trouve = false;
  if (await champ.count()) { await champ.fill(email); await attendre(2000); trouve = (await page.locator('#tableProspectMembreAttenteSignature tbody tr').filter({ hasText: email }).count()) > 0; }
  await page.click('#btTabProspectMembreSansContrat'); await attendre(1200);
  return trouve;
}
async function creerProspect(d) {
  await page.click('#btAjouterProspectSansContrat');
  const fr = await cadre(C.prospect.cadre);
  const champs = Object.fromEntries(Object.entries(C.prospect.champs).map(([id, cle]) => [id, d[cle]]));
  const r = await poser(fr, champs, d, false);
  if (r.absents.length) dire('⚠ Champs absents du formulaire prospect : ' + r.absents.join(', '));
  await photo('0-prospect');
  dire('Formulaire « nouveau prospect » rempli. Si le national propose une entreprise existante dans la liste, choisissez-la.');
  if (ESSAI) { dire('🧪 À blanc : le prospect n\'est pas créé, la suite de cette fiche est impossible.'); return false; }
  const rep = await pause('  Vérifiez puis Entrée pour enregistrer le prospect (s = sauter) : ');
  if (rep === 's') return false;
  await fr.click('#' + C.prospect.bouton_enregistrer);
  await attendre(3000);
  return true;
}

/* ─── Une adhésion ─────────────────────────────────────────────────────── */
async function saisir(d) {
  const reg = C.assistant.contrat.mode_reglement[`${d.reg_mode}|${d.reg_fois}`];
  await menu('Membres et Prospects', 'Gestion Prospects');
  if (await enAttenteDeSignature(d.m_email)) return 'déjà en attente de signature au national';
  let ligne = await trouverProspect(d.m_email);
  if (!ligne) {
    dire('Prospect absent : création.');
    if (!(await creerProspect(d))) return ESSAI ? 'à blanc : prospect non créé' : 'sautée';
    await menu('Membres et Prospects', 'Gestion Prospects');
    ligne = await trouverProspect(d.m_email);
    if (!ligne) return 'prospect introuvable après création';
  } else dire('Prospect déjà présent au national.');

  await ligne.locator('button, a').first().click(); await attendre(600);
  await page.locator('a:visible', { hasText: 'Envoyer le contrat membre pour signature' }).first().click();
  const fr = await cadre(C.assistant.cadre);

  // 1 · Préparation : l'entreprise déjà rattachée si son nom correspond, sinon une nouvelle.
  const boutons = await fr.locator('.btChoixEntreprise, button, a.btn').allInnerTexts();
  const existante = boutons.find(t => /^choisir /i.test(t.trim()) && sansAccent(t).includes(sansAccent(d.ent_nom)));
  await fr.locator('button, a', { hasText: existante ? existante.trim() : 'Créer une nouvelle entreprise' }).first().click();
  await attendre(1500);
  dire(existante ? `1 · Entreprise existante choisie (${existante.trim().slice(8)}).` : '1 · Nouvelle entreprise.');

  // 2 · Entreprise : recherche par ICE (complète ce que le national connaît), puis nos données dans les cases vides.
  const E = C.assistant.entreprise;
  await fr.evaluate(({ id, ice }) => { const $ = window.jQuery; $(`[oldid='${id}']`).add(`#${id}`).first().val(ice); try { window.rechercheInfoBddSirene(); } catch (e) {} }, { id: E.recherche_ice, ice: d.ent_ice });
  await attendre(2500);
  const dlg = await fermerDialogue(fr); if (dlg) dire('ℹ ' + dlg.replace(/\s+/g, ' ').slice(0, 160));
  for (const [id, l] of Object.entries(E.listes)) {
    const lib = await choisir(fr, id, l.url, d[l.cle]);
    dire(lib ? `   ${id} : ${lib}` : `⚠ ${id} : « ${d[l.cle]} » introuvable dans la liste du national, à choisir à la main.`);
  }
  const ent = await poser(fr, Object.fromEntries(Object.entries(E.champs).map(([id, cle]) => [id, d[cle]])), d, true);
  await fr.evaluate(() => { const $ = window.jQuery, c = $("[oldid='checkBoxAdresseIdentique'], #checkBoxAdresseIdentique").first(); c.prop('checked', true).trigger('change').trigger('ifChecked'); });
  if (ent.ecarts.length) dire('⚠ Différences gardées telles que le national les connaît : ' + ent.ecarts.join(' ; '));
  dire(`2 · Entreprise remplie (${ent.mis.length} champs).`); await photo('2-entreprise');
  if ((await pause('  Relisez l\'étape Entreprise, puis Entrée pour enregistrer et passer (s = sauter) : ')) === 's') return 'sautée';
  if (!(await avancer(fr, 2))) return 'sautée à l\'étape Entreprise';

  // 3 · Personne membre.
  const P = C.assistant.personne;
  const pers = { ...Object.fromEntries(Object.entries(P.champs).map(([id, cle]) => [id, d[cle]])), isVouvoye: P.vouvoiement };
  pers.isDirigeante = sansAccent(d.m_dirigeant) === 'oui' ? 'true' : sansAccent(d.m_dirigeant) === 'non' ? 'false' : '';
  const pr = await poser(fr, pers, d, false);
  await fr.evaluate(() => window.jQuery('#btCopierAdresseEntreprise').click());
  dire(`3 · Personne membre remplie (${pr.mis.length} champs).`); await photo('3-personne');
  if ((await pause('  Relisez l\'étape Personne membre, puis Entrée pour enregistrer et passer (s = sauter) : ')) === 's') return 'sautée';
  await fr.evaluate(() => window.jQuery('#formContact').steps('next')); await attendre(2000);
  // Le national demande « ajouter d'autres personnes ? » : non.
  if (await fr.evaluate(() => parseInt(window.jQuery("[oldid='idPersonne'], #idPersonne").first().val()) > 0)) {
    await fr.evaluate(() => { const $ = window.jQuery; $('#dialogPersonneMini').modal('hide'); $('#btAnnulerAjoutAutrePersonne').click(); });
    await attendre(1500);
  }
  if (await etape(fr) < 3 && !(await avancer(fr, 3))) return 'sautée à l\'étape Personne membre';

  // 4 · Contrat : rempli, JAMAIS enregistré par le robot.
  const contrat = await fr.evaluate(({ d, offre, reg }) => {
    const $ = window.jQuery, out = [];
    const n = t => String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
    const idEnt = $("[oldid='idEntreprise'], #idEntreprise").first().val();
    // Signataire : le membre lui-même si l'adhésion le dit.
    const sig = $('#idPersonneSignataire');
    if (parseInt(sig.val()) > 0) out.push('signataire : ' + sig.find('option:selected').text().trim());
    else if (d.sig_same !== 'Non') {
      const pers = $.ajax({ type: 'POST', url: '/personne/listerFromEntreprise', data: { nom: '', idEntreprise: idEnt }, async: false, dataType: 'json' }).responseJSON || [];
      const p = pers.find(x => n(x.nom) === n(d.m_nom) && n(x.prenom) === n(d.m_prenom));
      if (p) { const el = $('#idPersonneSignataire'); el.append(new Option(`${p.civilite} ${p.prenom} ${p.nom}, en qualité de ${p.fonction}`, p.id, true, true)).trigger('change'); out.push('signataire : le membre'); }
      else out.push('⚠ signataire à choisir à la main (membre introuvable dans la liste du national)');
    } else out.push(`⚠ signataire différent du membre (${d.s_prenom} ${d.s_nom}) : à ajouter avec le bouton + du national`);
    const met = $("[oldid='metiersContrat'], #metiersContrat").first(); if (!met.val()) met.val(d.metier);
    const offres = $.ajax({ url: '/offreSpecialeAbonnement/lister', data: { start: 0, length: 50, search: { value: '' }, columns: [{ data: 'nom' }] }, async: false, dataType: 'json' }).responseJSON;
    const o = Object.values(offres?.response?.tabOffresSpeciales || {}).find(x => n(x.nom) === n(offre));
    if (o) { const el = $('#tabIdsOffreSpeciale'); if (!el.find(`option[value='${o.id}']`).length) el.append(new Option(o.nom, o.id, true, true)); el.val(String(o.id)).trigger('change'); out.push('offre : ' + o.nom); }
    else out.push('⚠ offre spéciale à choisir à la main');
    if (reg) { $("[oldid='modeReglement'], #modeReglement").first().val(reg).trigger('change'); out.push('règlement : ' + $("[oldid='modeReglement'], #modeReglement").first().find('option:selected').text()); }
    else out.push('⚠ mode de règlement à choisir à la main');
    const pareil = d.fac_same !== 'Non';
    const radio = $(`[oldid='cotisationExterieure${pareil ? 'True' : 'False'}'], #cotisationExterieure${pareil ? 'True' : 'False'}`).first();
    if (radio.iCheck) radio.iCheck('check'); else radio.prop('checked', true).trigger('ifChecked');
    if (!pareil) {
      const cp = (d.f_cpville || '').match(/\d{5}/)?.[0] || '';
      $("[oldid='nomEntrepriseCotisation'], #nomEntrepriseCotisation").first().val(d.f_entreprise);
      $("[oldid='adresseEntrepriseCotisation'], #adresseEntrepriseCotisation").first().val(d.f_adresse);
      $("[oldid='codePostalEntrepriseCotisation'], #codePostalEntrepriseCotisation").first().val(cp);
      $("[oldid='villeEntrepriseCotisation'], #villeEntrepriseCotisation").first().val((d.f_cpville || '').replace(cp, '').trim());
      out.push('facturation : ' + d.f_entreprise);
    } else out.push('facturation : l\'entreprise du membre');
    out.push('début : ' + $("[oldid='dateDebutContrat'], #dateDebutContrat").first().val());
    return out;
  }, { d, offre: C.assistant.contrat.offre_speciale, reg });
  dire('4 · Contrat rempli : ' + contrat.join(' · ')); await photo('4-contrat');
  dire('⛔ Le robot s\'arrête ici. Relisez le contrat, enregistrez-le et lancez la signature vous-même.');
  return ESSAI ? 'à blanc : rempli jusqu\'au contrat' : 'remplie jusqu\'au contrat (à enregistrer et signer)';
}

/* ─── Boucle ───────────────────────────────────────────────────────────── */
await connexion();
const bandeau = (await page.locator('text=Bienvenue dans').first().textContent().catch(() => '')) || '';
console.log('\nConnecté : ' + bandeau.replace(/\s+/g, ' ').trim());
const journal = [['ref', 'entreprise', 'membre', 'résultat']];
for (const [i, d] of fiches.entries()) {
  console.log(`\n[${i + 1}/${fiches.length}] ${d.ent_nom} — ${d.m_prenom} ${d.m_nom}${d.club ? ' (club ' + d.club + ')' : ''}`);
  let res;
  try { res = await saisir(d); } catch (e) { res = 'erreur : ' + e.message.split('\n')[0]; }
  dire('→ ' + res);
  journal.push([d.id, d.ent_nom, `${d.m_prenom} ${d.m_nom}`, res]);
  if (i < fiches.length - 1) {
    const r = await demander('\n  Entrée = fiche suivante (q = arrêter) : ');
    if (r === 'q') break;
    await page.keyboard.press('Escape').catch(() => {});
  }
}
if (ESSAI && bloquees.length) console.log('\n🧪 Écritures bloquées pendant la répétition : ' + [...new Set(bloquees)].join(' ; '));
const nom = path.join(path.dirname(path.resolve(fichier)), 'journal-saisie-' + new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-') + '.csv');
fs.writeFileSync(nom, '﻿' + journal.map(r => r.map(x => `"${String(x ?? '').replace(/"/g, '""')}"`).join(';')).join('\n'));
console.log(`\nJournal : ${nom}`);
console.log('Pensez à « Marquer saisie » dans le CRM CAP pour les adhésions dont le contrat est parti.');
rl.close(); await ctx.close();
