-- v1.38.0 — Statut de groupe calculé (plan du 17/11/2026, choix de JB : « calculé d'après les membres et les réunions »).
-- Actif = au moins 5 fiches de membres, ou une réunion de lancement / du cycle tenue. Sinon : en création.
-- statut_fixe = groupe déjà actif dont la vie n'est pas saisie dans le CRM (autres régions) : reste « actif ».
alter table public.clubs add column if not exists statut_fixe boolean not null default false;

create or replace function public.cap_club_statut_calc(p_club uuid, p_fixe boolean)
returns text language sql stable security definer set search_path to 'public' as $$
  select case when coalesce(p_fixe, false)
      or (select count(*) from membres m where m.club_id = p_club) >= 5
      or exists (select 1 from reunions r where r.club_id = p_club and r.statut = 'realisee' and (r.type = 'RL' or r.format is not null))
    then 'actif' else 'creation' end
$$;

create or replace function public.clubs_statut_avant() returns trigger language plpgsql security definer set search_path to 'public' as $$
begin new.statut := cap_club_statut_calc(new.id, new.statut_fixe); return new; end $$;

create or replace function public.clubs_statut_suivre() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_ids uuid[] := '{}';
begin
  if tg_op <> 'INSERT' then v_ids := v_ids || old.club_id; end if;
  if tg_op <> 'DELETE' then v_ids := v_ids || new.club_id; end if;
  update clubs c set statut = cap_club_statut_calc(c.id, c.statut_fixe)
    where c.id = any (v_ids) and c.statut is distinct from cap_club_statut_calc(c.id, c.statut_fixe);
  return null;
end $$;

create or replace trigger clubs_statut_avant before insert or update on public.clubs
  for each row execute function public.clubs_statut_avant();
create or replace trigger membres_statut_club after insert or delete or update of club_id on public.membres
  for each row execute function public.clubs_statut_suivre();
create or replace trigger reunions_statut_club after insert or delete or update of club_id, statut, type, format on public.reunions
  for each row execute function public.clubs_statut_suivre();

-- Mise à niveau : les groupes aujourd'hui « actifs » hors de la région Rabat · Salé · Kénitra gardent leur statut (fixé),
-- puis tous les statuts sont recalculés (13 lignes).
update public.clubs c set statut_fixe = true
  where c.statut = 'actif' and cap_club_statut_calc(c.id, false) = 'creation'
    and not exists (select 1 from zones z, unnest(z.villes) v
      where z.nom ilike 'Rabat%' and lower(unaccent_simple(v)) = lower(unaccent_simple(c.ville)));
update public.clubs set statut = statut;
