// v1.76.0 — Bibliothèque nationale (Documents du réseau) : imports faits côté serveur.
//   action "national_liste"    : lit la rubrique « Ressources » du CRM national (catégories, sous-catégories, ressources). Lecture seule.
//   action "national_importer" : copie dans le bucket `reseau` les ressources de type fichier pas encore importées
//                                (source = national:<id>:v<version>), `max` par appel (4 par défaut).
//   action "importer"          : copie des fichiers du site (cap-proteine-maroc.vercel.app) dans le bucket `reseau`
//                                et crée leurs fiches. docs = [{ url, titre, categorie, description, source, membres }].
//   action "trame"             : copie les images d'une trame de présentation du site vers le bucket privé `presentations`.
// Appel : session superadmin, ou en-tête x-suivi-jeton (coffre national_suivi_jeton). verify_jwt:false.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-suivi-jeton', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const B = 'https://animateur.ma.caproteine.com', FICHIERS = 'https://app.ma.caproteine.com/uploads/ressources/auto/', SITE = 'https://cap-proteine-maroc.vercel.app/';
const MIME: Record<string, string> = { pdf: 'application/pdf', doc: 'application/msword', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', xls: 'application/vnd.ms-excel', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', ppt: 'application/vnd.ms-powerpoint', pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', gif: 'image/gif', mp4: 'video/mp4', mov: 'video/quicktime', zip: 'application/zip', txt: 'text/plain', md: 'text/markdown', gs: 'text/plain', csv: 'text/csv' };
const ext = (n: string) => (n.split('?')[0].match(/\.([a-z0-9]{1,5})$/i)?.[1] || '').toLowerCase();

class National {
  jar: Record<string, string> = {};
  async req(method: string, path: string, form?: Record<string, string>) {
    const r = await fetch(B + path, { method, redirect: 'manual', body: form ? new URLSearchParams(form).toString() : undefined, headers: { cookie: Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '), ...(form ? { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8' } : {}), 'x-requested-with': 'XMLHttpRequest' } });
    for (const c of r.headers.getSetCookie?.() ?? []) { const kv = c.split(';')[0]; const i = kv.indexOf('='); this.jar[kv.slice(0, i)] = kv.slice(i + 1); }
    return r;
  }
  async connexion() {
    await this.req('GET', '/');
    const r = await this.req('POST', '/connexion/extranet', { login: Deno.env.get('CAP_NATIONAL_IDENTIFIANT') || '', password: Deno.env.get('CAP_NATIONAL_MOT_DE_PASSE') || '', autoConnect: 'true' });
    if (!/Déconnexion/.test(await r.text())) throw new Error('Connexion au CRM national refusée.');
  }
}

