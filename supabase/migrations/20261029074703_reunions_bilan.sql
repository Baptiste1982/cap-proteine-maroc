-- v0.15 : bilan de réunion. Après chaque réunion, le CRM demande ce qui s'est passé.
-- Colonnes ajoutées (nullable, rien n'est réécrit) ; les droits d'écriture restent ceux de reunions_update.
alter table public.reunions add column if not exists presents integer check (presents is null or presents >= 0);
alter table public.reunions add column if not exists invites_venus integer check (invites_venus is null or invites_venus >= 0);
alter table public.reunions add column if not exists adhesions_obtenues integer check (adhesions_obtenues is null or adhesions_obtenues >= 0);
alter table public.reunions add column if not exists bilan_le timestamptz;
comment on column public.reunions.presents is 'Bilan : nombre de personnes présentes';
comment on column public.reunions.invites_venus is 'Bilan : nombre d''invités venus';
comment on column public.reunions.adhesions_obtenues is 'Bilan : adhésions obtenues à la réunion';
comment on column public.reunions.bilan_le is 'Date de saisie du bilan';
