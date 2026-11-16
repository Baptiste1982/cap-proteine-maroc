-- v0.48.0 : inscrits par le lien d'invitation du CRM national, rapatriés dans les invités. Appliquée le 16/11/2026.
alter table public.invites add column if not exists email text, add column if not exists national_id text;
create unique index if not exists invites_reunion_national on public.invites(reunion_id, national_id) where national_id is not null;
comment on column public.invites.national_id is 'Id du destinataire dans les statistiques de l''invitation du CRM national (inscrit par le lien)';
