// Annuaire national des membres (lecture seule) : entreprises membres et personnes membres, tels que le CRM national
// les affiche dans son menu « National ». Sert à connaître les membres de chaque groupe pour peupler notre CRM.
// Appel : session superadmin ou en-tête x-suivi-jeton. quoi = 'entreprises' | 'personnes' | 'tout'.
// action = 'verifier' (passage hebdomadaire) : compare l'annuaire du national à nos fiches. Elle AJOUTE les nouveaux membres
// (mêmes champs que l'import du 23/11) et ne fait que SIGNALER le reste : fiches venues du national qui n'y sont plus,
// personnes trouvées dans un autre groupe, groupes du national inconnus chez nous. Rien n'est supprimé ni déplacé.
// essai:true = rien n'est écrit. Le rapport (noms seulement, aucune coordonnée) est rangé dans reglages.national_verif.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
const VAPID_PUBLIC = 'BAKkMOISOmM62avwTzeE81_l592rvg9O-AiLBct4eGf7Xovoy_OswNK0lnQ0yokt6VDoRkL927x4LS5bFYnWbZM';
const B = 'https://animateur.ma.caproteine.com';
const dec = (x: string) => x.replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d)).replace(/&quot;/g, '"').replace(/&#039;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
const sansAcc = (x: string) => String(x || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const cle = (x: string) => sansAcc(x).replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter(Boolean).sort().join(' ');
const initcap = (x: string) => String(x || '').toLowerCase().replace(/(^|[\s'’-])(\p{L})/gu, (_, a, b) => a + b.toUpperCase());
const groupeChezNous = (g: string) => 'CAP ' + String(g || '').replace(/^Casa /, 'Casablanca ');
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
    if (body.action !== 'verifier') return json(out);

    const essai = body.essai === true, P = (out.personnes as any)?.cartes || [], E = (out.entreprises as any)?.cartes || [];
    // Garde-fou : une lecture ratée ou presque vide ne doit pas faire croire que tout le monde est parti.
    if ((out.personnes as any)?.erreur || (out.entreprises as any)?.erreur || P.length < 10) return json({ error: 'Lecture du national incomplète, vérification abandonnée', personnes: P.length }, 502);
    const { data: clubs } = await admin.from('clubs').select('id, nom, ville, animateur_id');
    const { data: mbs } = await admin.from('membres').select('id, nom, club_id, num, infos');
    const clubPar = new Map((clubs || []).map(c => [cle(c.nom), c]));
    const nomClub = (id: unknown) => (clubs || []).find(c => String(c.id) === String(id))?.nom || '';
    const R = { le: new Date().toISOString(), essai, national: P.length, groupes: {} as Record<string, number>, ajoutes: [] as any[], partis: [] as any[], deplaces: [] as any[], inconnus: [] as any[], erreurs: [] as string[] };
    const vus = new Set<string>(), aCreer: any[] = [];
    for (const c of P) {
      const brut = c.titres?.[0] || '', grp = c.petits?.[0] || '', k = cle(brut); if (!k) continue;
      const club = clubPar.get(cle(groupeChezNous(grp)));
      R.groupes[grp] = (R.groupes[grp] || 0) + 1;
      if (!club) { R.inconnus.push({ nom: initcap(brut), groupe: grp }); continue; }
      vus.add(k + '|' + club.id);
      const memes = (mbs || []).filter(m => cle(m.nom) === k);
      if (memes.some(m => String(m.club_id) === String(club.id))) continue;
      if (memes.length) { R.deplaces.push({ nom: initcap(brut), national: club.nom, chez_nous: memes.map(m => nomClub(m.club_id)).join(', ') }); continue; }
      const entNom = String(c.ent || '').replace(/\s*\([^)]*\)\s*$/, '');
      const e = E.find((x: any) => sansAcc(x.titres?.[0] || '') === sansAcc(entNom) && (x.petits?.[0] || '') === grp) || E.find((x: any) => sansAcc(x.titres?.[0] || '') === sansAcc(entNom));
      const mots = brut.split(/\s+/).filter(Boolean), maj = (w: string) => w.length > 1 && w === w.toUpperCase() && /\p{L}/u.test(w);
      const infos: Record<string, unknown> = { m_prenom: mots.filter((w: string) => !maj(w)).join(' '), m_nom: initcap(mots.filter(maj).join(' ')), m_tel: c.tel, m_email: c.mail, m_fonction: c.gras?.[0], ent_nom: entNom, ent_activite: e?.gras?.[0], ent_adresse: e ? String(e.adresse || '').replace(e.titres?.[0] || '', '').trim() : '', ent_ville: club.ville, ent_web: e?.site, source: 'national', importe_le: R.le.slice(0, 10) };
      for (const x of Object.keys(infos)) if (!infos[x]) delete infos[x];
      aCreer.push({ club_id: club.id, nom: initcap(brut), specialite: e?.gras?.[0] || null, contrat: true, commentaires: `Ajouté par la vérification hebdomadaire de l'annuaire du CRM national le ${R.le.slice(8, 10)}/${R.le.slice(5, 7)}/${R.le.slice(0, 4)}`, photo_url: c.image && !/contributeur|defaut/.test(c.image) ? c.image : null, logo_url: e?.image || null, site: e?.site || null, infos });
      R.ajoutes.push({ nom: initcap(brut), groupe: club.nom, metier: e?.gras?.[0] || '' });
    }
    // Fiches venues du national qui n'y figurent plus (dans ce groupe) : signalées, jamais retirées.
    for (const m of (mbs || [])) if ((m.infos as any)?.source === 'national' && !vus.has(cle(m.nom) + '|' + m.club_id)) R.partis.push({ id: m.id, nom: m.nom, groupe: nomClub(m.club_id) });
    if (!essai) {
      const rang: Record<string, number> = {}; for (const m of (mbs || [])) rang[m.club_id] = Math.max(rang[m.club_id] || 0, m.num || 0);
      for (const f of aCreer) { f.num = ++rang[f.club_id] || (rang[f.club_id] = 1); const { error } = await admin.from('membres').insert(f); if (error) R.erreurs.push(f.nom + ' : ' + error.message); }
      // On ne notifie que du nouveau : un écart déjà signalé la semaine d'avant reste dans le rapport, sans nouvelle notification.
      const sig = (r: any) => JSON.stringify([(r?.partis || []).map((x: any) => x.nom + x.groupe).sort(), (r?.deplaces || []).map((x: any) => x.nom + x.national).sort(), (r?.inconnus || []).map((x: any) => x.nom + x.groupe).sort()]);
      const { data: avant } = await admin.from('reglages').select('valeur').eq('cle', 'national_verif').maybeSingle();
      let prec: any = null; try { prec = JSON.parse(avant?.valeur || 'null'); } catch { /* */ }
      await admin.from('reglages').upsert({ cle: 'national_verif', valeur: JSON.stringify(R), maj_le: R.le });
      const n = R.ajoutes.length || (sig(R) !== sig(prec) && R.partis.length + R.deplaces.length + R.inconnus.length);
      if (n) {
        try {
          const { data: kv } = await admin.rpc('cap_vapid_private');
          if (kv) {
            webpush.setVapidDetails('https://cap-proteine-maroc.vercel.app', VAPID_PUBLIC, kv as string);
            const { data: profs } = await admin.from('profiles').select('id, role').in('role', ['superadmin', 'directeur_national']);
            const { data: abos } = await admin.from('push_abonnements').select('user_id, endpoint, p256dh, auth').in('user_id', (profs || []).map(p => p.id));
            const corps = [R.ajoutes.length && `${R.ajoutes.length} ajouté(s)`, R.partis.length && `${R.partis.length} qui n'y figure(nt) plus`, R.deplaces.length && `${R.deplaces.length} dans un autre groupe`, R.inconnus.length && `${R.inconnus.length} dans un groupe inconnu`].filter(Boolean).join(' · ');
            for (const ab of (abos || [])) { try { await webpush.sendNotification({ endpoint: ab.endpoint, keys: { p256dh: ab.p256dh, auth: ab.auth } }, JSON.stringify({ title: '🔎 Membres du national : du changement', body: corps, url: '/?verifnat=1', tag: 'verifnat' }), { TTL: 86400 }); } catch { /* */ } }
          }
        } catch { /* la notification ne bloque rien */ }
      }
    }
    return json({ ok: true, rapport: R });
  } catch (e) { return json({ error: String((e as Error).message || e) }, 500); }
});
