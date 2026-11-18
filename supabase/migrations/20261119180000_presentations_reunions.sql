-- v1.63 : présentations montées dans le CRM.
-- animateurs.photo / profil : la slide « Qui suis-je ? » ; reunions.presentation : le montage choisi pour la réunion.
alter table public.animateurs add column if not exists photo text, add column if not exists profil jsonb;
alter table public.reunions add column if not exists presentation jsonb;
create or replace function public.cap_anim_profil(p_anim uuid, p_photo text, p_profil jsonb)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not cap_est_equipe() then raise exception 'réservé à l''équipe'; end if;
  if not (cap_animateur_id() = p_anim or coalesce(cap_role(),'') in ('superadmin','directeur_national','directeur')) then
    raise exception 'Tu ne peux modifier que ta propre présentation';
  end if;
  if p_photo is not null and length(p_photo) > 400000 then raise exception 'Photo trop lourde'; end if;
  update animateurs set photo = coalesce(p_photo, photo), profil = coalesce(p_profil, profil) where id = p_anim;
end $function$;
grant execute on function public.cap_anim_profil(uuid, text, jsonb) to authenticated;
