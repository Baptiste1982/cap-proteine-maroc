// Suivi des demandes d'adhésion au CRM national Protéine (animateur.ma.caproteine.com).
//   action "verifier" (défaut) :
//     1. Annuaire : chaque demande reçue (non archivée) qui n'a pas encore de contact au national y est créée
//        (personne + entreprise, profil prospect), sinon retrouvée par son e-mail. 10 au plus par passage.
//     2. Signatures : pour chaque contrat envoyé et pas encore signé, on lit la liste « En attente de signature »
//        et la liste des membres. Contrat marqué signé, ou sorti de l'attente avec l'entreprise devenue membre
//        → national.signe_le, et notification aux superadmins. Sinon, l'état de signature est noté.
// Appel : session superadmin (bouton du CRM) ou en-tête x-suivi-jeton (coffre : national_suivi_jeton, appel programmé).
// Identifiants du national : secrets CAP_NATIONAL_IDENTIFIANT / CAP_NATIONAL_MOT_DE_PASSE.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-suivi-jeton', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const B = 'https://animateur.ma.caproteine.com';
const VAPID_PUBLIC = 'BAKkMOISOmM62avwTzeE81_l592rvg9O-AiLBct4eGf7Xovoy_OswNK0lnQ0yokt6VDoRkL927x4LS5bFYnWbZM';
const n = (t: unknown) => String(t ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
const COL_ATTENTE = ['', 'idPersonne', 'idEntreprise', 'nomEntreprise', 'activiteEntreprise', '', '', '', '', 'prenomPersonne', 'nomPersonne', 'fonctionPersonne', 'emailPersonne', 'tel1Personne', 'tel2Personne', 'adresseEntreprise', 'codePostalEntreprise', 'villeEntreprise'];
const COL_MEMBRES = ['', 'idPersonne', 'idEntreprise', 'nomEntreprise', 'activiteEntreprise', '', '', '', 'dateRelancePaiement', '', 'prenomPersonne', 'nomPersonne', 'fonctionPersonne', 'emailPersonne', 'tel1Personne', 'tel2Personne', 'adresseEntreprise', 'codePostalEntreprise', 'villeEntreprise'];

class National {
  jar: Record<string, string> = {};
  async req(method: string, path: string, form?: Record<string, string>) {
    const body = form ? new URLSearchParams(form).toString() : undefined;
    const r = await fetch(B + path, { method, redirect: 'manual', body, headers: { cookie: Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '), ...(form ? { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8', 'x-requested-with': 'XMLHttpRequest' } : {}) } });
    for (const c of r.headers.getSetCookie?.() ?? []) { const kv = c.split(';')[0]; const i = kv.indexOf('='); this.jar[kv.slice(0, i)] = kv.slice(i + 1); }
    return r;
  }
  async json(method: string, path: string, form?: Record<string, string>) {
    const r = await this.req(method, path, form); const t = await r.text();
    try { return JSON.parse(t); } catch { throw new Error(`${path} : réponse inattendue du national (${r.status})`); }
  }
  async ecrire(path: string, form: Record<string, string>) {
    const j = await this.json('POST', path, form);
    if (!j?.succes) throw new Error(`${path} : refusé par le national${j?.message ? ' — ' + j.message : ''}`);
    return j;
  }
  async connexion() {
    await this.req('GET', '/');
    const r = await this.req('POST', '/connexion/extranet', { login: Deno.env.get('CAP_NATIONAL_IDENTIFIANT') || '', password: Deno.env.get('CAP_NATIONAL_MOT_DE_PASSE') || '', autoConnect: 'true' });
    if (!/Déconnexion/.test(await r.text())) throw new Error('Connexion au CRM national refusée (identifiants à vérifier dans les secrets).');
  }
  // Liste DataTables lue comme la page du national : on ouvre l'écran, puis on demande ses lignes.
  async liste(index: string, liste: string, colonnes: string[], nb = 500) {
    await this.req('GET', index);
    const f: Record<string, string> = { draw: '1', start: '0', length: String(nb), 'search[value]': '', 'search[regex]': 'false', 'order[0][column]': '1', 'order[0][dir]': 'desc' };
    colonnes.forEach((c, i) => Object.assign(f, { [`columns[${i}][data]`]: c, [`columns[${i}][name]`]: c, [`columns[${i}][searchable]`]: c ? 'true' : 'false', [`columns[${i}][orderable]`]: c ? 'true' : 'false', [`columns[${i}][search][value]`]: '', [`columns[${i}][search][regex]`]: 'false' }));
    const j = await this.json('POST', liste, f);
    if (!j?.success) throw new Error(`${liste} : lecture refusée par le national`);
    const v = Object.values(j.response || {}).find(x => x && typeof x === 'object') as any;
    return (Array.isArray(v) ? v : Object.values(v || {})) as any[];
  }
}

