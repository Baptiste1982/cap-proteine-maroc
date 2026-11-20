-- v1.127 : événements du réseau qui ne sont pas la réunion d'un groupe (interclub, séminaire…).
create table if not exists public.evenements_reseau (
  id uuid primary key default gen_random_uuid(),
  titre text not null,
  genre text not null default 'Interclub',
  date date not null,
  heure text,
  lieu text,
  note text,
  cree_par uuid default auth.uid(),
  cree_le timestamptz not null default now()
);
alter table public.evenements_reseau enable row level security;
create policy evenements_lire on public.evenements_reseau for select using (public.cap_est_equipe());
create policy evenements_ajouter on public.evenements_reseau for insert with check (public.cap_gere_reseau());
create policy evenements_modifier on public.evenements_reseau for update using (public.cap_gere_reseau()) with check (public.cap_gere_reseau());
create policy evenements_retirer on public.evenements_reseau for delete using (public.cap_gere_reseau());
-- Les membres connectés les lisent aussi (réunions du réseau de l'espace membre).
create policy evenements_lire_membres on public.evenements_reseau for select using (public.cap_membre_id() is not null);
