-- v0.30.0 : lien Google Maps ou Waze d'un lieu (collé tel quel ; la position GPS en est extraite quand c'est possible).
alter table public.lieux add column if not exists lien_carte text;