// Invitations du national (liste « Gestion de mes invitations »), la plus récente d'abord.
async function invitationsListe(N: National): Promise<any[]> {
  await N.req('GET', '/invitation');
  const cols = ['', 'id', 'libelleType', 'dateDebut', 'dateFin', 'dateEnvoi', 'nomHote'];
  const f: Record<string, string> = { draw: '1', start: '0', length: '50', 'search[value]': '', 'search[regex]': 'false', 'order[0][column]': '1', 'order[0][dir]': 'desc' };
  cols.forEach((c, i) => Object.assign(f, { [`columns[${i}][data]`]: c, [`columns[${i}][name]`]: c, [`columns[${i}][searchable]`]: c ? 'true' : 'false', [`columns[${i}][orderable]`]: c ? 'true' : 'false', [`columns[${i}][search][value]`]: '', [`columns[${i}][search][regex]`]: 'false' }));
  const j = await N.json('POST', '/invitation/lister', f);
  return Array.isArray(j?.data) ? j.data : [];
}

// Écrit une invitation au national en reprenant le formulaire d'une invitation existante (body.source).
// body.maj = true : on modifie cette invitation (dates, lieu, type) ; sinon on en crée une nouvelle (forcerCreation).
async function invitationEcrire(N: National, body: any): Promise<any> {
  const t = await (await N.req('GET', '/invitation/formulaireNew?id=' + encodeURIComponent(String(body.source)) + (body.maj ? '' : '&forcerCreation=true'))).text();
  const dec = (x: string) => x.replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d)).replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/&quot;/g, '"').replace(/&#039;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, '\u00a0').replace(/&amp;/g, '&');
  const at = (tag: string, a: string) => dec((tag.match(new RegExp(`\\s${a}="([^"]*)"`)) || [])[1] ?? '');
  const inputs = [...t.matchAll(/<input\b[^>]*>/g)].map(m => m[0]);
  const val = (id: string) => { const tg = inputs.find(x => at(x, 'id') === id); return tg ? at(tg, 'value') : ''; };
  const coche = (id: string) => { const tg = inputs.find(x => at(x, 'id') === id); return !!tg && /\schecked/.test(tg); };
  const zone = (id: string) => dec((t.match(new RegExp(`<textarea[^>]*\\sid="${id}"[^>]*>([\\s\\S]*?)</textarea>`)) || [])[1] ?? '');
  const choix = (id: string) => { const m = t.match(new RegExp(`<select[^>]*\\sid="${id}"[^>]*>([\\s\\S]*?)</select>`)); const o = m ? [...m[1].matchAll(/<option\b[^>]*>/g)].map(x => x[0]).find(x => /\sselected/.test(x)) : null; return o ? at(o, 'value') : ''; };
  if (!val('libelleType')) throw new Error(`Invitation ${body.source} introuvable au national`);
  const TYPES: Record<string, [string, string]> = { '7': ["Réunion d'information", 'à la '], '16': ['Réunion de lancement', 'à la '], '3': ['Réunion des membres', 'à la '] };
  const idType = String(body.idType || choix('idType'));
  const typ = idType !== choix('idType') && TYPES[idType] ? TYPES[idType] : [val('libelleType'), val('motDeLiaisonType')];
  const f: Record<string, string> = {
    id: body.maj ? String(body.source) : '', idHote: String(body.idHote || choix('listeHote')), idType,
    motDeLiaisonType: typ[1], libelleType: typ[0],
    dateDebut: String(body.dateDebut), dateFin: String(body.dateFin), dateRelance: String(body.dateRelance || ''), dateReponse: String(body.dateReponse || ''), dateRappel: String(body.dateRappel || ''),
    montant: val('montant'), programme: zone('programme'), theme: String(body.theme || val('theme')), expediteur: val('expediteur'),
    expediteurIsAnimateur: String(coche('expediteurIsAnimateurTrue')), informationsDestinataires: coche('informationsDestinatairesTrue') ? 'prenom' : 'civilite_nom',
    urlSalleVisio: val('urlSalleVisio'), repasIsFacultatif: String(coche('repasIsFacultatifTrue')),
    optionVisio: String(coche('deroulementEvenementVisio') || coche('deroulementEvenementMixte')), optionPhysique: String(coche('deroulementEvenementPresentiel') || coche('deroulementEvenementMixte')),
    utilisationInscription: String(coche('utilisationInscriptionTrue')),
    nbOptionsReponse: ['1', '2', '3'].find(k => coche('choixReponseOption' + k)) || '1',
    texteOuiOption1: val('texteOuiOption1'), texteOuiOption2: val('texteOuiOption2'), texteOuiOption3: val('texteOuiOption3'),
    metadata: zone('metadata'), template: zone('template'), refTemplate: zone('refTemplate'),
  };
  if (!/^\d\d\/\d\d\/\d{4} à \d\d:\d\d$/.test(f.dateDebut) || !/^\d\d\/\d\d\/\d{4} à \d\d:\d\d$/.test(f.dateFin)) throw new Error('Dates au format « JJ/MM/AAAA à HH:MM » attendues');
  const resume = Object.fromEntries(Object.entries(f).map(([k, v]) => [k, v.length > 120 ? `(${v.length} caractères)` : v]));
  if (body.essai) return { ok: true, essai: true, envoi: resume };
  const r = await N.req('POST', '/invitation/enregistrer', f);
  const brut = await r.text(); let j: any = null; try { j = JSON.parse(brut); } catch { /* */ }
  const id = j?.tabDonnees?.id || (body.maj && j?.success ? body.source : null);
  if (!j?.success || !id) return { ok: false, error: `Le national a refusé l'enregistrement (${r.status}).`, reponse: brut.slice(0, 1500), envoi: resume };
  return { ok: true, id, lien: `${B}/invitation/inscription?ref=${id}`, qr: `${B}/invitation/qrCode?id=${id}&type=png`, envoi: resume };
}

