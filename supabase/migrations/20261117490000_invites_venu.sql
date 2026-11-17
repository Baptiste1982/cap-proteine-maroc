-- v1.34.0 — Suivi des invités après la réunion : présence notée invité par invité (vrai = venu, faux = absent, vide = pas noté).
-- Le message de remerciement part aux invités venus ; sa date reste dans invites.suivi_le. Droits inchangés (cap_can_edit_club).
alter table public.invites add column if not exists venu boolean;
comment on column public.invites.venu is 'Présence de l''invité à la réunion : vrai = venu, faux = absent, vide = pas encore noté';
