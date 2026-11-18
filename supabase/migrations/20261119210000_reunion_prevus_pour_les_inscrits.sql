-- Qui est prévu à une réunion : visible de l'équipe qui voit le groupe, et de toute personne de l'équipe inscrite à cette réunion (« Je viens »).
-- Noms, entreprise, métier et statut seulement : jamais de téléphone ni d'e-mail.
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
                from reunion_reponses rr join membres mb on mb.id = rr.membre_id where rr.reunion_id = p_reunion and rr.reponse = 'oui'));
end $function$;
grant execute on function public.cap_reunion_prevus(uuid) to authenticated;