// Inscrits d'une invitation : écran « Afficher les statistiques de l'invitation » (/invitation/statistique?id=…),
// liste DataTables /destinataireInvitation/lister?id=… (etatInvitation 1 = accepté, etatPresence 1 = présent).
async function inscritsLire(N: National, invId: string) {
  const id = encodeURIComponent(invId);
  await N.req('GET', `/invitation/statistique?id=${id}`);
  const cols = ['', 'id', 'nomEntreprise', 'prenom', 'nom', 'email', 'dateReponse', 'dateOuverture', 'nombreOuvertures', 'informations'];
  const f: Record<string, string> = { draw: '1', start: '0', length: '500', 'search[value]': '', 'search[regex]': 'false', 'order[0][column]': '1', 'order[0][dir]': 'desc' };
  cols.forEach((c, i) => Object.assign(f, { [`columns[${i}][data]`]: c, [`columns[${i}][name]`]: c, [`columns[${i}][searchable]`]: c ? 'true' : 'false', [`columns[${i}][orderable]`]: c ? 'true' : 'false', [`columns[${i}][search][value]`]: '', [`columns[${i}][search][regex]`]: 'false' }));
  const j = await N.json('POST', `/destinataireInvitation/lister?id=${id}`, f);
  const inscrits = (Array.isArray(j?.data) ? j.data : []).map((x: any) => ({ id: String(x.id), entreprise: String(x.nomEntreprise || '').trim(), prenom: String(x.prenom || '').trim(), nom: String(x.nom || '').trim(),
    email: String(x.email || '').trim(), tel: String(x.tel1 || '').trim(), activite: String(x.activite || '').trim(), reponse: String(x.dateReponse || ''), etat: Number(x.etatInvitation), present: Number(x.etatPresence) === 1 }));
  return { inscrits };
}
async function pousser(admin: any, title: string, body: string, url: string, tag: string) {
  try {
    const { data: k } = await admin.rpc('cap_vapid_private'); if (!k) return;
    webpush.setVapidDetails('https://cap-proteine-maroc.vercel.app', VAPID_PUBLIC, k as string);
    const { data: profs } = await admin.from('profiles').select('id').eq('role', 'superadmin');
    const { data: abos } = await admin.from('push_abonnements').select('id, endpoint, p256dh, auth').in('user_id', (profs || []).map((p: any) => p.id));
    for (const ab of abos || []) { try { await webpush.sendNotification({ endpoint: ab.endpoint, keys: { p256dh: ab.p256dh, auth: ab.auth } }, JSON.stringify({ title, body, url, tag }), { TTL: 86400 }); } catch { /* */ } }
  } catch { /* */ }
}
async function inscritsSync(admin: any, N: National, r: any) {
  const invId = r?.national?.invitation_id; if (!invId) return { inscrits: 0, nouveaux: 0 };
  const lu = await inscritsLire(N, String(invId));
  const { data: deja } = await admin.from('invites').select('id, national_id, nom, email').eq('reunion_id', r.id);
  let nouveaux = 0; const noms: string[] = [];
  for (const x of lu.inscrits) {
    const nom = [x.prenom, x.nom].filter(Boolean).join(' ').trim() || x.email;
    const ex = (deja || []).find((d: any) => d.national_id === x.id || (x.email && n(d.email) === n(x.email)) || n(d.nom) === n(nom));
    const note = `Inscrit par le lien du national${x.reponse ? ' le ' + x.reponse : ''}`;
    if (ex) { if (!ex.national_id) await admin.from('invites').update({ national_id: x.id, email: x.email || null }).eq('id', ex.id); continue; }
    const { error } = await admin.from('invites').insert({ reunion_id: r.id, nom, email: x.email || null, tel: x.tel || null, entreprise: x.entreprise || null, metier: x.activite || null, statut: x.etat === 2 ? 'Non intéressé' : 'Intéressé', invite_par: 'Lien du national', note, national_id: x.id });
    if (!error) { nouveaux++; noms.push(nom); }
  }
  await admin.from('reunions').update({ national: { ...r.national, inscrits: lu.inscrits.length, inscrits_le: new Date().toISOString() } }).eq('id', r.id);
  if (noms.length) await pousser(admin, `🗓 ${noms.length > 1 ? noms.length + ' nouveaux inscrits' : 'Nouvel inscrit'} à la réunion du ${String(r.date).split('-').reverse().join('/')}`, noms.join(', '), '/?reunion=' + r.id, 'insc-' + r.id);
  return { inscrits: lu.inscrits.length, nouveaux };
}

