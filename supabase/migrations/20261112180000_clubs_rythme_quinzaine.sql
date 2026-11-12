-- v0.43.0 : rythme « toutes les deux semaines » (quinzaine) ancré sur une date de départ.
alter table public.clubs add column if not exists rythme_pas smallint check (rythme_pas in (1,2));
alter table public.clubs add column if not exists rythme_depart date;
comment on column public.clubs.rythme_pas is 'Avec rythme_rang = 0 : 1 = chaque semaine, 2 = toutes les deux semaines (quinzaine).';
comment on column public.clubs.rythme_depart is 'Date d''une réunion du rythme (ancre de la quinzaine).';
