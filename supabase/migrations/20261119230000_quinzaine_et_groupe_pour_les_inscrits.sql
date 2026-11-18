-- Le réseau fonctionne par quinzaine : les chiffres « récents » du groupe portent sur 14 jours (avant : 7).
create or replace function public.cap_groupe_semaine(p_club uuid default null::uuid)
 returns json language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_club uuid := p_club; v_mb uuid := cap_membre_id(); v_res json;
begin
  if v_club is null then select club_id into v_club from membres where id = v_mb; end if;
  if v_club is null or not cap_peut_voir_groupe(v_club) then raise exception 'accès refusé'; end if;
  select json_build_object(
    'jours', 14, 'du', (current_date - 14), 'au', current_date,
    'recos', count(*) filter (where r.cree_le >= now() - interval '14 days'),
    'affaires', count(*) filter (where r.statut = 'signee' and r.maj_le >= now() - interval '14 days'),
    'ca', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= now() - interval '14 days'), 0),
    'recos_avant', count(*) filter (where r.cree_le >= now() - interval '28 days' and r.cree_le < now() - interval '14 days'),
    'ca_avant', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= now() - interval '28 days' and r.maj_le < now() - interval '14 days'), 0))
  into v_res from recommandations r where r.club_id = v_club;
  return v_res;
end $function$;

-- Qui est prévu à une réunion, pour l'équipe qui voit le groupe ou qui s'y est inscrite : invités, équipe, membres qui viennent,
-- et maintenant les membres du groupe et les chiffres de la quinzaine (recommandations, affaires signées, chiffre d'affaires).
create or replace function public.cap_reunion_prevus(p_reunion uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_club uuid;
begin
  if not cap_est_equipe() or coalesce(cap_role(),'') = 'visiteur' then raise exception 'réservé à l''équipe'; end if;
  select club_id into v_club from reunions where id = p_reunion;
  if v_club is null then return jsonb_build_object('acces', false); end if;
  if not (cap_can_see_club(v_club) or exists (select 1 from invites i where i.reunion_id = p_reunion and i.profil_id = cap_uid())) then
    return jsonb_build_object('acces', false);
  end if;
  return jsonb_build_object('acces', true,
    'invites', (select coalesce(jsonb_agg(jsonb_build_object('nom', i.nom, 'entreprise', coalesce(i.entreprise,''), 'metier', coalesce(i.metier,''), 'statut', i.statut, 'par', coalesce(i.invite_par,'')) order by i.created_at), '[]'::jsonb)
                from invites i where i.reunion_id = p_reunion and i.profil_id is null),
    'equipe', (select coalesce(jsonb_agg(i.nom order by i.created_at), '[]'::jsonb) from invites i where i.reunion_id = p_reunion and i.profil_id is not null),
    'membres', (select coalesce(jsonb_agg(jsonb_build_object('nom', mb.nom, 'metier', coalesce(cap_metier_membre(mb.infos, mb.specialite),'')) order by mb.nom), '[]'::jsonb)
                from reunion_reponses rr join membres mb on mb.id = rr.membre_id where rr.reunion_id = p_reunion and rr.reponse = 'oui'),
    'groupe', (select coalesce(jsonb_agg(jsonb_build_object('nom', mb.nom, 'metier', coalesce(cap_metier_membre(mb.infos, mb.specialite),''), 'entreprise', coalesce(mb.infos->>'ent_nom',''),
                  'vient', (select rr.reponse from reunion_reponses rr where rr.reunion_id = p_reunion and rr.membre_id = mb.id)) order by mb.num), '[]'::jsonb)
                from membres mb where mb.club_id = v_club),
    'quinzaine', (select jsonb_build_object(
                  'recos', count(*) filter (where r.cree_le >= now() - interval '14 days'),
                  'affaires', count(*) filter (where r.statut = 'signee' and r.maj_le >= now() - interval '14 days'),
                  'ca', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= now() - interval '14 days'), 0))
                from recommandations r where r.club_id = v_club));
end $function$;
