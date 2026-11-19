-- v1.84.0
-- 1. Statistiques : le nombre de membres d'un groupe = ses fiches, complété par le nombre donné par le national tant que les fiches manquent.
do $do$
declare d text; a text := $a$'membres', (select count(*) from membres m where m.club_id = c.id),$a$;
  b text := $b$'membres', greatest((select count(*) from membres m where m.club_id = c.id), coalesce(c.pairs_declares, 0)),
        'surplus', greatest(coalesce(c.pairs_declares, 0) - (select count(*) from membres m where m.club_id = c.id), 0),$b$;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.proname = 'cap_monitoring' and p.pronamespace = 'public'::regnamespace;
  if position('''surplus''' in d) > 0 then return; end if;
  if position(a in d) = 0 then raise exception 'cap_monitoring : ligne des membres introuvable'; end if;
  execute replace(d, a, b);
end $do$;

-- 2. Directeur de région nommé depuis le CRM (super admin). Lecture des directeurs par toute l'équipe.
create or replace function public.cap_regions_directeurs() returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select case when cap_est_equipe() then
    (select coalesce(jsonb_agg(jsonb_build_object('zone_id', p.zone_id, 'profil', p.id, 'nom', p.nom, 'animateur_id', p.animateur_id) order by p.nom), '[]'::jsonb)
       from profiles p where p.role = 'directeur' and p.zone_id is not null)
  else '[]'::jsonb end
$function$;

create or replace function public.cap_region_directeur(p_zone uuid, p_profil uuid, p_oui boolean) returns text language plpgsql security definer set search_path to 'public'
as $function$
declare v_role text;
begin
  if coalesce(cap_role(), '') <> 'superadmin' or cap_voir() is not null then raise exception 'réservé au super admin'; end if;
  if not exists (select 1 from zones where id = p_zone) then raise exception 'région inconnue'; end if;
  select role into v_role from profiles where id = p_profil;
  if v_role is null then raise exception 'compte inconnu'; end if;
  if v_role in ('superadmin', 'directeur_national') then raise exception 'ce compte a déjà un rôle national'; end if;
  if v_role = 'visiteur' then raise exception 'le compte visiteur ne peut pas diriger une région'; end if;
  if coalesce(p_oui, true) then
    update profiles set role = 'directeur', zone_id = p_zone where id = p_profil;
    return 'directeur';
  else
    update profiles set role = 'animateur' where id = p_profil and role = 'directeur' and zone_id = p_zone;
    return 'animateur';
  end if;
end $function$;
