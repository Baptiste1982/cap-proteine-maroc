-- v1.125 : un groupe peut être mis en pause, avec un motif. Les droits ne changent pas (ceux de la mise à jour d'un groupe).
alter table public.clubs
  add column if not exists pause_le timestamptz,
  add column if not exists pause_motif text,
  add column if not exists pause_par text,
  add column if not exists pause_reprise date;
comment on column public.clubs.pause_le is 'Groupe en pause depuis cette date (vide = groupe en activité)';
