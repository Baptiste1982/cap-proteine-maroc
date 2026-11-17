-- v1.30.0 — Chiffres par période (plan du 17/11/2026, lot H) et invités sans l'équipe inscrite.
-- cap_tableau_club : la série mensuelle porte aussi le nombre d'affaires signées, et « moi_serie » donne au membre
-- ses propres chiffres mois par mois (12 mois) : l'espace membre en tire le mois, le trimestre, le semestre et l'année.
-- cap_groupe_vue : le compteur d'invités de la prochaine réunion ne compte plus l'équipe inscrite (« Je viens »).

CREATE OR REPLACE FUNCTION public.cap_tableau_club(p_club uuid, p_mb uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_mb uuid; v_club uuid := p_club; v_ville text; v_cnom text; v_zid uuid; v_znom text; v_clubs uuid[]; v_res json;
begin
  if not cap_peut_voir_groupe(p_club) then raise exception 'accès refusé'; end if;
  v_mb := case when p_mb is not null and p_mb = cap_membre_id() then p_mb end;
  select c.ville, c.nom into v_ville, v_cnom from clubs c where c.id = v_club;
  select z.id, z.nom into v_zid, v_znom from zones z
   where exists (select 1 from unnest(z.villes) v where lower(unaccent_simple(v)) = lower(unaccent_simple(v_ville))) limit 1;
  if v_zid is not null then
    select array_agg(c.id) into v_clubs from clubs c, zones z
     where z.id = v_zid and exists (select 1 from unnest(z.villes) v where lower(unaccent_simple(v)) = lower(unaccent_simple(c.ville)));
  else
    select array_agg(c.id) into v_clubs from clubs c where lower(c.ville) = lower(v_ville);
  end if;
  with r as (select * from recommandations where club_id = any(v_clubs)),
  mois as (select generate_series(date_trunc('month', now()) - interval '11 months', date_trunc('month', now()), interval '1 month') as m),
  agg as (
    select x.cle,
      count(*) filter (where r.cree_le >= date_trunc('month', now())) recos_mois,
      count(*) filter (where r.cree_le >= date_trunc('year', now())) recos_annee,
      count(*) filter (where r.statut = 'signee' and r.maj_le >= date_trunc('month', now())) affaires_mois,
      count(*) filter (where r.statut = 'signee' and r.maj_le >= date_trunc('year', now())) affaires_annee,
      coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= date_trunc('month', now())), 0) ca_mois,
      coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= date_trunc('year', now())), 0) ca_annee,
      count(*) filter (where r.statut not in ('signee','sans_suite')) en_cours
    from (values ('groupe'),('region')) x(cle)
    left join r on (x.cle = 'region' or r.club_id = v_club)
    group by x.cle),
  serie as (
    select x.cle, json_agg(json_build_object('mois', to_char(mo.m, 'YYYY-MM'),
      'recos', (select count(*) from r where date_trunc('month', r.cree_le) = mo.m and (x.cle = 'region' or r.club_id = v_club)),
      'affaires', (select count(*) from r where r.statut = 'signee' and date_trunc('month', r.maj_le) = mo.m and (x.cle = 'region' or r.club_id = v_club)),
      'ca', (select coalesce(sum(montant), 0) from r where r.statut = 'signee' and date_trunc('month', r.maj_le) = mo.m and (x.cle = 'region' or r.club_id = v_club)))
      order by mo.m) s
    from (values ('groupe'),('region')) x(cle) cross join mois mo group by x.cle),
  moi as (
    select
      count(*) filter (where de = v_mb) donnees,
      count(*) filter (where a = v_mb) recues,
      count(*) filter (where de = v_mb and statut = 'signee') donnees_signees,
      count(*) filter (where a = v_mb and statut = 'signee') recues_signees,
      coalesce(sum(montant) filter (where de = v_mb and statut = 'signee'), 0) ca_transmis,
      coalesce(sum(montant) filter (where a = v_mb and statut = 'signee'), 0) ca_recu,
      coalesce(sum(montant) filter (where de = v_mb and statut = 'signee' and maj_le >= date_trunc('month', now())), 0) ca_transmis_mois,
      coalesce(sum(montant) filter (where a = v_mb and statut = 'signee' and maj_le >= date_trunc('month', now())), 0) ca_recu_mois,
      count(*) filter (where a = v_mb and statut not in ('signee','sans_suite')) recues_en_cours
    from recommandations where v_mb is not null and (de = v_mb or a = v_mb))
  select json_build_object(
    'moi', case when v_mb is not null then (select row_to_json(moi) from moi) end,
    'groupe', (select json_build_object('nom', v_cnom, 'membres', (select count(*) from membres where club_id = v_club)) :: jsonb
               || to_jsonb(a) - 'cle' || jsonb_build_object('serie', s.s) from agg a join serie s using (cle) where a.cle = 'groupe'),
    'region', (select json_build_object('nom', coalesce(v_znom, v_ville), 'groupes', coalesce(array_length(v_clubs, 1), 0),
                 'membres', (select count(*) from membres where club_id = any(v_clubs))) :: jsonb
               || to_jsonb(a) - 'cle' || jsonb_build_object('serie', s.s) from agg a join serie s using (cle) where a.cle = 'region'),
    'moi_serie', case when v_mb is not null then (select json_agg(json_build_object('mois', to_char(mo.m, 'YYYY-MM'),
        'donnees', (select count(*) from recommandations x where x.de = v_mb and date_trunc('month', x.cree_le) = mo.m),
        'recues', (select count(*) from recommandations x where x.a = v_mb and date_trunc('month', x.cree_le) = mo.m),
        'ca_transmis', (select coalesce(sum(x.montant), 0) from recommandations x where x.de = v_mb and x.statut = 'signee' and date_trunc('month', x.maj_le) = mo.m),
        'ca_recu', (select coalesce(sum(x.montant), 0) from recommandations x where x.a = v_mb and x.statut = 'signee' and date_trunc('month', x.maj_le) = mo.m))
        order by mo.m) from mois mo) end,
    'calcule_le', now()) into v_res;
  return v_res;
end $function$;

CREATE OR REPLACE FUNCTION public.cap_groupe_vue(p_club uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        'adresse', l.adresse, 'ville', coalesce(l.ville, c.ville), 'invites', (select count(*) from invites i where i.reunion_id = r.id and i.profil_id is null),
        'ma_reponse', (select rr.reponse from reunion_reponses rr where rr.reunion_id = r.id and rr.membre_id = v_mb),
        'viennent', (select count(*) from reunion_reponses rr where rr.reunion_id = r.id and rr.reponse = 'oui'),
        'absents', (select count(*) from reunion_reponses rr where rr.reunion_id = r.id and rr.reponse = 'non'))
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
      from invites i left join membres pm on pm.id = i.propose_par where i.reunion_id = v_prochaine and i.profil_id is null),
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
end $function$;
