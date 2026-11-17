-- v1.26.0 : région de chaque groupe pour l'annuaire de l'espace membre (appliquée en prod le 17/11/2026).
create or replace function public.cap_annuaire_regions()
returns table(club_id uuid, region text, region_id uuid)
language sql stable security definer set search_path to 'public'
as $$
  select c.id, coalesce(z.nom, c.ville), z.id
  from clubs c
  left join lateral (
    select z.id, z.nom from zones z
    where exists (select 1 from unnest(z.villes) v where unaccent_simple(lower(v)) = unaccent_simple(lower(c.ville)))
    order by z.nom limit 1
  ) z on true
  where (cap_membre_id() is not null or cap_est_equipe())
$$;
grant execute on function public.cap_annuaire_regions() to authenticated;