// Les ressources du national, à plat : { id, nom, version, fichier, type, url, categorie, sous }.
async function ressources(N: National) {
  await N.req('GET', '/ressourceDocumentaire');
  const t = await (await N.req('GET', '/categorieRessourceDocumentaire/lister')).text();
  let j: any; try { j = JSON.parse(t); } catch { throw new Error('Ressources du national : réponse inattendue'); }
  const out: any[] = [], brut = j?.response?.tabCategorie || [];
  const liste = (v: any) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);
  for (const c of liste(brut)) {
    const sous = Object.entries(c).find(([k, v]) => /sous/i.test(k) && v && typeof v === 'object')?.[1];
    for (const s of liste(sous)) {
      const res = Object.entries(s as any).find(([k, v]) => /ressource/i.test(k) && v && typeof v === 'object')?.[1];
      for (const r of liste(res) as any[]) out.push({ id: r.id, nom: r.nom ?? r.nomRessource, version: r.version, fichier: r.nomFichier, type: r.type, url: r.url, categorie: c.nom, sous: (s as any).nom, cles: Object.keys(r) });
    }
  }
  return { out, brut };
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

    // Copie un fichier distant dans un bucket ; rend { chemin, taille, mime }.
    const copier = async (source: string, bucket: string, chemin: string, max = 48e6) => {
      const r = await fetch(source);
      if (!r.ok) throw new Error(`téléchargement refusé (${r.status})`);
      const buf = new Uint8Array(await r.arrayBuffer());
      if (buf.byteLength > max) throw new Error(`trop lourd (${Math.round(buf.byteLength / 1e6)} Mo)`);
      const mime = MIME[ext(chemin)] || r.headers.get('content-type') || 'application/octet-stream';
      const up = await admin.storage.from(bucket).upload(chemin, buf, { contentType: mime, upsert: true });
      if (up.error) throw new Error(up.error.message);
      return { chemin, taille: buf.byteLength, mime };
    };
    const fiche = async (d: Record<string, unknown>) => {
      const { error } = await admin.from('documents_reseau').insert(d);
      if (error) throw new Error(error.message);
    };
    const dejaSources = async () => new Set(((await admin.from('documents_reseau').select('source').not('source', 'is', null)).data || []).map((x: any) => x.source));

    if (body.action === 'national_liste') {
      const N = new National(); await N.connexion(); const { out, brut } = await ressources(N);
      return json({ ok: true, n: out.length, ressources: out, apercu: body.brut ? JSON.stringify(brut).slice(0, 3000) : undefined });
    }
    if (body.action === 'national_importer') {
      const N = new National(); await N.connexion(); const { out } = await ressources(N); const deja = await dejaSources();
      const max = Math.max(1, Math.min(10, Number(body.max) || 4)), faits: any[] = [], ko: any[] = [];
      const fichiers = out.filter(r => r.type === 'fichier' && r.fichier), autres = out.filter(r => !(r.type === 'fichier' && r.fichier));
      const reste = fichiers.filter(r => !deja.has(`national:${r.id}:v${r.version ?? ''}`));
      for (const r of reste.slice(0, max)) {
        const src = `national:${r.id}:v${r.version ?? ''}`;
        try {
          const c = await copier(FICHIERS + encodeURIComponent(r.fichier), 'reseau', `national/${crypto.randomUUID()}.${ext(r.fichier) || 'bin'}`);
          await fiche({ titre: String(r.nom || r.fichier).slice(0, 200), description: [r.sous, r.version != null ? 'version ' + r.version : '', 'CRM national'].filter(Boolean).join(' · '), categorie: 'National · ' + (r.categorie || 'Ressources'), chemin: c.chemin, nom_fichier: r.fichier, type_mime: c.mime, taille: c.taille, visible_animateurs: true, visible_membres: false, lien_public: false, source: src });
          faits.push(r.nom);
        } catch (e) { ko.push({ nom: r.nom, fichier: r.fichier, erreur: String((e as Error).message) }); }
      }
      return json({ ok: true, total: out.length, fichiers: fichiers.length, importes: faits, echecs: ko, restants: Math.max(0, reste.length - max), hors_fichier: autres.map(r => ({ nom: r.nom, type: r.type, url: r.url, categorie: r.categorie })) });
    }
    if (body.action === 'importer') {
      const deja = await dejaSources(), faits: string[] = [], ko: any[] = [];
      for (const d of (body.docs || []) as any[]) {
        const chemin0 = String(d.url || '').replace(/^\/+/, '');
        if (!chemin0 || /\.\.|^https?:/i.test(chemin0)) { ko.push({ titre: d.titre, erreur: 'adresse refusée' }); continue; }
        if (d.source && deja.has(d.source)) continue;
        try {
          const nom = chemin0.split('/').pop()!;
          const c = await copier(SITE + chemin0, 'reseau', `cap/${crypto.randomUUID()}.${ext(nom) || 'bin'}`);
          await fiche({ titre: d.titre, description: d.description || null, categorie: d.categorie || 'Autres', chemin: c.chemin, nom_fichier: d.nom_fichier || nom, type_mime: c.mime, taille: c.taille, visible_animateurs: d.animateurs !== false, visible_membres: !!d.membres, lien_public: !!d.lien, source: d.source || null, epingle: !!d.epingle });
          faits.push(d.titre);
        } catch (e) { ko.push({ titre: d.titre, erreur: String((e as Error).message) }); }
      }
      return json({ ok: true, importes: faits, echecs: ko });
    }
    if (body.action === 'trame') {
      const faits: string[] = [], ko: any[] = [];
      for (const f of (body.fichiers || []) as string[]) {
        if (!/^presentations\/[a-z0-9/_-]+\.(jpg|png|webp)$/i.test(f)) { ko.push({ f, erreur: 'chemin refusé' }); continue; }
        try { await copier(SITE + f, 'presentations', f.replace(/^presentations\//, ''), 5e6); faits.push(f); } catch (e) { ko.push({ f, erreur: String((e as Error).message) }); }
      }
      return json({ ok: true, copies: faits.length, echecs: ko });
    }
    return json({ error: 'action inconnue' }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
