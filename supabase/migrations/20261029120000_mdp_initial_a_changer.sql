-- ═══════════════════════════════════════════════════════════════════════════
-- Mot de passe initial « cap2026 » : le CRM oblige à le changer à la connexion.
-- Projet Supabase : cap-proteine-maroc (xsppsqjigdgaybmowzaq).
--
-- Pas de colonne « à changer » à tenir à jour : la fonction regarde le mot de passe
-- réel du compte connecté. Dès qu'il n'est plus « cap2026 », elle répond false.
-- Elle ne lit que le compte qui l'appelle (auth.uid()) et ne renvoie qu'un booléen.
-- Sans session (anon), auth.uid() est nul : la réponse est null, rien n'est exposé.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.cap_mdp_a_changer()
returns boolean
language sql stable security definer
set search_path = public, extensions
as $$
  select u.encrypted_password = extensions.crypt('cap2026', u.encrypted_password)
  from auth.users u where u.id = auth.uid();
$$;

grant execute on function public.cap_mdp_a_changer() to authenticated;
