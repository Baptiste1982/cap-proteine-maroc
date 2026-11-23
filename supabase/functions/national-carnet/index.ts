// Carnet du national (lecture seule au national) : rapatrie dans carnet_national les contacts de l'Annuaire du CRM national
// (écran « Annuaire », /personne puis /personne/lister) vus par UN compte : celui d'un animateur (son compte branché)
// ou le compte commun (super admin). Rien n'est écrit au national.
// Appel : session d'équipe (chacun pour son compte ; le super admin pour n'importe lequel ou le compte commun avec commun:true)
// ou en-tête x-suivi-jeton (tous:true = tous les comptes branchés + le compte commun).
// ⚠ Les lignes du national portent identifiant et mot de passe de la personne : on ne garde JAMAIS ces champs.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const B = 'https://animateur.ma.caproteine.com';
const COLS = ['', 'id', 'nomEntreprise', 'prenom', 'nom', 'email', 'tel1', 'tel2', 'adresse', 'codePostal', 'ville', 'profil'];
const s = (x: unknown, n = 160) => { const t = String(x ?? '').replace(/\s+/g, ' ').trim(); return t ? t.slice(0, n) : null; };
const premierNom = (o: any): string | null => { if (!o || typeof o !== 'object') return null; if (typeof o.nom === 'string' && o.nom.trim()) return o.nom; for (const v of Object.values(o)) { const r = premierNom(v); if (r) return r; } return null; };
const libelles = (o: any, out: string[] = []): string[] => { if (o && typeof o === 'object') { if (typeof o.libelle === 'string') out.push(o.libelle.trim()); else for (const v of Object.values(o)) libelles(v, out); } return out; };

