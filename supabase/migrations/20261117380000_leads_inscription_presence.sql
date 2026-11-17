-- v1.19.0 : rapprochement d'un lead avec une inscription à la réunion, et présence (appliquée le 17/11/2026, nom leads_inscription_presence)
alter table public.leads add column if not exists inscrit_le timestamptz, add column if not exists invite_id uuid, add column if not exists venu boolean, add column if not exists venu_note_le timestamptz;
comment on column public.leads.invite_id is 'Invité de la réunion (table invites) rapproché du lead : inscription par le lien national.';
comment on column public.leads.venu is 'Présence à la réunion de l''invitation : vrai, faux, ou vide si pas encore noté.';
