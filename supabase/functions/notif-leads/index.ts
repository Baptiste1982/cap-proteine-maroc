// Notification « nouveaux leads » (v1.21) : appelée par la RPC cap_leads_recevoir quand le Google Sheet
// remonte des leads qui n'étaient pas encore dans le CRM. Accès : en-tête x-suivi-jeton (coffre national_suivi_jeton).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
const VAPID_PUBLIC = 'BAKkMOISOmM62avwTzeE81_l592rvg9O-AiLBct4eGf7Xovoy_OswNK0lnQ0yokt6VDoRkL927x4LS5bFYnWbZM';
Deno.serve(async (req) => {
  const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  try {
    const jeton = req.headers.get('x-suivi-jeton');
    const { data: ok } = jeton ? await admin.rpc('cap_national_jeton_ok', { p: jeton }) : { data: false };
    if (ok !== true) return json({ error: 'Non autorisé' }, 401);
    const body = await req.json().catch(() => ({}));
    const noms = (Array.isArray(body.noms) ? body.noms : []).map(String).filter(Boolean).slice(0, 20);
    if (!noms.length) return json({ ok: true, envoyes: 0 });
    const { data: k } = await admin.rpc('cap_vapid_private'); if (!k) return json({ ok: false, error: 'clé VAPID absente' });
    webpush.setVapidDetails('https://cap-proteine-maroc.vercel.app', VAPID_PUBLIC, k as string);
    const { data: profs } = await admin.from('profiles').select('id').eq('role', 'superadmin');
    const { data: abos } = await admin.from('push_abonnements').select('id, endpoint, p256dh, auth').in('user_id', (profs || []).map((p: any) => p.id));
    const payload = JSON.stringify({ title: `📇 ${noms.length > 1 ? noms.length + ' nouveaux leads' : 'Nouveau lead'}${body.feuille ? ' · ' + String(body.feuille) : ''}`, body: noms.join(', '), url: '/?leads=1', tag: 'leads' });
    let envoyes = 0;
    for (const ab of abos || []) {
      try { await webpush.sendNotification({ endpoint: ab.endpoint, keys: { p256dh: ab.p256dh, auth: ab.auth } }, payload, { TTL: 86400 }); envoyes++; }
      catch (e) { const c = (e as { statusCode?: number }).statusCode; if (c === 404 || c === 410) await admin.from('push_abonnements').delete().eq('id', ab.id); }
    }
    return json({ ok: true, envoyes });
  } catch (e) { return json({ error: String((e as Error).message || e) }, 500); }
});
