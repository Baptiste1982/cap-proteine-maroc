-- v1.6.0 : la prochaine réunion du groupe porte son format (business, conférence, visite) et son thème.
create or replace function public.cap_groupe_vue(p_club uuid default null)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_club uuid := p_club; v_mb uuid := cap_membre_id(); v_prochaine uuid; v_res json;
begin
  if v_club is null then select club_id into v_club from membres where id = v_mb; end if;
  if v_club is null or not cap_peut_voir_groupe(v_club) then raise exception 'accès refusé'; end if;
  select r.id into v_prochaine from reunions r where r.club_id = v_club and r.date >= current_date and r.statut <> 'annulee'
   order by r.date, r.heure nulls last limit 1;
  select json_build_object(
    'club', (select json_build_object('id', c.id, 'nom', c.nom, 'ville', c.ville, 'statut', c.statut, 'objectif', c.objectif,
        'animateur', a.nom, 'rythme_jour', c.rythme_jour, 'rythme_rang', c.rythme_rang, 'rythme_pas', c.rythme_pas,
        'heure', c.heure_habituelle, 'lieu', l.nom, 'metiers_recherches', coalesce(c.metiers_recherches, '[]'::jsonb))
      from clubs c left join animateurs a on a.id = c.animateur_id left join lieux l on l.id = c.lieu_habituel_id where c.id = v_club),
    'prochaine', (select json_build_object('id', r.id, 'date', r.date, 'heure', r.heure, 'type', r.type, 'format', r.format, 'theme', r.theme, 'lieu', l.nom,
        'adresse', l.adresse, 'ville', coalesce(l.ville, c.ville), 'invites', (select count(*) from invites i where i.reunion_id = r.id))
      from reunions r join clubs c on c.id = r.club_id left join lieux l on l.id = r.lieu_id where r.id = v_prochaine),
    'reunions', (select json_build_object('a_venir', count(*) filter (where r.date >= current_date and r.statut <> 'annulee'),
        'faites_annee', count(*) filter (where r.statut = 'realisee' and r.date >= date_trunc('year', now())),
        'presents_moyen', round(avg(r.presents) filter (where r.statut = 'realisee' and r.presents is not null)))
      from reunions r where r.club_id = v_club),
    'membres', (select coalesce(json_agg(json_build_object('id', m.id, 'nom', m.nom,
        'metier', cap_metier_membre(m.infos, m.specialite), 'entreprise', m.infos->>'ent_nom',
        'photo', m.photo_url, 'inscrit', m.user_id is not null, 'moi', m.id = v_mb) order by m.num nulls last, m.nom), '[]')
      from membres m where m.club_id = v_club),
    'invites', (select coalesce(json_agg(json_build_object('id', i.id, 'nom', i.nom, 'entreprise', i.entreprise, 'metier', i.metier,
        'tel', i.tel, 'email', i.email, 'statut', i.statut, 'invite_par', coalesce(pm.nom, i.invite_par)) order by i.nom), '[]')
      from invites i left join membres pm on pm.id = i.propose_par where i.reunion_id = v_prochaine),
    'recos', (select coalesce(json_agg(x order by x.cree_le desc), '[]') from (
        select r.id, d.nom de_nom, b.nom a_nom, r.statut, r.montant, r.cree_le, r.maj_le
        from recommandations r left join membres d on d.id = r.de left join membres b on b.id = r.a
        where r.club_id = v_club order by r.cree_le desc limit 8) x),
    'messages', (select coalesce(json_agg(x order by x.cree_le), '[]') from (
        select g.id, g.auteur_nom, g.membre_id, g.texte, g.cree_le from messages_groupe g
        where g.club_id = v_club order by g.cree_le desc limit 4) x),
    'chiffres', cap_tableau_club(v_club, v_mb),
    'vue_equipe', v_mb is null or not exists (select 1 from membres where id = v_mb and club_id = v_club)) into v_res;
  return v_res;
end $$;
