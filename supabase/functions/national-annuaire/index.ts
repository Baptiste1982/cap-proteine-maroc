// Annuaire national des membres (lecture seule) : entreprises membres et personnes membres, tels que le CRM national
// les affiche dans son menu « National ». Sert à connaître les membres de chaque groupe pour peupler notre CRM.
// Appel : session superadmin ou en-tête x-suivi-jeton. quoi = 'entreprises' | 'personnes' | 'tout'.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const B = 'https://animateur.ma.caproteine.com';
const dec = (x: string) => x.replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d)).replace(/&quot;/g, '"').replace(/&#039;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
const txt = (x?: string) => dec(String(x || '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();

Deno.serve(async (req) => {
  const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
  try {
    const url = Deno.env.get('SUPABASE_URL')!, admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let ok = false; const jeton = req.headers.get('x-suivi-jeton');
    if (jeton) { const { data } = await admin.rpc('cap_national_jeton_ok', { p: jeton }); ok = data === true; }
    if (!ok) {
      const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } });
      const { data: { user } } = await caller.auth.getUser();
      if (user) { const { data: p } = await admin.from('profiles').select('role').eq('id', user.id).single(); ok = p?.role === 'superadmin'; }
    }
    if (!ok) return json({ error: 'Non autorisé' }, 401);
    const body = await req.json().catch(() => ({})); const quoi = String(body.quoi || 'tout');

    const jar: Record<string, string> = {};
    const call = async (method: string, path: string, form?: Record<string, string>) => {
      const r = await fetch(B + path, { method, redirect: 'manual', body: form ? new URLSearchParams(form).toString() : undefined, headers: { cookie: Object.entries(jar).map(([k, v]) => `${k}=${v}`).join('; '), ...(form ? { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8', 'x-requested-with': 'XMLHttpRequest' } : {}) } });
      for (const c of r.headers.getSetCookie?.() ?? []) { const kv = c.split(';')[0]; const i = kv.indexOf('='); jar[kv.slice(0, i)] = kv.slice(i + 1); }
      return r;
    };
    await call('GET', '/');
    const cx = await call('POST', '/connexion/extranet', { login: Deno.env.get('CAP_NATIONAL_IDENTIFIANT') || '', password: Deno.env.get('CAP_NATIONAL_MOT_DE_PASSE') || '', autoConnect: 'true' });
    if (!/Déconnexion/.test(await cx.text())) return json({ error: 'Connexion au CRM national refusée' }, 500);

    // Même requête que celle qui a déjà fonctionné pour l'annuaire des entreprises (colonnes '', 'nom' ; tri sur la 2e).
    const liste = async (page: string, lister: string) => {
      await call('GET', page);
      const f: Record<string, string> = { draw: '1', start: '0', length: '2000', 'search[value]': '', 'search[regex]': 'false', 'order[0][column]': '1', 'order[0][dir]': 'desc' };
      ['', 'nom'].forEach((c, i) => Object.assign(f, { [`columns[${i}][data]`]: c, [`columns[${i}][name]`]: c, [`columns[${i}][searchable]`]: c ? 'true' : 'false', [`columns[${i}][orderable]`]: c ? 'true' : 'false', [`columns[${i}][search][value]`]: '', [`columns[${i}][search][regex]`]: 'false' }));
      const r = await call('POST', lister, f); const t = await r.text();
      let j: any = null; try { j = JSON.parse(t); } catch { /* */ }
      if (!j?.succes) return { erreur: `${lister} : ${r.status}`, total: 0, cartes: [] as any[] };
      const cartes = String(j.data || '').split(/<div class="col-sm-6[^"]*">/).slice(1).map(b => ({
        titres: [...b.matchAll(/<strong>([\s\S]*?)<\/strong>/g)].map(m => txt(m[1])).filter(Boolean),
        petits: [...b.matchAll(/<small[^>]*>([\s\S]*?)<\/small>/g)].map(m => txt(m[1])).filter(Boolean),
        gras: [...b.matchAll(/<div class="[^"]*font-bold[^"]*">([\s\S]*?)<\/div>/g)].map(m => txt(m[1])).filter(Boolean),
        h2: [...b.matchAll(/<h[1-4][^>]*>([\s\S]*?)<\/h[1-4]>/g)].map(m => txt(m[1])).filter(Boolean),
        ent: txt((b.match(/fa-building-o"><\/i>([^<]*)/) || [])[1]),
        tel: txt((b.match(/fa-phone-square[^>]*><\/i>([^<]*)/) || [])[1]),
        mail: txt((b.match(/mailto:([^"'\\]+)/) || [])[1]),
        site: txt((b.match(/fa-firefox[^>]*href="([^"]+)"/) || [])[1]),
        adresse: txt((b.match(/<address>([\s\S]*?)<\/address>/) || [])[1]),
        image: txt((b.match(/<img[^>]*src="([^"]+)"/) || [])[1]),
      }));
      return { total: j.nbLignesTotales, cartes };
    };
    const out: Record<string, unknown> = { ok: true, lu_le: new Date().toISOString() };
    if (quoi !== 'personnes') out.entreprises = await liste('/entrepriseMembre/trombinoscopeNational', '/entrepriseMembre/listerTrombinoscopeNational');
    if (quoi !== 'entreprises') out.personnes = await liste('/personneMembre/trombinoscopeNational', '/personneMembre/listerTrombinoscopeNational');
    return json(out);
  } catch (e) { return json({ error: String((e as Error).message || e) }, 500); }
});
