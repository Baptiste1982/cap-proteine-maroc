-- Espace membre (v0.25.0) : le CRM voit si un membre qui a reçu son code s'est déjà connecté.
-- auth.users n'est pas lisible depuis le navigateur : cette fonction ne rend que la date de dernière connexion
-- des comptes membres, et seulement à l'équipe du CRM (cap_est_equipe), pour les membres qu'elle peut voir.
create or replace function public.cap_membres_connexions() returns table(membre_id uuid, derniere_connexion timestamptz)
language sql stable security definer set search_path = public as $$
  select m.id, u.last_sign_in_at
  from membres m join auth.users u on u.id = m.user_id
  where cap_est_equipe() and cap_can_see_club(m.club_id)
$$;
