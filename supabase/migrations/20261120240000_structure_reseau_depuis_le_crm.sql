-- v1.81.0 — créer une région, une ville, un groupe depuis le CRM : super admin, direction nationale, ou droit donné au compte.
alter table public.profiles add column if not exists gere_reseau boolean not null default false;

create or replace function public.cap_gere_reseau() returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (select 1 from profiles p where p.id = cap_uid()
    and (p.role in ('superadmin','directeur_national') or p.gere_reseau));
$function$;

alter policy zones_admin on public.zones using (cap_gere_reseau()) with check (cap_gere_reseau());
alter policy clubs_insert on public.clubs with check (cap_gere_reseau());
alter policy clubs_update on public.clubs using (cap_can_edit_club(id) or cap_gere_reseau()) with check (cap_can_edit_club(id) or cap_gere_reseau());
alter policy anim_write on public.animateurs
  using (cap_role() = any (array['superadmin','directeur_national','directeur']) or cap_gere_reseau())
  with check (cap_role() = any (array['superadmin','directeur_national','directeur']) or cap_gere_reseau());

create or replace function public.cap_droits_comptes() returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
begin
  if coalesce(cap_role(), '') <> 'superadmin' then raise exception 'réservé au super admin'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nom', p.nom, 'role', p.role, 'animateur_id', p.animateur_id,
    'gere_reseau', p.gere_reseau, 'gere_documents', p.gere_documents, 'voit_monitoring', p.voit_monitoring)), '[]'::jsonb) from profiles p);
end $function$;

create or replace function public.cap_droit_compte(p_profil uuid, p_droit text, p_oui boolean) returns boolean language plpgsql security definer set search_path to 'public'
as $function$
begin
  if coalesce(cap_role(), '') <> 'superadmin' or cap_voir() is not null then raise exception 'réservé au super admin'; end if;
  if p_droit = 'gere_reseau' then update profiles set gere_reseau = coalesce(p_oui, false) where id = p_profil;
  elsif p_droit = 'gere_documents' then update profiles set gere_documents = coalesce(p_oui, false) where id = p_profil;
  elsif p_droit = 'voit_monitoring' then update profiles set voit_monitoring = coalesce(p_oui, false) where id = p_profil;
  else raise exception 'droit inconnu'; end if;
  return found;
end $function$;
