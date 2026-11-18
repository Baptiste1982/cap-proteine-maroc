-- v1.80.0 — effectif déclaré par le bureau national pour un groupe dont les fiches ne sont pas saisies dans le CRM.
alter table public.clubs add column if not exists pairs_declares integer;
alter table public.clubs add column if not exists pairs_declares_le date;
comment on column public.clubs.pairs_declares is 'Nombre de pairs (animateur inclus) déclaré par le bureau national ; affiché tant que les fiches saisies sont moins nombreuses.';
