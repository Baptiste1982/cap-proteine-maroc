// Contrats sortis de « En attente de signature » au CRM national : sont-ils devenus membres ?
// national-suivi lit « En attente de signature » et « Gestion Membres ». Or « Gestion Membres » revient vide pour le
// compte commun alors que l'entreprise figure déjà dans l'annuaire national « Entreprises Membres » : le contrat restait
// noté « Introuvable au national ». Ici, chaque contrat sorti de l'attente (national.absent_le) est cherché dans cet annuaire.
//   trouvé  → national.signe_le, notification aux superadmins ;
//   absent depuis plus d'un jour → une alerte, une seule fois.
// Lecture seule au national. Appel : session superadmin (bouton du CRM) ou en-tête x-suivi-jeton (appel programmé).
// essai:true = rien n'est écrit chez nous non plus.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-suivi-jeton', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const B = 'https://animateur.ma.caproteine.com';
const VAPID_PUBLIC = 'BAKkMOISOmM62avwTzeE81_l592rvg9O-AiLBct4eGf7Xovoy_OswNK0lnQ0yokt6VDoRkL927x4LS5bFYnWbZM';
const n = (t: unknown) => String(t ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
const dec = (x: string) => x.replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d)).replace(/&quot;/g, '"').replace(/&#039;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');

class National {
  jar: Record<string, string> = {};
  async req(method: string, path: string, form?: Record<string, string>) {
    const r = await fetch(B + path, { method, redirect: 'manual', body: form ? new URLSearchParams(form).toString() : undefined, headers: { cookie: Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '), ...(form ? { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8', 'x-requested-with': 'XMLHttpRequest' } : {}) } });
    for (const c of r.headers.getSetCookie?.() ?? []) { const kv = c.split(';')[0]; const i = kv.indexOf('='); this.jar[kv.slice(0, i)] = kv.slice(i + 1); }
    return r;
  }
  async json(path: string, form: Record<string, string>) {
    const r = await this.req('POST', path, form); const t = await r.text();
    try { return JSON.parse(t); } catch { throw new Error(`${path} : réponse inattendue du national (${r.status})`); }
  }
  async connexion() {
    await this.req('GET', '/');
    const r = await this.req('POST', '/connexion/extranet', { login: Deno.env.get('CAP_NATIONAL_IDENTIFIANT') || '', password: Deno.env.get('CAP_NATIONAL_MOT_DE_PASSE') || '', autoConnect: 'true' });
    if (!/Déconnexion/.test(await r.text())) throw new Error('Connexion au CRM national refusée (identifiants à vérifier dans les secrets).');
  }
}

// Annuaire national « Entreprises Membres » : une carte par entreprise membre (nom, groupe, activité).
async function annuaireMembres(N: National) {
  await N.req('GET', '/entrepriseMembre/trombinoscopeNational');
  const f: Record<string, string> = { draw: '1', start: '0', length: '2000', 'search[value]': '', 'search[regex]': 'false', 'order[0][column]': '1', 'order[0][dir]': 'desc' };
  ['', 'nom'].forEach((c, i) => Object.assign(f, { [`columns[${i}][data]`]: c, [`columns[${i}][name]`]: c, [`columns[${i}][searchable]`]: c ? 'true' : 'false', [`columns[${i}][orderable]`]: c ? 'true' : 'false', [`columns[${i}][search][value]`]: '', [`columns[${i}][search][regex]`]: 'false' }));
  const j = await N.json('/entrepriseMembre/listerTrombinoscopeNational', f);
  if (!j?.succes) throw new Error('Annuaire des membres : lecture refusée par le national');
  const txt = (x?: string) => dec(String(x || '')).replace(/\s+/g, ' ').trim();
  return String(j.data || '').split('class="itemEntreprise"').slice(1).map(b => ({
    nom: txt((b.match(/<strong>([^<]*)<\/strong>/) || [])[1]), club: txt((b.match(/<small[^>]*>([^<]*)<\/small>/) || [])[1]), activite: txt((b.match(/<div class="font-bold">([^<]*)<\/div>/) || [])[1]),
  })).filter(x => x.nom);
}
// Nom que porte au national l'entreprise d'un contrat (lu sur la fiche de la personne, retrouvée par son e-mail).
async function nomEntreprise(N: National, email: string, entId: string): Promise<string> {
  if (!email || !entId) return '';
  const j = await N.json('/personneProspectMembre/listerAll', { 'columns[0][data]': 'email', 'columns[0][searchable]': 'true', 'columns[0][search][value]': email, start: '0', length: '5' });
  for (const p of Object.values(j || {}) as any[]) for (const r of Object.values(p?.tabEntreprises || {}) as any[]) if (r?.[entId]?.nom) return String(r[entId].nom);
  return '';
}

