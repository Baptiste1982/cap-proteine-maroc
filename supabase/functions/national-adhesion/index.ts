// Envoi d'une adhésion reçue dans le CRM CAP vers l'Espace Animateur national Protéine
// (animateur.ma.caproteine.com), sans navigateur : la fonction rejoue les mêmes requêtes que
// l'assistant « Envoyer le contrat membre pour signature » (relevées le 29/10/2026).
//
//   action "apercu"  : se connecte, LIT seulement, et dit ce qui serait envoyé.
//   action "envoyer" : prospect → entreprise → personne → contrat + abonnement → PDF du contrat.
//                      signature "papier" : contrat papier à imprimer (aucun e-mail ne part) ;
//                      signature "aucune" : s'arrête une fois le contrat généré.
//                      La signature électronique n'est jamais lancée d'ici.
//
// Réservé au superadmin. Identifiants du national : secrets CAP_NATIONAL_IDENTIFIANT et
// CAP_NATIONAL_MOT_DE_PASSE (jamais dans le code). Chaque étape réussie est enregistrée dans
// adhesions.national : un nouvel envoi reprend là où le précédent s'est arrêté, sans doublon.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const B = 'https://animateur.ma.caproteine.com';
const MODES: Record<string, string> = { 'virement|1': '1', 'virement|2': '6', 'cheque|1': '4', 'cheque|2': '8' };
const n = (t: unknown) => String(t ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[-'’.]/g, ' ').replace(/\s+/g, ' ').trim();
const frDate = (iso: string) => /^\d{4}-\d{2}-\d{2}$/.test(iso || '') ? iso.split('-').reverse().join('/') : (iso || '');
const aujourdhui = () => new Date().toLocaleDateString('fr-FR', { timeZone: 'Africa/Casablanca' });

class National {
  jar: Record<string, string> = {};
  async req(method: string, path: string, form?: Record<string, string | string[]>) {
    let body: string | undefined;
    if (form) {
      const p = new URLSearchParams();
      for (const [k, v] of Object.entries(form)) (Array.isArray(v) ? v : [v]).forEach(x => p.append(k, x ?? ''));
      body = p.toString();
    }
    const r = await fetch(B + path, {
      method, redirect: 'manual', body,
      headers: {
        cookie: Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '),
        ...(form ? { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8', 'x-requested-with': 'XMLHttpRequest' } : {}),
      },
    });
    for (const c of r.headers.getSetCookie?.() ?? []) { const kv = c.split(';')[0]; const i = kv.indexOf('='); this.jar[kv.slice(0, i)] = kv.slice(i + 1); }
    return r;
  }
  async json(method: string, path: string, form?: Record<string, string | string[]>) {
    const r = await this.req(method, path, form);
    const t = await r.text();
    try { return JSON.parse(t); } catch { throw new Error(`${path} : réponse inattendue du national (${r.status})`); }
  }
  async ecrire(path: string, form: Record<string, string | string[]>) {
    const j = await this.json('POST', path, form);
    if (!j?.succes) throw new Error(`${path} : refusé par le national${j?.message ? ' — ' + j.message : ''}`);
    return j;
  }
  async connexion(login: string, password: string) {
    await this.req('GET', '/');
    const r = await this.req('POST', '/connexion/extranet', { login, password, autoConnect: 'true' });
    const t = await r.text();
    if (!/Déconnexion/.test(t)) throw new Error('Connexion au CRM national refusée (identifiant ou mot de passe à vérifier dans les secrets).');
    return (t.match(/Bienvenue dans l'espace animateur ([^<]+?)\./) || [])[1] || '';
  }
}

Deno.serve(async (req) => {
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Méthode non autorisée' }, 405);
  const etapes: string[] = [];
  let surErreur: (() => Promise<void>) | null = null;
  try {
    const url = Deno.env.get('SUPABASE_URL')!, anon = Deno.env.get('SUPABASE_ANON_KEY')!, service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: 'Session invalide' }, 401);
    const admin = createClient(url, service);
    const { data: prof } = await admin.from('profiles').select('role').eq('id', user.id).single();
    if (prof?.role !== 'superadmin') return json({ error: 'Réservé au superadmin' }, 403);

    const body = await req.json().catch(() => ({}));
    const { action, adhesion_id } = body;
    const opt = { offre: 'Aucune', justification: '', date_debut: '', signature: 'papier', ...(body.options || {}) };
    if (!['apercu', 'envoyer'].includes(action)) return json({ error: 'Action inconnue' }, 400);
    if (!['papier', 'aucune'].includes(opt.signature)) return json({ error: 'Signature électronique non prise en charge ici' }, 400);

    const { data: a, error: aerr } = await admin.from('adhesions').select('*').eq('id', adhesion_id).single();
    if (aerr || !a) return json({ error: 'Adhésion introuvable' }, 404);
    const d = a.data || {};
    const nat: Record<string, any> = { ...(a.national || {}) };
    surErreur = async () => { if (action === 'envoyer') await admin.from('adhesions').update({ national: { ...nat, etapes, erreur: etapes[etapes.length - 1], maj: new Date().toISOString() } }).eq('id', a.id); };
    const sauver = async (extra: Record<string, unknown> = {}) => {
      Object.assign(nat, extra, { maj: new Date().toISOString(), etapes, erreur: null });
      if (action === 'envoyer') await admin.from('adhesions').update({ national: nat }).eq('id', a.id);
    };

    // Ce qu'il faut absolument avoir pour un contrat.
    const manque = [['ent_nom', 'nom de l\'entreprise'], ['ent_nom_legal', 'nom légal'], ['ent_ice', 'ICE'], ['ent_categorie', 'catégorie juridique'],
      ['metier', 'métier'], ['ent_adresse', 'adresse'], ['ent_cp', 'code postal'], ['ent_ville', 'ville'], ['m_nom', 'nom'], ['m_prenom', 'prénom'],
      ['m_email', 'e-mail'], ['m_tel', 'mobile'], ['m_fonction', 'fonction'], ['reg_mode', 'mode de règlement'], ['reg_fois', 'nombre de versements']]
      .filter(([k]) => !String(d[k] ?? '').trim()).map(([, l]) => l);
    if (manque.length) return json({ error: 'Adhésion incomplète pour le national : ' + manque.join(', ') }, 400);
    if (d.sig_same === false) return json({ error: `Le signataire (${d.s_prenom || ''} ${d.s_nom || ''}) n'est pas le membre : à ajouter à la main dans le national.` }, 400);
    const idMode = MODES[`${d.reg_mode}|${d.reg_fois}`];
    if (!idMode) return json({ error: 'Mode de règlement inconnu du national' }, 400);

    const N = new National();
    const club = await N.connexion(Deno.env.get('CAP_NATIONAL_IDENTIFIANT') || '', Deno.env.get('CAP_NATIONAL_MOT_DE_PASSE') || '');
    etapes.push(`Connecté au national : ${club}`);

    // Listes officielles.
    const cats: any[] = await N.json('GET', '/categorieJuridique/lister?libelle=');
    const cat = cats.find(c => n(c.libelle) === n(d.ent_categorie));
    const mets: any[] = await N.json('GET', '/metier/listerSansConcurrence?libelle=');
    const met = mets.find(m => n(m.libelle) === n(d.metier));
    const offres = Object.values((await N.json('GET', '/offreSpecialeAbonnement/lister?start=0&length=50'))?.response?.tabOffresSpeciales || {}) as any[];
    const offre = offres.find(o => n(o.nom) === n(opt.offre));
    if (!cat) throw new Error(`Catégorie « ${d.ent_categorie} » inconnue du national`);
    if (!met) throw new Error(`Métier « ${d.metier} » inconnu du national`);
    if (!offre) throw new Error(`Offre « ${opt.offre} » inconnue du national`);
    if (offre.id !== 1 && !opt.justification) throw new Error('Une offre spéciale demande une justification');

    // 1 · Prospect (par e-mail), créé s'il n'existe pas.
    const chercher = async () => Object.values(await N.json('POST', '/personneProspectMembre/listerAll', {
      'columns[0][data]': 'email', 'columns[0][searchable]': 'true', 'columns[0][search][value]': d.m_email, start: '0', length: '5',
    }) || {}).find((p: any) => n(p.email) === n(d.m_email)) as any;
    let pers = nat.prospect_id ? (Object.values(await N.json('POST', '/personneProspectMembre/listerAll', {
      'columns[0][data]': 'idPersonne', 'columns[0][searchable]': 'true', 'columns[0][searchOperator]': '=', 'columns[0][search][value]': String(nat.prospect_id), start: '0', length: '5',
    }) || {})[0] as any) : await chercher();
    const entreprisesDe = (p: any) => Object.values(p?.tabEntreprises || {}).flatMap((g: any) => Object.values(g || {})) as any[];
    let ent = pers ? (entreprisesDe(pers).find(e => n(e.nom) === n(d.ent_nom)) || null) : null;
    if (nat.entreprise_id) ent = { id: nat.entreprise_id, nom: d.ent_nom };
    etapes.push(pers ? `Prospect existant au national (n° ${pers.id})` : 'Prospect absent : il sera créé');
    etapes.push(ent ? `Entreprise existante : ${ent.nom} (n° ${ent.id})` : 'Entreprise : une nouvelle sera créée');

    if (action === 'apercu') {
      const page = pers ? await (await N.req('GET', `/prospectMembre/formulaireAjoutAttenteSignature?idPersonne=${pers.id}`)).text() : '';
      return json({
        ok: true, etapes, club,
        plan: {
          prospect: pers ? `${pers.prenom} ${pers.nom} (n° ${pers.id})` : 'à créer', entreprise: ent ? `${ent.nom} (n° ${ent.id})` : 'à créer',
          categorie: cat.libelle.trim(), metier: met.libelle, offre: offre.nom,
          reglement: { '1': 'Virement bancaire en 1 fois', '6': 'Virement bancaire en 2 fois consécutives', '4': 'Chèque en 1 fois', '8': 'Chèque en 2 fois consécutives' }[idMode],
          montant: (page.match(/id="montantTotal"[^>]*value="([^"]*)"/) || [])[1] || '9000.00 (formule standard)',
          date_debut: opt.date_debut || aujourdhui(), signature: opt.signature,
          deja: nat.contrat_id ? `Contrat déjà créé (n° ${nat.contrat_id})` : '',
        },
      });
    }

    if (!pers) {
      const p = await N.ecrire('/personne/enregistrer', {
        'idProfil[]': '10', activiteEntreprise: d.ent_activite || '', idEntreprise: '', id: '', civilite: d.m_civilite || 'Monsieur',
        nom: d.m_nom, prenom: d.m_prenom, fonction: d.m_fonction || '', email: d.m_email, tel1: d.m_tel || '', tel2: d.m_tel2 || '',
        adresse: d.ent_adresse || '', codePostal: d.ent_cp || '', ville: d.ent_ville || '',
      });
      const e = await N.ecrire('/entreprise/enregistrer', { id: '', idPersonne: String(p.id), nom: d.ent_nom, activite: d.ent_activite || '' });
      pers = { id: p.id, identifiant: null, motDePasse: null };
      ent = { id: e.id, nom: d.ent_nom };
      etapes.push(`Prospect créé (n° ${p.id}), entreprise créée (n° ${e.id})`);
      await sauver({ prospect_id: p.id, entreprise_id: e.id });
    } else await sauver({ prospect_id: pers.id });

    // 2 · Entreprise : ce que le national sait déjà est gardé, nos données comblent les vides.
    let ex: any = {};
    if (ent?.id) ex = (await N.json('POST', '/entrepriseProspectMembre/get', { id: String(ent.id) }))?.response?.entrepriseProspectMembre || {};
    const ecarts: string[] = [];
    const v = (cle: string, notre: string) => { const sa = String(ex[cle] ?? '').trim(); if (sa && notre && n(sa) !== n(notre)) ecarts.push(`${cle} : national « ${sa} », adhésion « ${notre} »`); return sa || notre || ''; };
    const metIds = (ex.tabMetiers || []).length ? ex.tabMetiers.map((m: any) => String(m.id)) : [String(met.id)];
    const metLib = (ex.tabMetiers || []).length ? ex.tabMetiers.map((m: any) => m.libelle).join(', ') : met.libelle;
    const adr = v('adresseSiegeSocial', d.ent_adresse), cp = v('codePostalSiegeSocial', d.ent_cp), ville = v('villeSiegeSocial', d.ent_ville);
    const e2 = await N.ecrire('/entrepriseProspectMembre/enregistrer', {
      id: ent?.id ? String(ent.id) : '', 'tabIdsMetier[]': metIds, idCategorieJuridique: String(ex.categorieJuridique?.id || cat.id), informationsGerant: ex.informationsGerant || '',
      adresse: v('adresse', d.ent_adresse) , codePostal: v('codePostal', d.ent_cp), ville: v('ville', d.ent_ville),
      adresseSiegeSocial: adr, codePostalSiegeSocial: cp, villeSiegeSocial: ville,
      nom: v('nom', d.ent_nom), nomLegal: v('nomLegal', d.ent_nom_legal), activite: v('activite', d.ent_activite), villeRcs: v('villeRcs', d.ent_ville_rcs),
      montantCapitalSocial: v('montantCapitalSocial', String(d.ent_capital || '').replace(/[^\d.,]/g, '').replace(',', '.')), siret: v('siret', String(d.ent_ice || '').replace(/\s/g, '')),
      codeNaf: ex.codeNaf || '', numTva: v('numTva', d.ent_patente), urlSiteInternet: v('urlSiteInternet', d.ent_web),
      effectif: v('effectif', d.ent_effectif), anneeCreation: v('anneeCreation', d.ent_annee), telStandard: v('telStandard', d.ent_tel),
    });
    const idEnt = String(e2.id);
    const nomLegal = v('nomLegal', d.ent_nom_legal);
    etapes.push(`Entreprise enregistrée (n° ${idEnt})` + (ecarts.length ? ` — gardé tel quel au national : ${ecarts.join(' ; ')}` : ''));
    await sauver({ entreprise_id: idEnt, ecarts });

    // 3 · Personne membre (identifiants de l'application Protéine générés comme le fait le national).
    let ident = pers.identifiant || nat.identifiant || '', mdp = pers.motDePasse || nat.mot_de_passe || '';
    if (!ident) {
      const base = d.m_prenom.trim().charAt(0).toLowerCase() + d.m_nom.trim().charAt(0).toUpperCase() + d.m_nom.trim().slice(1).toLowerCase().replace(/\s+/g, '');
      ident = base;
      for (let i = 0; i < 20 && (await N.json('POST', '/personneMembre/testerIdentifiant', { identifiant: ident }))?.existe; i++) ident = base + Math.floor(Math.random() * 1000);
      mdp = d.m_prenom.trim().charAt(0).toLowerCase() + d.m_nom.trim().charAt(0).toLowerCase() + Math.floor(Math.random() * 1000000);
    }
    const dirigeant = n(d.m_dirigeant) === 'non' ? 'false' : 'true';
    const p2 = await N.ecrire('/personneProspectMembre/enregistrer', {
      id: String(pers.id), idEntreprise: idEnt, civilite: d.m_civilite || pers.civilite || 'Monsieur', isVouvoye: 'true', isDirigeante: dirigeant,
      nom: d.m_nom.trim().toUpperCase(), prenom: d.m_prenom.trim(), fonction: d.m_fonction || '', email: d.m_email, tel1: d.m_tel || '', tel2: d.m_tel2 || '',
      dateAnniversaire: frDate(d.m_naissance), identifiant: ident, motDePasse: mdp, adresse: adr, codePostal: cp, ville,
    });
    etapes.push(`Personne membre enregistrée (n° ${p2.id}), identifiant ${ident}`);
    await sauver({ personne_id: p2.id, identifiant: ident, mot_de_passe: mdp });

    // 4 · Contrat + abonnement + PDF.
    const page = await (await N.req('GET', `/prospectMembre/formulaireAjoutAttenteSignature?idPersonne=${pers.id}`)).text();
    const montant = (page.match(/id="montantTotal"[^>]*value="([^"]*)"/) || [])[1] || '';
    const idFormule = (page.match(/id="idFormule"[^>]*value="([^"]*)"/) || [])[1] || '';
    if (!montant || !idFormule) throw new Error('Montant ou formule de l\'abonnement introuvable sur la page du national');
    const dateDebut = opt.date_debut || aujourdhui();
    const contrat = (id: string, type: string, fichier: string) => ({
      id, idEntreprise: idEnt, idSignataire: String(p2.id), date: dateDebut, montantTotal: montant, metiers: metLib, nomFichier: fichier, type,
      referenceProcedure: '', referenceSignataire: '', referenceSignatairePrincipal: '', logYousign: '',
    });
    const c1 = await N.ecrire('/contrat/enregistrer', contrat(nat.contrat_id ? String(nat.contrat_id) : '', '', ''));
    await sauver({ contrat_id: c1.id });
    const pareil = d.fac_same !== false;
    const cpF = pareil ? cp : (String(d.f_cpville || '').match(/\d{5}/) || [''])[0];
    const modeLib = { '1': 'Virement bancaire en 1 fois', '6': 'Virement bancaire en 2 fois consécutives', '4': 'Chèque en 1 fois', '8': 'Chèque en 2 fois consécutives' }[idMode];
    const ab = await N.ecrire('/abonnement/enregistrer', {
      id: nat.abonnement_id ? String(nat.abonnement_id) : '', idContrat: String(c1.id), idEntreprise: idEnt, idEntrepriseFacturation: pareil ? idEnt : '',
      idOffreSpeciale: String(offre.id), nomEntrepriseFacturation: pareil ? nomLegal : (d.f_entreprise || ''), adresseFacturation: pareil ? adr : (d.f_adresse || ''),
      codePostalFacturation: cpF, villeFacturation: pareil ? ville : String(d.f_cpville || '').replace(cpF, '').trim(), dateDebut,
      idModeReglement: idMode, justificationOffreSpeciale: opt.justification || '',
      remarque: `Offre spéciale choisie : ${offre.nom}\r\nJustification : ${opt.justification || ''}\r\nRéglement choisi : ${modeLib}`,
      idFormule, montantTotal: montant, renouvellementActif: 'true', relanceActive: 'true',
    });
    await sauver({ abonnement_id: ab.id });
    const pdf = await N.ecrire('/contrat/genererPdf', { id: String(c1.id), idAbonnement: String(ab.id), idEntreprise: idEnt });
    etapes.push(`Contrat n° ${c1.id} généré (${montant} MAD HT, début ${dateDebut}, ${offre.nom}, ${modeLib})`);
    await sauver({ nom_fichier: pdf.nomFichier, url_contrat: pdf.urlContrat, url_contrat_papier: pdf.urlContratPapier, statut: 'contrat_genere' });

    if (opt.signature === 'papier') {
      await N.ecrire('/contrat/enregistrer', contrat(String(c1.id), '1', pdf.nomFichier || ''));
      etapes.push('Signature papier choisie : contrat à imprimer en deux exemplaires.');
      await sauver({ statut: 'contrat_papier', signature: 'papier' });
    }
    await admin.from('adhesions').update({ saisie_proteine_le: new Date().toISOString(), saisie_proteine_par: user.id }).eq('id', a.id);
    return json({ ok: true, etapes, national: nat });
  } catch (e) {
    etapes.push('⛔ ' + String((e as Error)?.message || e));
    await surErreur?.().catch(() => {});
    return json({ ok: false, error: String((e as Error)?.message || e), etapes }, 200);
  }
});
