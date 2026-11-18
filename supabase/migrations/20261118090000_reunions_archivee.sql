-- v1.41.0 — Réunions passées rangées sans bilan (plan G1, choix de JB : « les archiver, hors compteurs »).
-- La réunion reste dans l'historique ; elle ne compte plus dans « bilans à saisir ». Droits inchangés (reunions_update).
alter table public.reunions add column if not exists archivee_le timestamptz, add column if not exists archivee_par uuid;
comment on column public.reunions.archivee_le is 'Réunion passée rangée sans bilan : gardée dans l''historique, hors des compteurs « bilans à saisir ».';
