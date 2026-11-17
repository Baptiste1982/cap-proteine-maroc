-- v1.6.0 : cycle des réunions d'un groupe en activité : business → conférence (intervenant extérieur) → visite d'entreprise → business.
-- Pas de DROP : le type (SI/RL, lu par le national) reste, le format s'ajoute à côté.
alter table public.reunions add column if not exists format text check (format is null or format in ('business','conference','visite'));
alter table public.reunions add column if not exists theme text check (theme is null or char_length(theme) <= 200);
comment on column public.reunions.format is 'Format d''une réunion de groupe en activité : business, conference (intervenant extérieur), visite (visite d''entreprise). Vide = SI/RL classique.';
comment on column public.reunions.theme is 'Intervenant et sujet d''une conférence, ou entreprise visitée.';
alter table public.clubs add column if not exists cycle boolean not null default false;
comment on column public.clubs.cycle is 'Le groupe suit le cycle business → conférence → visite → business.';
