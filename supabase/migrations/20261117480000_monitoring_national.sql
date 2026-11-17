-- v1.32.0 — Monitoring national (plan du 17/11/2026, lot I).
-- Accès : super admin, directeur national, ou droit profiles.voit_monitoring donné compte par compte (bureau national).
-- Les deux fonctions ne renvoient que des chiffres agrégés et des noms : aucune coordonnée, aucune donnée légale.
alter table public.profiles add column if not exists voit_monitoring boolean not null default false;

create or replace function public.cap_peut_monitoring()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from profiles p where p.id = cap_uid()
    and (p.role in ('superadmin', 'directeur_national') or p.voit_monitoring))
$$;

-- Tout le réseau, groupe par groupe et mois par mois.
create or replace function public.cap_monitoring()
returns json language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not cap_peut_monitoring() then raise exception 'réservé au monitoring'; end if;
  return json_build_object(
    'clubs', (select coalesce(json_agg(json_build_object('id', c.id, 'nom', c.nom, 'ville', c.ville, 'statut', c.statut,
        'animateur', a.nom, 'objectif', c.objectif,
        'zone', (select z.nom from zones z where exists (select 1 from unnest(z.villes) v
                  where lower(unaccent_simple(v)) = lower(unaccent_simple(c.ville))) order by z.nom limit 1),
        'membres', (select count(*) from membres m where m.club_id = c.id),
        'cles', (select coalesce(json_agg(md5(lower(unaccent_simple(trim(m.nom))))), '[]') from membres m where m.club_id = c.id))
      order by c.nom), '[]') from clubs c left join animateurs a on a.id = c.animateur_id),
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
      ) u where u.club_id is not null group by u.club_id, u.mois) s),
    'calcule_le', now());
end $$;

-- Le détail d'un groupe : ses membres et leurs affaires (noms et chiffres seulement).
create or replace function public.cap_monitoring_groupe(p_club uuid)
returns json language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not cap_peut_monitoring() then raise exception 'réservé au monitoring'; end if;
  return (select coalesce(json_agg(json_build_object('id', m.id, 'nom', m.nom, 'metier', cap_metier_membre(m.infos, m.specialite),
      'entree', m.created_at::date,
      'donnees', (select count(*) from recommandations r where r.de = m.id),
      'recues', (select count(*) from recommandations r where r.a = m.id),
      'ca_transmis', (select coalesce(sum(r.montant), 0) from recommandations r where r.de = m.id and r.statut = 'signee'),
      'ca_recu', (select coalesce(sum(r.montant), 0) from recommandations r where r.a = m.id and r.statut = 'signee'))
    order by m.num nulls last, m.nom), '[]') from membres m where m.club_id = p_club);
end $$;
grant execute on function public.cap_peut_monitoring(), public.cap_monitoring(), public.cap_monitoring_groupe(uuid) to authenticated;
