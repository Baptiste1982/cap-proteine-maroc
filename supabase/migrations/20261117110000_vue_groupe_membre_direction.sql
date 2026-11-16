-- v1.3.0 — « Mon groupe » : l'accueil du groupe dans l'espace membre, et la même vue pour la direction.
-- Accès : un membre du groupe, ou l'équipe qui peut modifier le groupe (animateur du groupe, directeur de sa zone,
-- direction nationale, superadmin). Jamais un membre d'un autre groupe.
-- Métier affiché : la spécialité saisie d'abord, jamais « - Autre - ».
create or replace function public.cap_metier_membre(p_infos jsonb, p_specialite text)
returns text language sql immutable as $$
  select coalesce(nullif(trim(p_infos->>'metier_precis'), ''),
                  nullif(nullif(trim(p_infos->>'metier'), ''), '- Autre -'),
                  nullif(trim(p_specialite), ''))
$$;

create or replace function public.cap_peut_voir_groupe(p_club uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from membres m where m.user_id = auth.uid() and m.club_id = p_club)
      or (cap_est_equipe() and cap_can_edit_club(p_club))
$$;

-- Chiffres d'un groupe et de sa région (+ ceux du membre si p_mb est le membre connecté). Vérifie l'accès lui-même.
create or replace function public.cap_tableau_club(p_club uuid, p_mb uuid default null)
returns json language plpgsql stable security definer set search_path = public as $$
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
    'calcule_le', now()) into v_res;
  return v_res;
end $$;

-- Le tableau du membre passe par le même calcul.
create or replace function public.cap_membre_tableau()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_mb uuid := cap_membre_id(); v_club uuid;
begin
  if v_mb is null then raise exception 'aucune fiche membre liée'; end if;
  select club_id into v_club from membres where id = v_mb;
  return cap_tableau_club(v_club, v_mb);
end $$;

-- L'accueil du groupe en une seule lecture. p_club vide = le groupe du membre connecté.
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
    'prochaine', (select json_build_object('id', r.id, 'date', r.date, 'heure', r.heure, 'type', r.type, 'lieu', l.nom,
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

-- L'annuaire de l'espace membre affiche aussi la spécialité plutôt que « - Autre - ».
create or replace function public.cap_annuaire_fiche()
returns table(id uuid, nom text, club text, club_id uuid, ville text, metier text, entreprise text, activite text, cherche text,
              telephone text, inscrit boolean, moi boolean, photo text, logo text, presentation text, site text, linkedin text,
              reseaux text, fonction text)
language sql stable security definer set search_path = public as $$
  select m.id, m.nom, c.nom, m.club_id, coalesce(nullif(m.infos->>'ent_ville', ''), c.ville),
         cap_metier_membre(m.infos, m.specialite), m.infos->>'ent_nom', m.infos->>'ent_activite', m.cherche,
         case when m.tel_visible then m.infos->>'m_tel' end, m.user_id is not null, m.user_id = auth.uid(),
         m.photo_url, m.logo_url,
         coalesce(nullif(m.presentation, ''), nullif(m.infos->>'ent_activite', '')),
         coalesce(nullif(m.site, ''), nullif(m.infos->>'ent_web', '')),
         m.linkedin, m.reseaux, m.infos->>'m_fonction'
  from membres m left join clubs c on c.id = m.club_id
  where (cap_membre_id() is not null or cap_est_equipe())
    and (m.annuaire_visible or m.user_id = auth.uid())
  order by m.nom
$$;
