-- v1.2.0 — Tableau de bord chiffré pour le membre : lui, son groupe, sa région.
-- Le membre voit les totaux de sa région, mais jamais le détail des autres groupes.
-- Calculé à la volée à partir de recommandations : chaque saisie met les chiffres à jour.
-- Comparaison de villes sans accents (Kénitra = Kenitra), sans dépendre de l'extension unaccent.
create or replace function public.unaccent_simple(t text) returns text language sql immutable as $$
  select translate(coalesce(t, ''), 'ÀÂÄÁÃàâäáãÉÈÊËéèêëÎÏÍÌîïíìÔÖÓÒÕôöóòõÛÜÚÙûüúùÇç', 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc')
$$;

create or replace function public.cap_membre_tableau()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_mb uuid; v_club uuid; v_ville text; v_cnom text; v_zid uuid; v_znom text; v_clubs uuid[]; v_res json;
begin
  v_mb := cap_membre_id();
  if v_mb is null then raise exception 'aucune fiche membre liée'; end if;
  select m.club_id, c.ville, c.nom into v_club, v_ville, v_cnom from membres m join clubs c on c.id = m.club_id where m.id = v_mb;
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
    from recommandations where de = v_mb or a = v_mb)
  select json_build_object(
    'moi', (select row_to_json(moi) from moi),
    'groupe', (select json_build_object('nom', v_cnom, 'membres', (select count(*) from membres where club_id = v_club)) :: jsonb
               || to_jsonb(a) - 'cle' || jsonb_build_object('serie', s.s) from agg a join serie s using (cle) where a.cle = 'groupe'),
    'region', (select json_build_object('nom', coalesce(v_znom, v_ville), 'groupes', coalesce(array_length(v_clubs, 1), 0),
                 'membres', (select count(*) from membres where club_id = any(v_clubs))) :: jsonb
               || to_jsonb(a) - 'cle' || jsonb_build_object('serie', s.s) from agg a join serie s using (cle) where a.cle = 'region'),
    'calcule_le', now()) into v_res;
  return v_res;
end $$;

