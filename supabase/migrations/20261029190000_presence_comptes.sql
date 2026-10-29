-- Qui est connecté : chaque appli ouverte signale sa présence (profiles.vu_le) toutes les minutes.
-- La liste n'est lisible que par le superadmin et le directeur national.
-- Pas de REVOKE (l'outil de migration le bloque) : cap_ping ne touche que la ligne de auth.uid() (rien pour anon),
-- cap_qui_connecte lève une erreur pour tout autre rôle.

alter table public.profiles add column if not exists vu_le timestamptz;
comment on column public.profiles.vu_le is 'Dernier signe de vie de l''appli ouverte (mis à jour chaque minute par cap_ping).';

create or replace function public.cap_ping()
returns void language sql security definer set search_path = public as $$
  update profiles set vu_le = now() where id = auth.uid();
$$;
grant execute on function public.cap_ping() to authenticated;

create or replace function public.cap_qui_connecte()
returns table(id uuid, login text, nom text, role text, vu_le timestamptz, derniere_connexion timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if coalesce(cap_role(), '') not in ('superadmin', 'directeur_national') then
    raise exception 'Réservé au superadmin et au directeur national';
  end if;
  return query
    select p.id, p.login, p.nom, p.role, p.vu_le, u.last_sign_in_at
    from profiles p join auth.users u on u.id = p.id
    order by p.vu_le desc nulls last, u.last_sign_in_at desc nulls last, p.nom;
end $$;
grant execute on function public.cap_qui_connecte() to authenticated;
