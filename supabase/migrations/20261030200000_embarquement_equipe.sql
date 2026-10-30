-- v0.33.0 : embarquement de l'équipe. Pas de DROP, pas de DELETE.
-- Le superadmin donne à chacun un mot de passe provisoire (via l'edge admin-users) et lui envoie ses accès par WhatsApp.
-- Le mot de passe provisoire impose d'en choisir un autre à la connexion, comme « cap2026 ».
alter table public.profiles add column if not exists mdp_provisoire boolean not null default false;
alter table public.profiles add column if not exists invite_le timestamptz;

create or replace function public.cap_mdp_a_changer() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select u.encrypted_password = extensions.crypt('cap2026', u.encrypted_password)
      or coalesce((select p.mdp_provisoire from public.profiles p where p.id = u.id), false)
  from auth.users u where u.id = auth.uid();
$$;

-- L'utilisateur vient de choisir son mot de passe.
create or replace function public.cap_mdp_change_fait() returns void
language sql security definer set search_path = public as $$
  update public.profiles set mdp_provisoire = false where id = auth.uid();
$$;

-- Superadmin : marque le mot de passe d'un compte comme provisoire (appelé juste après set_password).
create or replace function public.cap_marquer_invite(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.cap_role(),'') <> 'superadmin' then raise exception 'réservé au superadmin'; end if;
  update public.profiles set mdp_provisoire = true, invite_le = now() where id = p_id;
end $$;

-- Superadmin : état de chaque compte d'équipe (dernière connexion, mot de passe de départ encore actif).
create or replace function public.cap_equipe_etat() returns table(id uuid, nom text, role text, email text, animateur_id uuid,
  vu_le timestamptz, derniere_connexion timestamptz, mdp_initial boolean, mdp_provisoire boolean, invite_le timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if coalesce(public.cap_role(),'') <> 'superadmin' then raise exception 'réservé au superadmin'; end if;
  return query select p.id, p.nom, p.role, u.email::text, p.animateur_id, p.vu_le, u.last_sign_in_at,
    u.encrypted_password = extensions.crypt('cap2026', u.encrypted_password), p.mdp_provisoire, p.invite_le
  from public.profiles p join auth.users u on u.id = p.id order by p.role, p.nom;
end $$;

grant execute on function public.cap_mdp_change_fait() to authenticated;
grant execute on function public.cap_marquer_invite(uuid) to authenticated;
grant execute on function public.cap_equipe_etat() to authenticated;
