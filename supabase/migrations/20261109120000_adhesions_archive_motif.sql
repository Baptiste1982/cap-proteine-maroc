-- v0.36.0 — Retirer une candidature avec un motif : elle passe en statut « rejetee » (archives),
-- reste consultable et peut être restaurée.
alter table public.adhesions add column if not exists archivee_le timestamptz;
alter table public.adhesions add column if not exists archive_motif text;
alter table public.adhesions add column if not exists archive_par uuid references auth.users(id);
comment on column public.adhesions.archive_motif is 'Motif saisi quand la candidature est retirée (statut rejetee) ; elle reste consultable dans les archives et peut être restaurée.';
