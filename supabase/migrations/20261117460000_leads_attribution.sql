-- v1.31.0 — Attribution des leads aux animateurs (demande JB du 17/11/2026).
-- La direction traite le lead, puis le confie à un animateur avec un mot ; l'animateur le retrouve dans sa boîte
-- « Contacts confiés », l'invite à sa réunion et note le suivi. Il ne lit et ne modifie que les leads qui lui sont confiés.
alter table public.leads
  add column if not exists attribue_a uuid references public.animateurs(id) on delete set null,
  add column if not exists attribue_par uuid,
  add column if not exists attribue_par_nom text,
  add column if not exists attribue_le timestamptz,
  add column if not exists attribue_note text,
  add column if not exists attribue_lu_le timestamptz;
create index if not exists leads_attribue_a_idx on public.leads (attribue_a) where attribue_a is not null;

alter policy leads_lire on public.leads using (
  coalesce(cap_role(), '') in ('superadmin', 'directeur_national', 'directeur')
  or (attribue_a is not null and attribue_a = cap_animateur_id()));
alter policy leads_modifier on public.leads
  using (coalesce(cap_role(), '') in ('superadmin', 'directeur_national', 'directeur')
         or (attribue_a is not null and attribue_a = cap_animateur_id()))
  with check (coalesce(cap_role(), '') in ('superadmin', 'directeur_national', 'directeur')
         or (attribue_a is not null and attribue_a = cap_animateur_id()));
