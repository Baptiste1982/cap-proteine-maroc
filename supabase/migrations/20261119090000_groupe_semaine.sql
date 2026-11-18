-- v1.52.0 — chiffres du groupe sur les 7 derniers jours (carte de la prochaine réunion, accueil du membre).
-- Lecture seule ; même contrôle d'accès que cap_groupe_vue (membre du groupe ou équipe qui le gère).
create or replace function public.cap_groupe_semaine(p_club uuid default null)
returns json
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_club uuid := p_club; v_mb uuid := cap_membre_id(); v_res json;
begin
  if v_club is null then select club_id into v_club from membres where id = v_mb; end if;
  if v_club is null or not cap_peut_voir_groupe(v_club) then raise exception 'accès refusé'; end if;
  select json_build_object(
    'du', (current_date - 7), 'au', current_date,
    'recos', count(*) filter (where r.cree_le >= now() - interval '7 days'),
    'affaires', count(*) filter (where r.statut = 'signee' and r.maj_le >= now() - interval '7 days'),
    'ca', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= now() - interval '7 days'), 0),
    'recos_avant', count(*) filter (where r.cree_le >= now() - interval '14 days' and r.cree_le < now() - interval '7 days'),
    'ca_avant', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= now() - interval '14 days' and r.maj_le < now() - interval '7 days'), 0))
  into v_res from recommandations r where r.club_id = v_club;
  return v_res;
end $function$;
grant execute on function public.cap_groupe_semaine(uuid) to authenticated;