Deno.serve(async (req) => {
  const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const url = Deno.env.get('SUPABASE_URL')!, admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  try {
    let ok = false;
    const jeton = req.headers.get('x-suivi-jeton');
    if (jeton) { const { data } = await admin.rpc('cap_national_jeton_ok', { p: jeton }); ok = data === true; }
    if (!ok) {
      const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } });
      const { data: { user } } = await caller.auth.getUser();
      if (user) { const { data: p } = await admin.from('profiles').select('role').eq('id', user.id).single(); ok = p?.role === 'superadmin'; }
    }
    if (!ok) return json({ error: 'Non autorisé' }, 401);
    const body = await req.json().catch(() => ({}));
    const essai = body.essai === true;

    const { data: adhs, error } = await admin.from('adhesions').select('id, data, national, saisie_proteine_le').neq('statut', 'rejetee').not('national', 'is', null);
    if (error) throw error;
    const suivis = (adhs || []).filter(a => a.national?.contrat_id && !a.national?.signe_le && a.national?.absent_le);
    const res = { ok: true, essai, examines: suivis.length, signes: [] as { id: string; nom: string; ent: string; club: string }[], introuvables: [] as string[], annuaire: 0 };
    if (!suivis.length) return json(res);

    const N = new National(); await N.connexion();
    const ann = await annuaireMembres(N); res.annuaire = ann.length;
    const maintenant = new Date().toISOString();
    const nomDe = (d: any) => [d?.m_prenom, d?.m_nom].filter(Boolean).join(' ');
    // On relit la ligne juste avant d'écrire : national-suivi peut l'avoir touchée entre-temps.
    const sauver = async (a: any, extra: Record<string, unknown>, cols: Record<string, unknown> = {}) => {
      if (essai) return;
      const { data: frais } = await admin.from('adhesions').select('national').eq('id', a.id).single();
      a.national = { ...(frais?.national || a.national || {}), ...extra };
      await admin.from('adhesions').update({ national: a.national, ...cols }).eq('id', a.id);
    };

    for (const a of suivis) {
      const nat = a.national;
      let e = ann.find(x => n(x.nom) === n(nat.entreprise_nom || a.data?.ent_nom));
      if (!e && !nat.entreprise_nom) {
        const nom = await nomEntreprise(N, a.data?.m_email || '', String(nat.entreprise_id || '')).catch(() => '');
        if (nom) { await sauver(a, { entreprise_nom: nom }); e = ann.find(x => n(x.nom) === n(nom)); }
      }
      if (e) {
        await sauver(a, { signe_le: maintenant, signe_source: 'annuaire des membres du national', verifie_le: maintenant, absent_le: null, club_national: e.club || null,
          etat_signature: 'Signé · membre au national' + (e.club ? ' (' + e.club + ')' : '') }, a.saisie_proteine_le ? {} : { saisie_proteine_le: maintenant });
        res.signes.push({ id: a.id, nom: nomDe(a.data), ent: e.nom, club: e.club });
      } else {
        res.introuvables.push(`${nomDe(a.data)} · contrat n° ${nat.contrat_id}`);
        if (!nat.absent_alerte_le && Date.now() - new Date(nat.absent_le).getTime() > 864e5) {
          await sauver(a, { absent_alerte_le: maintenant });
          (a as any)._alerte = true;
        }
      }
    }

    if (!essai) {
      const envois: { title: string; body: string; url: string; tag: string }[] = [
        ...res.signes.map(s => ({ title: '✍️ Contrat signé au national', body: [s.nom, s.ent, s.club].filter(Boolean).join(' · '), url: '/?adh=' + s.id, tag: 'signe-' + s.id })),
        ...suivis.filter((a: any) => a._alerte).map(a => ({ title: '⚠️ Contrat introuvable au national', body: `${nomDe(a.data)} · contrat n° ${a.national.contrat_id} : ni en attente de signature ni membre. À vérifier.`, url: '/?adh=' + a.id, tag: 'absent-' + a.id })),
      ];
      if (envois.length) {
        try {
          const { data: k } = await admin.rpc('cap_vapid_private');
          if (k) {
            webpush.setVapidDetails('https://cap-proteine-maroc.vercel.app', VAPID_PUBLIC, k as string);
            const { data: profs } = await admin.from('profiles').select('id').eq('role', 'superadmin');
            const { data: abos } = await admin.from('push_abonnements').select('id, endpoint, p256dh, auth').in('user_id', (profs || []).map(p => p.id));
            for (const m of envois) for (const ab of abos || []) { try { await webpush.sendNotification({ endpoint: ab.endpoint, keys: { p256dh: ab.p256dh, auth: ab.auth } }, JSON.stringify(m), { TTL: 86400 }); } catch { /* */ } }
          }
        } catch { /* la notification ne bloque rien */ }
      }
    }
    return json(res);
  } catch (e) { return json({ error: String((e as Error).message || e) }, 500); }
});
