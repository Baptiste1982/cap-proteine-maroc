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
const n = (t: unknown) => String(t ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
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
    if (body.action === 'regarder') {
      // Lecture seule d'une page du national, morceaux autour d'un motif (pour relever la navigation).
      const N0 = new National(); await N0.connexion();
      const t = await (await N0.req('GET', String(body.page || '/connexion/extranet'))).text();
      return json({ ok: true, morceaux: [...t.matchAll(new RegExp(String(body.motif), 'g'))].slice(0, 6).map(m => t.slice(Math.max(0, m.index! - 200), m.index! + 700)) });
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
