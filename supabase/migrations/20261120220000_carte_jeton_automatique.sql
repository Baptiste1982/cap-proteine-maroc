-- v1.79.0 — la carte de visite existe dès la création de la fiche membre.
alter table public.membres alter column carte_jeton set default gen_random_uuid();
update public.membres set carte_jeton = gen_random_uuid() where carte_jeton is null;
