-- v0.35.0 — Espace « Mon groupe » de l'animateur.
-- 1. Les métiers que le groupe cherche à recruter (liste libre, tirée de la liste officielle côté front).
alter table public.clubs add column if not exists metiers_recherches jsonb not null default '[]'::jsonb;
comment on column public.clubs.metiers_recherches is 'Métiers que le groupe cherche à recruter (tableau de libellés, liste officielle du national).';

-- 2. L'animateur peut noter une affaire (recommandation) annoncée en réunion, entre deux membres de son groupe.
--    Même droit que la modification déjà en place : équipe + club éditable.
create policy recos_equipe_ajouter on public.recommandations
  for insert to authenticated
  with check (cap_est_equipe() and cap_can_edit_club(club_id));
