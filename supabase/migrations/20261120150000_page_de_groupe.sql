-- v1.71.0 — page d'un groupe, en consultation : ses membres (nom, métier, entreprise ; aucune coordonnée) et son animateur,
-- à qui l'on demande le numéro d'un membre. Ouverte à l'équipe (hors visiteur) et aux membres.
create or replace function public.cap_groupe_page(p_club uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare c record;
begin
  if not ((cap_est_equipe() and coalesce(cap_role(), '') <> 'visiteur') or cap_membre_id() is not null) then raise exception 'accès refusé'; end if;
  select cl.id, cl.nom, cl.ville, a.nom animateur, a.tel animateur_tel into c from clubs cl left join animateurs a on a.id = cl.animateur_id where cl.id = p_club;
  if c.id is null then return null; end if;
  return jsonb_build_object('id', c.id, 'nom', c.nom, 'ville', c.ville, 'animateur', c.animateur, 'animateur_tel', c.animateur_tel,
    'membres', (select coalesce(jsonb_agg(jsonb_build_object('id', mb.id, 'nom', mb.nom, 'metier', coalesce(cap_metier_membre(mb.infos, mb.specialite), ''),
                  'entreprise', coalesce(mb.infos->>'ent_nom', ''), 'photo', mb.photo_url, 'animateur', mb.animateur_id is not null) order by mb.num), '[]'::jsonb)
                from membres mb where mb.club_id = p_club and (mb.annuaire_visible or mb.id = cap_membre_id())));
end $function$;

-- Les qualités des inscrits portent aussi l'identifiant du groupe (pour ouvrir sa page).
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
            'q', case when x.club_id = v_club then 'groupe' else 'reseau' end, 'groupe', x.club, 'club_id', x.club_id)), '[]'::jsonb)
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
