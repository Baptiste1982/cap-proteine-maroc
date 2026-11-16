-- v0.45.0 : accès et identifiants par rôle.
-- Mobile WhatsApp des comptes d'équipe sans fiche d'animateur (direction), état complet des accès, superadmin seulement.
alter table public.profiles add column if not exists tel text;

create or replace function public.cap_acces_equipe()
returns table(id uuid, nom text, role text, email text, animateur_id uuid, zone_id uuid, tel text,
  derniere_connexion timestamptz, mdp_initial boolean, mdp_provisoire boolean, invite_le timestamptz)
language plpgsql stable security definer set search_path to 'public', 'extensions' as $$
begin
  if coalesce(public.cap_role(),'') <> 'superadmin' then raise exception 'réservé au superadmin'; end if;
  return query select p.id, p.nom, p.role, u.email::text, p.animateur_id, p.zone_id,
    coalesce(nullif(a.tel,''), p.tel), u.last_sign_in_at,
    u.encrypted_password = extensions.crypt('cap2026', u.encrypted_password), p.mdp_provisoire, p.invite_le
  from public.profiles p join auth.users u on u.id = p.id left join public.animateurs a on a.id = p.animateur_id
  order by p.role, p.nom;
end $$;

create or replace function public.cap_profil_tel(p_id uuid, p_tel text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_anim uuid;
begin
  if coalesce(public.cap_role(),'') <> 'superadmin' then raise exception 'réservé au superadmin'; end if;
  select animateur_id into v_anim from public.profiles where id = p_id;
  if v_anim is not null then update public.animateurs set tel = nullif(trim(p_tel),'') where id = v_anim;
  else update public.profiles set tel = nullif(trim(p_tel),'') where id = p_id; end if;
end $$;
