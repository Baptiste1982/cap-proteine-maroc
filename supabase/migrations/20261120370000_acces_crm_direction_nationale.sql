-- v1.114 : la direction nationale donne aussi les accès au CRM (comptes animateur et directeur de région seulement).
create or replace function public.cap_acces_equipe()
 returns table(id uuid, nom text, role text, email text, animateur_id uuid, zone_id uuid, tel text, derniere_connexion timestamp with time zone, mdp_initial boolean, mdp_provisoire boolean, invite_le timestamp with time zone)
 language plpgsql stable security definer set search_path to 'public', 'extensions'
as $function$
begin
  if coalesce(public.cap_role(),'') not in ('superadmin','directeur_national') then raise exception 'réservé à la direction'; end if;
  return query select p.id, p.nom, p.role, u.email::text, p.animateur_id, p.zone_id,
    coalesce(nullif(a.tel,''), p.tel), u.last_sign_in_at,
    u.encrypted_password = extensions.crypt('cap2026', u.encrypted_password), p.mdp_provisoire, p.invite_le
  from public.profiles p join auth.users u on u.id = p.id left join public.animateurs a on a.id = p.animateur_id
  order by p.role, p.nom;
end $function$;

create or replace function public.cap_marquer_invite(p_id uuid) returns void
 language plpgsql security definer set search_path to 'public'
as $function$
declare r text := coalesce(public.cap_role(), '');
begin
  if public.cap_voir() is not null or r not in ('superadmin','directeur_national') then raise exception 'réservé à la direction'; end if;
  if r = 'directeur_national' and not exists (select 1 from public.profiles where id = p_id and role in ('animateur','directeur')) then
    raise exception 'réservé au super admin pour ce compte';
  end if;
  update public.profiles set mdp_provisoire = true, invite_le = now() where id = p_id;
end $function$;