Deno.serve(async (req) => {
  const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const url = Deno.env.get('SUPABASE_URL')!, service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const admin = createClient(url, service);
  try {
    let ok = false;
    const jeton = req.headers.get('x-suivi-jeton');
    if (jeton) { const { data } = await admin.rpc('cap_national_jeton_ok', { p: jeton }); ok = data === true; }
    if (!ok) {
      const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } });
      const { data: { user } } = await caller.auth.getUser();
      if (user) { const { data: p } = await admin.from('profiles').select('role').eq('id', user.id).single(); ok = p?.role === 'superadmin'; }
    }
    if (!ok) return json({ error: 'Non autorisé' }, 401);

    const body = await req.json().catch(() => ({}));
    if (body.action === 'inscrits') {
      // Inscrits d'une réunion (ou de toutes les réunions à venir qui ont une invitation) rapatriés dans les invités.
      const N0 = new National(); await N0.connexion();
      let q = admin.from('reunions').select('id, date, national').not('national', 'is', null);
      q = body.reunion_id ? q.eq('id', body.reunion_id) : q.gte('date', new Date(Date.now() - 2 * 864e5).toISOString().slice(0, 10));
      const { data: rs } = await q; const out: any[] = [];
      for (const r of rs || []) out.push({ reunion_id: r.id, ...(await inscritsSync(admin, N0, r)) });
      return json({ ok: true, reunions: out });
    }
    if (body.action === 'regarder') {
      // Lecture seule d'une page du national, morceaux autour d'un motif (pour relever la navigation).
      const N0 = new National(); await N0.connexion();
      const t = await (await N0.req('GET', String(body.page || '/connexion/extranet'))).text();
      return json({ ok: true, morceaux: [...t.matchAll(new RegExp(String(body.motif), 'g'))].slice(0, 6).map(m => t.slice(Math.max(0, m.index! - 200), m.index! + 700)) });
    }
    if (body.action === 'champs') {
      // Lecture seule : liste des champs de formulaire d'une page (nom, id, type, valeur, options d'une liste).
      const N0 = new National(); await N0.connexion();
      const t = await (await N0.req('GET', String(body.page || '/'))).text();
      const at = (tag: string, a: string) => (tag.match(new RegExp(`\\s${a}="([^"]*)"`)) || [])[1] ?? '';
      const champs: any[] = [];
      for (const m of t.matchAll(/<(input|textarea)\b[^>]*>/g)) champs.push({ t: m[1] === 'input' ? at(m[0], 'type') || 'text' : 'textarea', name: at(m[0], 'name'), id: at(m[0], 'id'), v: at(m[0], 'value').slice(0, 80), coche: /\schecked/.test(m[0]) || undefined });
      for (const m of t.matchAll(/<select\b([^>]*)>([\s\S]*?)<\/select>/g)) champs.push({ t: 'select', name: at(m[0], 'name'), id: at(m[0], 'id'), options: [...m[2].matchAll(/<option\b([^>]*)>([^<]*)/g)].slice(0, 40).map(o => `${at(o[0], 'value')}=${o[2].trim()}${/selected/.test(o[1]) ? ' *' : ''}`) });
      const forms = [...t.matchAll(/<form\b[^>]*>/g)].map(f => f[0]);
      return json({ ok: true, forms, champs: champs.filter(c => c.name || c.id) });
    }
    if (body.action === 'lister') {
      // Lecture seule d'une liste DataTables du national (ex. /invitation + /invitation/lister).
      const N0 = new National(); await N0.connexion();
      await N0.req('GET', String(body.index));
      const nb = Number(body.nb) || 20, f: Record<string, string> = { draw: '1', start: '0', length: String(nb), 'search[value]': '', 'search[regex]': 'false', 'order[0][column]': '1', 'order[0][dir]': 'desc' };
      (body.colonnes || []).map(String).forEach((c: string, i: number) => Object.assign(f, { [`columns[${i}][data]`]: c, [`columns[${i}][name]`]: c, [`columns[${i}][searchable]`]: c ? 'true' : 'false', [`columns[${i}][orderable]`]: c ? 'true' : 'false', [`columns[${i}][search][value]`]: '', [`columns[${i}][search][regex]`]: 'false' }));
      const r = await N0.req('POST', String(body.liste), f);
      return json({ ok: true, statut: r.status, brut: (await r.text()).slice(0, 20000) });
    }
    if (body.action === 'invitation_copier') {
      // Nouvelle invitation au national à partir d'une existante (comme « Rédiger une nouvelle invitation à partir de celle-ci »).
      // Entrée : source (n° d'invitation), dateDebut / dateFin (« JJ/MM/AAAA à HH:MM »), dateReponse / dateRelance / dateRappel (« JJ/MM/AAAA »),
      // theme, idHote, idType facultatifs ; essai:true = rien n'est écrit, on renvoie ce qui serait envoyé.
      const N0 = new National(); await N0.connexion();
      return json(await invitationEcrire(N0, body));
    }
    if (body.action === 'invitation_reunion') {
      // Invitation au national pour une réunion de notre CRM (création, ou mise à jour des dates si elle existe déjà).
      // Modèle : la dernière invitation du national du même type (SI → Réunion d'information, RL → Réunion de lancement).
      const { data: r, error: e1 } = await admin.from('reunions').select('id, type, format, theme, date, heure, statut, lieu_id, national').eq('id', body.reunion_id).single();
      if (e1 || !r) throw new Error('Réunion introuvable');
      if (r.statut === 'annulee') throw new Error('Réunion annulée : pas d\'invitation.');
      const { data: l } = r.lieu_id ? await admin.from('lieux').select('nom').eq('id', r.lieu_id).single() : { data: null };
      const N0 = new National(); await N0.connexion();
      const idType = r.format ? 3 : r.type === 'RL' ? 16 : r.type === 'SI' ? 7 : 3; // v1.6.1 : réunion du cycle = « Réunion des membres »
      const invs = await invitationsListe(N0);
      const nat = r.national || {};
      const maj = nat.invitation_id && invs.some(x => String(x.id) === String(nat.invitation_id)) ? String(nat.invitation_id) : '';
      const source = maj || String((invs.find(x => +x.idType === idType) || invs[0] || {}).id || '');
      if (!source) throw new Error('Aucune invitation au national à prendre pour modèle : crée la première là-bas.');
      // Lieu : celui du national dont le nom correspond au nôtre, sinon on refuse (le national exige un lieu existant).
      const hotes = new Map<string, string>(); for (const x of invs) if (x.idHote) hotes.set(n(x.nomHote), String(x.idHote));
      const idHote = l?.nom ? hotes.get(n(l.nom)) : (invs.find(x => String(x.id) === source)?.idHote ? String(invs.find(x => String(x.id) === source).idHote) : '');
      if (!idHote) throw new Error(l?.nom ? `Le lieu « ${l.nom} » n'existe pas encore au national. Lieux connus là-bas : ${[...new Set(invs.map(x => x.nomHote))].join(', ') || 'aucun'}.` : 'Choisis d\'abord le lieu de la réunion.');
      const d = new Date(r.date + 'T12:00:00Z'), j2 = (k: number) => { const x = new Date(d); x.setUTCDate(x.getUTCDate() - k); return x.toISOString().slice(0, 10).split('-').reverse().join('/'); };
      const h = /^\d\d:\d\d/.test(r.heure || '') ? r.heure.slice(0, 5) : '11:00', hf = String(Math.min(23, +h.slice(0, 2) + 3)).padStart(2, '0') + h.slice(2);
      const jour = j2(0);
      const res = await invitationEcrire(N0, { source, maj: !!maj, idType, idHote, dateDebut: `${jour} à ${h}`, dateFin: `${jour} à ${hf}`, dateReponse: j2(1), dateRappel: j2(2), dateRelance: j2(3), theme: r.theme || undefined, essai: body.essai });
      if (res.ok && !res.essai) {
        const national = { invitation_id: res.id, lien: res.lien, qr: res.qr, date: r.date, heure: h, lieu: l?.nom || '', modele: maj ? nat.modele : source, cree_le: nat.cree_le || new Date().toISOString(), maj_le: new Date().toISOString() };
        await admin.from('reunions').update({ national }).eq('id', r.id);
        return json({ ...res, national, mise_a_jour: !!maj });
      }
      return json(res);
    }
    if (body.action === 'miroir') {
      // Ce que le national affiche dans « En attente de signature » et « Gestion des membres » (lecture seule).
      const N1 = new National(); await N1.connexion();
      const etatDe = (c: any) => Object.values(c?.tabEtatSignature || {}).map((x: any) => String(x?.libelle || '').replace(/<br\s*\/?>/g, ' ').replace(/\s+/g, ' ').trim()).pop() || '';
      const ligne = (r: any) => {
        const ab = r?.entreprise?.abonnementEnCours || {}, c = ab.contrat || {}, p = r?.personne || {};
        return { personne: [p.prenom, p.nom].filter(Boolean).join(' '), email: p.email || '', tel: p.tel1 || '', entreprise: r?.entreprise?.nom || '', entreprise_id: r?.entreprise?.id || null,
          contrat_id: c.id || null, date: c.date || '', debut: ab.dateDebut || '', fin: ab.dateFin || '', montant: c.montantTotal || ab.montantTotal || '', etat: etatDe(c), signe: c.isSigne === true,
          pdf: c.nomFichier ? `https://app.ma.caproteine.com/uploads/contratMembre/contratPapier-${c.nomFichier}.pdf` : '' };
      };
      const attente = (await N1.liste('/prospectMembre/indexAttenteSignature', '/prospectMembre/lister', COL_ATTENTE)).map(ligne);
      const membres = (await N1.liste('/membre', '/membre/lister', COL_MEMBRES, 1000)).map(ligne);
      return json({ ok: true, attente, membres, lu_le: new Date().toISOString() });
    }
    const { data: adhs, error } = await admin.from('adhesions').select('id, statut, data, national, saisie_proteine_le, created_at').neq('statut', 'rejetee');
    if (error) throw error;
    const N = new National();
    await N.connexion();
    const maintenant = new Date().toISOString();
    const res = { annuaire: [] as string[], signes: [] as { id: string; nom: string; ent: string }[], attente: 0, erreurs: [] as string[] };
    const nomDe = (d: any) => [d?.m_prenom, d?.m_nom].filter(Boolean).join(' ');
    const sauver = async (a: any, extra: Record<string, unknown>, cols: Record<string, unknown> = {}) => {
      a.national = { ...(a.national || {}), ...extra };
      await admin.from('adhesions').update({ national: a.national, ...cols }).eq('id', a.id);
    };

    // 1 · Fiche prospect au national (« Sans contrat »), remplie par national-adhesion action « prospect ».
    const aRemplir = (adhs || []).filter(a => !a.national?.personne_id && !a.national?.contrat_id && !a.national?.prospect_erreur_le).slice(0, 5);
    for (const a of aRemplir) {
      try {
        const r = await fetch(url + '/functions/v1/national-adhesion', { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-suivi-jeton': jeton || '', Authorization: req.headers.get('Authorization') || '' }, body: JSON.stringify({ action: 'prospect', adhesion_id: a.id }) });
        const j = await r.json().catch(() => ({}));
        if (j?.ok) { a.national = j.national; res.annuaire.push(`${nomDe(a.data)} : fiche prospect remplie au national`); }
        else { res.erreurs.push(`Prospect, ${nomDe(a.data)} : ${j?.error || r.status}`); if (j && j.ok === false || /incompl/i.test(j?.error || '')) await sauver(a, { prospect_erreur_le: maintenant, prospect_erreur: j.error }); }
      } catch (e) { res.erreurs.push(`Prospect, ${nomDe(a.data)} : ${(e as Error).message}`); }
    }

    // 1 bis · Annuaire seul, pour les demandes incomplètes (pas de fiche prospect possible).
    const aCreer = (adhs || []).filter(a => !a.national?.prospect_id && !a.national?.contrat_id && a.data?.m_email && a.data?.m_nom && a.data?.m_prenom).slice(0, 10);
    for (const a of aCreer) {
      const d = a.data;
      try {
        const trouve = Object.values(await N.json('POST', '/personneProspectMembre/listerAll', {
          'columns[0][data]': 'email', 'columns[0][searchable]': 'true', 'columns[0][search][value]': d.m_email, start: '0', length: '5',
        }) || {}).find((p: any) => n(p.email) === n(d.m_email)) as any;
        if (trouve) {
          await sauver(a, { prospect_id: trouve.id, annuaire_le: maintenant, annuaire: 'retrouvé' });
          res.annuaire.push(`${nomDe(d)} : déjà dans l'annuaire (n° ${trouve.id})`);
          continue;
        }
        const p = await N.ecrire('/personne/enregistrer', {
          'idProfil[]': '10', activiteEntreprise: d.ent_activite || '', idEntreprise: '', id: '', civilite: d.m_civilite || 'Monsieur',
          nom: d.m_nom, prenom: d.m_prenom, fonction: d.m_fonction || '', email: d.m_email, tel1: d.m_tel || '', tel2: d.m_tel2 || '',
          adresse: d.ent_adresse || '', codePostal: d.ent_cp || '', ville: d.ent_ville || '',
        });
        const extra: Record<string, unknown> = { prospect_id: p.id, annuaire_le: maintenant, annuaire: 'créé' };
        if (d.ent_nom) { const e = await N.ecrire('/entreprise/enregistrer', { id: '', idPersonne: String(p.id), nom: d.ent_nom, activite: d.ent_activite || '' }); extra.entreprise_id = e.id; }
        await sauver(a, extra);
        res.annuaire.push(`${nomDe(d)} : ajouté à l'annuaire (n° ${p.id})`);
      } catch (e) { res.erreurs.push(`Annuaire, ${nomDe(d)} : ${(e as Error).message}`); }
    }

    // 2 · Signatures des contrats envoyés.
    const suivis = (adhs || []).filter(a => a.national?.contrat_id && !a.national?.signe_le);
    if (suivis.length) {
      const attente = await N.liste('/prospectMembre/indexAttenteSignature', '/prospectMembre/lister', COL_ATTENTE);
      const membres = await N.liste('/membre', '/membre/lister', COL_MEMBRES, 1000);
      const parContrat = new Map<string, any>();
      for (const r of attente) { const c = r?.entreprise?.abonnementEnCours?.contrat; if (c?.id) parContrat.set(String(c.id), c); }
      const entMembres = new Set(membres.map(r => String(r?.entreprise?.id ?? r?.idEntreprise ?? '')).filter(Boolean));
      for (const a of suivis) {
        const nat = a.national, c = parContrat.get(String(nat.contrat_id));
        const etat = c ? Object.values(c.tabEtatSignature || {}).map((x: any) => String(x?.libelle || '').replace(/<br\s*\/?>/g, ' ').replace(/\s+/g, ' ').trim()).pop() : '';
        const signe = (c && c.isSigne === true) || (!c && nat.entreprise_id && entMembres.has(String(nat.entreprise_id)));
        if (signe) {
          await sauver(a, { signe_le: maintenant, signe_source: 'national', verifie_le: maintenant, etat_signature: 'Signé' }, a.saisie_proteine_le ? {} : { saisie_proteine_le: maintenant });
          res.signes.push({ id: a.id, nom: nomDe(a.data), ent: a.data?.ent_nom || '' });
        } else if (c) {
          res.attente++;
          await sauver(a, { verifie_le: maintenant, etat_signature: etat || 'En attente de signature', absent_le: null });
        } else {
          await sauver(a, { verifie_le: maintenant, etat_signature: 'Introuvable au national (ni en attente ni membre)', absent_le: nat.absent_le || maintenant });
        }
      }
    }

    // 2 bis · Inscrits des invitations des réunions à venir.
    try {
      const { data: rs } = await admin.from('reunions').select('id, date, national').not('national', 'is', null).gte('date', new Date(Date.now() - 2 * 864e5).toISOString().slice(0, 10));
      for (const r of rs || []) await inscritsSync(admin, N, r);
    } catch (e) { res.erreurs.push('Inscrits : ' + (e as Error).message); }

    // 3 · Notification des signatures aux superadmins.
    if (res.signes.length) {
      try {
        const { data: k } = await admin.rpc('cap_vapid_private');
        if (k) {
          webpush.setVapidDetails('https://cap-proteine-maroc.vercel.app', VAPID_PUBLIC, k as string);
          const { data: profs } = await admin.from('profiles').select('id').eq('role', 'superadmin');
          const { data: abos } = await admin.from('push_abonnements').select('id, endpoint, p256dh, auth').in('user_id', (profs || []).map(p => p.id));
          for (const s of res.signes) {
            const payload = JSON.stringify({ title: '✍️ Contrat signé au national', body: [s.nom, s.ent].filter(Boolean).join(' · '), url: '/?adh=' + s.id, tag: 'signe-' + s.id });
            for (const ab of abos || []) {
              try { await webpush.sendNotification({ endpoint: ab.endpoint, keys: { p256dh: ab.p256dh, auth: ab.auth } }, payload, { TTL: 86400 }); }
              catch (e) { const code = (e as { statusCode?: number }).statusCode; if (code === 404 || code === 410) await admin.from('push_abonnements').delete().eq('id', ab.id); }
            }
          }
        }
      } catch (e) { res.erreurs.push('Notification : ' + (e as Error).message); }
    }
    return json({ ok: true, ...res, verifie_le: maintenant });
  } catch (e) { return json({ error: String((e as Error).message || e) }, 500); }
});
