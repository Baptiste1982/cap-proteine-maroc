// Code d'accès à l'espace membre (v0.24.0), sans WhatsApp ni SMS automatique.
// L'animateur (ou un directeur, ou le superadmin) crée depuis la fiche membre du CRM un code à 6 chiffres.
// Il le transmet lui-même au membre, qui se connecte sur membre.html avec son mobile et ce code.
//
// Le compte du membre est un compte Supabase Auth dont l'e-mail est fabriqué à partir du mobile :
// 212661234567@membres.cap-proteine.ma (aucun e-mail n'est jamais envoyé à cette adresse). Le code est
// son mot de passe ; le membre peut le changer depuis « Mon profil ». Aucun profil d'équipe n'est créé :
// ce compte ne voit rien du CRM (cap_est_equipe).
//
// Droits : il faut pouvoir modifier le club du membre (cap_can_edit_club, appelé avec la session de l'appelant).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const DOMAINE = 'membres.cap-proteine.ma';

// Mobile marocain → chiffres E.164 sans « + » (même règle que cap_tel_norm en base et que membre.html).
function telNorm(t: unknown): string {
  let d = String(t ?? '').replace(/\D/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.length === 10 && d.startsWith('0')) d = '212' + d.slice(1);
  if (d.length === 9 && /^[5-7]/.test(d)) d = '212' + d;
  return d;
}

function codeAleatoire(): string {
  const a = new Uint32Array(1);
  crypto.getRandomValues(a);
  return String(a[0] % 1_000_000).padStart(6, '0');
}

Deno.serve(async (req) => {
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Méthode non autorisée' }, 405);
  try {
    const url = Deno.env.get('SUPABASE_URL')!, anon = Deno.env.get('SUPABASE_ANON_KEY')!, service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) return json({ error: 'Session invalide' }, 401);
    const admin = createClient(url, service);

    const { membre_id } = await req.json().catch(() => ({}));
    const { data: m, error: merr } = await admin.from('membres').select('id, club_id, nom, infos, user_id').eq('id', membre_id).single();
    if (merr || !m) return json({ error: 'Membre introuvable' }, 404);
    const { data: peut } = await caller.rpc('cap_can_edit_club', { c_id: m.club_id });
    if (peut !== true) return json({ error: "Tu ne peux pas gérer l'accès de ce membre" }, 403);

    let tel = m.infos?.m_tel;
    if (!tel) {
      const { data: adh } = await admin.from('adhesions').select('data').eq('membre_id', m.id).limit(1).maybeSingle();
      tel = adh?.data?.m_tel;
    }
    const t = telNorm(tel);
    if (!/^212[5-7]\d{8}$/.test(t)) return json({ error: 'Mobile manquant ou invalide : renseigne son mobile (06…, 07…) dans ses informations.' }, 400);
    const email = `${t}@${DOMAINE}`;
    const code = codeAleatoire();

    if (m.user_id) {
      const { error } = await admin.auth.admin.updateUserById(m.user_id, { email, password: code, email_confirm: true });
      if (error) return json({ error: /already|registered|exists/i.test(error.message) ? 'Ce mobile est déjà utilisé par un autre membre.' : error.message }, 400);
    } else {
      const { data: cree, error } = await admin.auth.admin.createUser({ email, password: code, email_confirm: true, user_metadata: { membre_id: m.id } });
      if (error) return json({ error: /already|registered|exists/i.test(error.message) ? 'Ce mobile est déjà utilisé par un autre membre.' : error.message }, 400);
      const { error: uerr } = await admin.from('membres').update({ user_id: cree.user.id }).eq('id', m.id);
      if (uerr) { await admin.auth.admin.deleteUser(cree.user.id); return json({ error: uerr.message }, 500); }
    }
    return json({ ok: true, code, telephone: t, nouveau: !m.user_id });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
