-- v1.18.0 : leads nationaux (prospects à inviter). Référencés dans le CRM (Adhésions → Leads), invitation WhatsApp,
-- suivi « contacté ». Lecture et écriture : l'équipe hors lecture seule. Pas de suppression (on change l'état).
create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  nom text not null,
  specialite text, telephone text, source text, ville text, linkedin text, commentaire text,
  statut text not null default 'a_contacter' check (statut in ('a_contacter','message_envoye','contacte','inscrit','pas_interesse')),
  a_rappeler boolean not null default false,
  message_le timestamptz, message_par_nom text,
  contacte_le timestamptz, contacte_par uuid, contacte_par_nom text,
  reunion_id uuid references public.reunions(id) on delete set null,
  notes text,
  origine text not null default 'national'
);
alter table public.leads enable row level security;
create policy leads_lire on public.leads for select using (public.cap_est_equipe() and public.cap_role() <> 'visiteur');
create policy leads_ajouter on public.leads for insert with check (public.cap_est_equipe() and public.cap_role() <> 'visiteur');
create policy leads_modifier on public.leads for update using (public.cap_est_equipe() and public.cap_role() <> 'visiteur');
comment on table public.leads is 'Leads nationaux : prospects à inviter aux réunions (liste CAP Maroc), suivi des contacts.';

-- (appliqué à part : leads_feuille_sync, reglages_partages)
alter table public.leads add column if not exists feuille text, add column if not exists sheet_le timestamptz, add column if not exists sheet_err text;
create table if not exists public.reglages (cle text primary key, valeur text, maj_le timestamptz not null default now());
alter table public.reglages enable row level security;
create policy reglages_lire on public.reglages for select using (public.cap_est_equipe());
create policy reglages_ajouter on public.reglages for insert with check (public.cap_role() = 'superadmin');
create policy reglages_modifier on public.reglages for update using (public.cap_role() = 'superadmin');
