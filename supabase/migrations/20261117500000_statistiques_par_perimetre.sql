-- v1.35.0 — Les statistiques (courbes, détail, prévisionnel) pour chaque niveau : national, région, groupe.
-- Les groupes du périmètre de l'appelant, mois par mois : tout le réseau pour la direction nationale et les comptes
-- « monitoring », sa zone pour un directeur, ses groupes pour un animateur (même règle que cap_can_see_club).
create or replace function public.cap_monitoring()
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare v_tout boolean := cap_peut_monitoring(); v_ids uuid[];
begin
  if not v_tout and coalesce(cap_role(), '') not in ('directeur', 'animateur') then raise exception 'réservé à l''équipe'; end if;
  select coalesce(array_agg(c.id), '{}') into v_ids from clubs c where v_tout or cap_can_see_club(c.id);
  return json_build_object(
    'portee', case when v_tout then 'reseau' else cap_role() end,
    'clubs', (select coalesce(json_agg(json_build_object('id', c.id, 'nom', c.nom, 'ville', c.ville, 'statut', c.statut,
        'animateur', a.nom, 'objectif', c.objectif,
        'zone', (select z.nom from zones z where exists (select 1 from unnest(z.villes) v
                  where lower(unaccent_simple(v)) = lower(unaccent_simple(c.ville))) order by z.nom limit 1),
        'membres', (select count(*) from membres m where m.club_id = c.id),
        'cles', (select coalesce(json_agg(md5(lower(unaccent_simple(trim(m.nom))))), '[]') from membres m where m.club_id = c.id))
      order by c.nom), '[]') from clubs c left join animateurs a on a.id = c.animateur_id where c.id = any (v_ids)),
    'series', (select coalesce(json_agg(s), '[]') from (
      select u.club_id, u.mois, sum(u.membres) membres, sum(u.tenues) tenues, sum(u.presents) presents, sum(u.presents_n) presents_n,
             sum(u.invites) invites, sum(u.adh) adh, sum(u.recos) recos, sum(u.affaires) affaires, sum(u.ca) ca
      from (
        select m.club_id, to_char(m.created_at, 'YYYY-MM') mois, 1 membres, 0 tenues, 0 presents, 0 presents_n, 0 invites, 0 adh, 0 recos, 0 affaires, 0::numeric ca
          from membres m
        union all
        select r.club_id, to_char(r.date, 'YYYY-MM'), 0, (r.statut = 'realisee')::int,
               case when r.statut = 'realisee' then coalesce(r.presents, 0) else 0 end,
               (r.statut = 'realisee' and r.presents is not null)::int,
               (select count(*) from invites i where i.reunion_id = r.id and i.profil_id is null)::int, 0, 0, 0, 0
          from reunions r where r.statut <> 'annulee'
        union all
        select coalesce(mb.club_id, case when a.ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then a.ref::uuid end),
               to_char(a.created_at, 'YYYY-MM'), 0, 0, 0, 0, 0, 1, 0, 0, 0
          from adhesions a left join membres mb on mb.id = a.membre_id where a.statut <> 'rejetee'
        union all
        select rc.club_id, to_char(rc.cree_le, 'YYYY-MM'), 0, 0, 0, 0, 0, 0, 1, 0, 0 from recommandations rc
        union all
        select rc.club_id, to_char(rc.maj_le, 'YYYY-MM'), 0, 0, 0, 0, 0, 0, 0, 1, coalesce(rc.montant, 0)
          from recommandations rc where rc.statut = 'signee'
      ) u where u.club_id = any (v_ids) group by u.club_id, u.mois) s),
    'calcule_le', now());
end $$;

-- Le détail d'un groupe : ses membres et leurs affaires (noms et chiffres seulement).
create or replace function public.cap_monitoring_groupe(p_club uuid)
returns json language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not (cap_peut_monitoring() or cap_can_see_club(p_club)) then raise exception 'groupe hors de ton périmètre'; end if;
  return (select coalesce(json_agg(json_build_object('id', m.id, 'nom', m.nom, 'metier', cap_metier_membre(m.infos, m.specialite),
      'entree', m.created_at::date,
      'donnees', (select count(*) from recommandations r where r.de = m.id),
      'recues', (select count(*) from recommandations r where r.a = m.id),
      'ca_transmis', (select coalesce(sum(r.montant), 0) from recommandations r where r.de = m.id and r.statut = 'signee'),
      'ca_recu', (select coalesce(sum(r.montant), 0) from recommandations r where r.a = m.id and r.statut = 'signee'))
    order by m.num nulls last, m.nom), '[]') from membres m where m.club_id = p_club);
end $$;
