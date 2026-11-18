-- v1.70.0 — dans la liste des invités d'une réunion, distinguer : membre du groupe, membre d'un autre groupe,
-- invité extérieur au réseau. Rapprochement invité ↔ fiche membre : compte relié, même mobile, même e-mail ou même nom.
create or replace function public.cap_reunion_qualites(p_reunion uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_club uuid; v_mb uuid := cap_membre_id(); v_ok boolean := false;
begin
  select club_id into v_club from reunions where id = p_reunion;
  if v_club is null then return '[]'::jsonb; end if;
  if cap_est_equipe() and coalesce(cap_role(), '') <> 'visiteur' then
    v_ok := cap_can_see_club(v_club) or exists (select 1 from invites i where i.reunion_id = p_reunion and i.profil_id = cap_uid());
  end if;
  if not v_ok and v_mb is not null then
    v_ok := exists (select 1 from membres where id = v_mb and club_id = v_club)
         or exists (select 1 from reunion_reponses rr where rr.reunion_id = p_reunion and rr.membre_id = v_mb and rr.reponse = 'oui');
  end if;
  if not v_ok then return '[]'::jsonb; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'nom', i.nom,
            'q', case when x.club_id = v_club then 'groupe' else 'reseau' end, 'groupe', x.club)), '[]'::jsonb)
          from invites i
          join lateral (
            select mb.club_id, c.nom club from membres mb left join clubs c on c.id = mb.club_id
            where (i.profil_id is not null and mb.user_id = i.profil_id)
               or (cap_tel_norm(i.tel) is not null and cap_tel_norm(mb.infos->>'m_tel') = cap_tel_norm(i.tel))
               or (nullif(lower(trim(i.email)), '') is not null and lower(trim(mb.infos->>'m_email')) = lower(trim(i.email)))
               or (length(cap_nom_cle(i.nom)) >= 6 and cap_nom_cle(mb.nom) = cap_nom_cle(i.nom))
            order by (mb.club_id = v_club) desc, mb.created_at limit 1) x on true
          where i.reunion_id = p_reunion);
end $function$;

-- Aperçu « voir comme » : lecture permise.
create or replace function public.cap_voir()
 returns text language plpgsql stable security definer set search_path to 'public'
as $function$
declare v text; p text;
begin
  if auth.uid() is null then return null; end if;
  begin v := nullif(current_setting('request.headers', true)::json->>'x-cap-voir', ''); exception when others then return null; end;
  if v is null or v !~ '^[um]:[0-9a-f-]{36}$' then return null; end if;
  if not exists (select 1 from profiles where id = auth.uid() and role = 'superadmin') then return null; end if;
  p := coalesce(current_setting('request.path', true), '');
  if coalesce(current_setting('request.method', true), 'GET') not in ('GET', 'HEAD')
     and p !~ '^/rpc/(cap_annuaire|cap_annuaire_fiche|cap_annuaire_contacts|cap_annuaire_regions|cap_groupe_vue|cap_groupe_semaine|cap_membre_tableau|cap_tableau_club|cap_membre_prochaine_reunion|cap_membre_invites_groupe|cap_membre_mes_invites|cap_membre_recos_club|cap_membre_id|cap_role|cap_peut_voir_groupe|cap_docs_profil|cap_zone_villes|cap_membres_connexions|cap_qui_connecte|cap_equipe_etat|cap_acces_equipe|cap_voir_qui|cap_membre_moi|cap_membre_reunions_reseau|cap_membre_reunion_prevus|cap_reunion_prevus|cap_reunion_reponses|cap_quinzaine_debut|cap_reunion_qualites)$' then
    raise exception 'Aperçu en lecture seule : rien ne peut être modifié.';
  end if;
  return v;
end $function$;
