-- v0.44.0 : invitation du CRM national rattachée à une réunion.
-- national = { invitation_id, lien, qr, date, heure, lieu, modele, cree_le, maj_le } (écrit par la fonction national-suivi).
alter table public.reunions add column if not exists national jsonb;
comment on column public.reunions.national is 'Invitation créée au CRM national pour cette réunion (n°, lien d''inscription, QR, date et heure au moment de l''envoi).';