async function lire(login: string, password: string) {
  const jar: Record<string, string> = {};
  const call = async (method: string, path: string, form?: Record<string, string>) => {
    const r = await fetch(B + path, { method, redirect: 'manual', body: form ? new URLSearchParams(form).toString() : undefined, headers: { cookie: Object.entries(jar).map(([k, v]) => `${k}=${v}`).join('; '), ...(form ? { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8', 'x-requested-with': 'XMLHttpRequest' } : {}) } });
    for (const c of r.headers.getSetCookie?.() ?? []) { const kv = c.split(';')[0]; const i = kv.indexOf('='); jar[kv.slice(0, i)] = kv.slice(i + 1); }
    return r;
  };
  await call('GET', '/');
  const cx = await call('POST', '/connexion/extranet', { login, password, autoConnect: 'true' });
  if (!/Déconnexion/.test(await cx.text())) throw new Error('Le national refuse la connexion avec ce compte');
  await call('GET', '/personne');
  const tout: any[] = []; let total = 0;
  // Même requête que la page (colonnes nommées, tri sur l'identifiant), par pages de 500.
  for (let start = 0; start < 20000; start += 500) {
    const f: Record<string, string> = { draw: '1', start: String(start), length: '500', 'search[value]': '', 'search[regex]': 'false', 'order[0][column]': '1', 'order[0][dir]': 'desc' };
    COLS.forEach((c, i) => Object.assign(f, { [`columns[${i}][data]`]: c, [`columns[${i}][name]`]: c, [`columns[${i}][searchable]`]: c ? 'true' : 'false', [`columns[${i}][orderable]`]: c ? 'true' : 'false', [`columns[${i}][search][value]`]: '', [`columns[${i}][search][regex]`]: 'false' }));
    const r = await call('POST', '/personne/lister', f); let j: any = null; try { j = JSON.parse(await r.text()); } catch { /* */ }
    if (!j?.success) throw new Error(`Annuaire du national illisible (${r.status})`);
    const page = Array.isArray(j.response?.tabPersonnes) ? j.response.tabPersonnes : Object.values(j.response?.tabPersonnes || {});
    total = Number(j.response?.nbLignesTotales) || page.length; tout.push(...page);
    if (!page.length || tout.length >= total) break;
  }
  return { total, lignes: tout };
}

async function rapatrier(admin: any, animId: string | null, login: string, password: string) {
  const { total, lignes } = await lire(login, password), le = new Date().toISOString();
  const rows = lignes.filter((p: any) => Number(p?.id) > 0).map((p: any) => ({
    animateur_id: animId, national_id: Number(p.id), civilite: s(p.civilite, 20), prenom: s(p.prenom, 80), nom: s(p.nom, 80), fonction: s(p.fonction, 120),
    entreprise: s(premierNom(p.tabEntreprises), 160), email: s(p.email, 160), tel1: s(p.tel1, 40), tel2: s(p.tel2, 40), adresse: s(p.adresse, 200), code_postal: s(p.codePostal, 20), ville: s(p.ville, 80),
    profils: s([...new Set(libelles(p.tabProfils))].join(', '), 200), actif: p.isActive !== false, absent_le: null, vu_le: le,
  }));
  let q = admin.from('carnet_national').select('id, national_id'); q = animId ? q.eq('animateur_id', animId) : q.is('animateur_id', null);
  const { data: avant } = await q; const connus = new Map((avant || []).map((x: any) => [Number(x.national_id), x.id]));
  let nouveaux = 0, erreurs = 0;
  for (const r of rows) {
    const id = connus.get(r.national_id);
    const { error } = id ? await admin.from('carnet_national').update(r).eq('id', id) : await admin.from('carnet_national').insert(r);
    if (error) erreurs++; else if (!id) nouveaux++;
  }
  // Un contact qui n'est plus dans l'Annuaire du national reste chez nous, marqué « absent » (rien n'est effacé).
  if (rows.length >= total && rows.length) {
    const vus = new Set(rows.map(r => r.national_id)), partis = (avant || []).filter((x: any) => !vus.has(Number(x.national_id))).map((x: any) => x.id);
    for (let i = 0; i < partis.length; i += 200) await admin.from('carnet_national').update({ absent_le: le }).in('id', partis.slice(i, i + 200)).is('absent_le', null);
  }
  if (animId) await admin.from('national_comptes').update({ carnet_le: le, carnet_nb: rows.length }).eq('animateur_id', animId);
  else await admin.from('reglages').upsert({ cle: 'carnet_commun_le', valeur: le, maj_le: le });
  return { total, lus: rows.length, nouveaux, erreurs };
}

Deno.serve(async (req) => {
  const json = (b: unknown, st = 200) => new Response(JSON.stringify(b), { status: st, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cap-voir' } });
  if (req.method === 'OPTIONS') return json({});
  try {
    const url = Deno.env.get('SUPABASE_URL')!, admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const body = await req.json().catch(() => ({}));
    let role = '', monAnim: string | null = null, jetonOk = false; const jeton = req.headers.get('x-suivi-jeton');
    if (jeton) { const { data } = await admin.rpc('cap_national_jeton_ok', { p: jeton }); jetonOk = data === true; }
    if (!jetonOk) {
      const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } });
      const { data: { user } } = await caller.auth.getUser();
      if (!user) return json({ error: 'Non autorisé' }, 401);
      const { data: p } = await admin.from('profiles').select('role, animateur_id').eq('id', user.id).single();
      role = p?.role || ''; monAnim = p?.animateur_id || null;
      if (!role || role === 'visiteur') return json({ error: 'Non autorisé' }, 401);
    }
    const sup = jetonOk || role === 'superadmin';
    const compte = async (animId: string) => { const { data } = await admin.rpc('cap_national_compte_secret', { p_anim: animId }); return data?.identifiant && data?.mdp ? { login: String(data.identifiant), password: String(data.mdp) } : null; };
    const commun = () => rapatrier(admin, null, Deno.env.get('CAP_NATIONAL_IDENTIFIANT') || '', Deno.env.get('CAP_NATIONAL_MOT_DE_PASSE') || '');

    if (body.tous) {
      if (!sup) return json({ error: 'Réservé au super admin' }, 403);
      const res: any[] = []; const { data: cs } = await admin.from('national_comptes').select('animateur_id').eq('actif', true);
      for (const c of cs || []) { try { const k = await compte(c.animateur_id); if (k) res.push({ animateur_id: c.animateur_id, ...(await rapatrier(admin, c.animateur_id, k.login, k.password)) }); } catch (e) { res.push({ animateur_id: c.animateur_id, error: String((e as Error).message || e) }); } }
      try { res.push({ animateur_id: null, ...(await commun()) }); } catch (e) { res.push({ animateur_id: null, error: String((e as Error).message || e) }); }
      return json({ ok: true, comptes: res });
    }
    if (body.commun) { if (!sup) return json({ error: 'Réservé au super admin' }, 403); return json({ ok: true, ...(await commun()) }); }
    const cible = String(body.animateur_id || monAnim || '');
    if (!cible) return json({ error: "Ce compte n'a pas de fiche Équipe : pas de compte national à lire." }, 400);
    if (!sup && cible !== monAnim) return json({ error: 'Chacun ne rapatrie que son propre carnet' }, 403);
    const k = await compte(cible); if (!k) return json({ error: "Branche d'abord ton compte du CRM national." }, 400);
    return json({ ok: true, ...(await rapatrier(admin, cible, k.login, k.password)) });
  } catch (e) { return json({ error: String((e as Error).message || e) }, 500); }
});
