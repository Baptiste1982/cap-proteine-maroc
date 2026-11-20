// Comptes du CRM : liste, création, mot de passe, rôle, suppression.
// Super admin : tout. Direction nationale (v4, 20/11/2026) : créer un compte d'animateur ou de directeur de région, et lui
// donner un mot de passe provisoire. Elle ne touche jamais à un compte super admin, direction nationale ou visiteur.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const DOMAIN = 'cap-proteine.ma';
const ROLES = ['superadmin', 'directeur_national', 'directeur', 'animateur', 'visiteur'];
const ROLES_NAT = ['directeur', 'animateur'];

Deno.serve(async (req) => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Méthode non autorisée' }, 405);

  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader) return json({ error: 'Non authentifié' }, 401);

    const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: uerr } = await caller.auth.getUser();
    if (uerr || !user) return json({ error: 'Session invalide' }, 401);

    const admin = createClient(url, service);
    const { data: prof } = await admin.from('profiles').select('role').eq('id', user.id).single();
    const sup = prof?.role === 'superadmin', nat = prof?.role === 'directeur_national';
    if (!sup && !nat) return json({ error: 'Réservé à la direction' }, 403);

    const body = await req.json().catch(() => ({}));
    const action = body.action;
    if (nat && !['create', 'set_password'].includes(action)) return json({ error: 'Réservé au super admin' }, 403);

    if (action === 'list') {
      const { data: list, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (error) return json({ error: error.message }, 400);
      const { data: profs } = await admin.from('profiles').select('*');
      const byId: Record<string, any> = {};
      (profs || []).forEach((p: any) => { byId[p.id] = p; });
      const users = list.users.map((u: any) => {
        const p = byId[u.id] || {};
        return { id: u.id, email: u.email, login: p.login || null, nom: p.nom || null, role: p.role || null, zone_id: p.zone_id || null, animateur_id: p.animateur_id || null, last_sign_in_at: u.last_sign_in_at };
      });
      return json({ users });
    }

    if (action === 'create') {
      const { login, nom, password, role, zone_id, animateur_id } = body;
      if (!login || !password || !role) return json({ error: 'login, mot de passe et rôle requis' }, 400);
      if (!ROLES.includes(role)) return json({ error: 'Rôle invalide' }, 400);
      if (nat && !ROLES_NAT.includes(role)) return json({ error: 'Ce rôle est réservé au super admin' }, 403);
      const email = String(login).includes('@') ? String(login) : `${String(login).toLowerCase()}@${DOMAIN}`;
      if (nat && !email.endsWith('@' + DOMAIN)) return json({ error: 'Identifiant invalide' }, 400);
      const { data: created, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
      if (error) return json({ error: error.message }, 400);
      const { error: perr } = await admin.from('profiles').upsert({
        id: created.user.id, login: String(login).toLowerCase(), nom: nom || login, role,
        zone_id: zone_id || null, animateur_id: animateur_id || null,
      });
      if (perr) { await admin.auth.admin.deleteUser(created.user.id); return json({ error: perr.message }, 400); }
      return json({ ok: true, id: created.user.id, email });
    }

    if (action === 'set_password') {
      const { id, password } = body;
      if (!id || !password) return json({ error: 'id et mot de passe requis' }, 400);
      if (nat) {
        // La cible doit être un compte d'équipe au rôle animateur ou directeur de région (jamais un membre, jamais la direction).
        const { data: cible } = await admin.from('profiles').select('role').eq('id', id).maybeSingle();
        if (!cible || !ROLES_NAT.includes(String(cible.role))) return json({ error: 'Ce compte est réservé au super admin' }, 403);
      }
      const { error } = await admin.auth.admin.updateUserById(id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (action === 'set_role') {
      const { id, role, zone_id, animateur_id } = body;
      if (!id || !role) return json({ error: 'id et rôle requis' }, 400);
      if (!ROLES.includes(role)) return json({ error: 'Rôle invalide' }, 400);
      const { error } = await admin.from('profiles').update({ role, zone_id: zone_id || null, animateur_id: animateur_id || null }).eq('id', id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (action === 'delete') {
      const { id } = body;
      if (!id) return json({ error: 'id requis' }, 400);
      if (id === user.id) return json({ error: 'Impossible de supprimer son propre compte' }, 400);
      await admin.from('profiles').delete().eq('id', id);
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: 'Action inconnue' }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
