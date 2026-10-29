-- Espace « Mes réunions » des animateurs (v0.22.0).
-- Chaque club retient son lieu, son jour et son heure habituels : « Planifier la suivante » pré-remplit tout.
--   rythme_jour  : 1 = lundi … 7 = dimanche
--   rythme_rang  : 0 = chaque semaine, 1 à 4 = 1er … 4e du mois, -1 = dernier du mois
-- Chaque réunion peut porter un compte rendu (texte structuré en jsonb, le canevas évoluera sans migration).
-- Droits : ceux déjà en place (clubs_update / reunions_update = cap_can_edit_club).

alter table public.clubs add column if not exists lieu_habituel_id uuid references public.lieux(id) on delete set null;
alter table public.clubs add column if not exists rythme_jour smallint check (rythme_jour between 1 and 7);
alter table public.clubs add column if not exists rythme_rang smallint check (rythme_rang between -1 and 4);
alter table public.clubs add column if not exists heure_habituelle text;

alter table public.reunions add column if not exists compte_rendu jsonb;
alter table public.reunions add column if not exists cr_le timestamptz;
alter table public.reunions add column if not exists cr_par uuid;

comment on column public.clubs.rythme_rang is '0 = chaque semaine, 1..4 = Nième du mois, -1 = dernier du mois';
comment on column public.reunions.compte_rendu is 'Compte rendu de la réunion : {deroule, decisions, suivi, ...} — canevas à aligner sur le modèle national';
