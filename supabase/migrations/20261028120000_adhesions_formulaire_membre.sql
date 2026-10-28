-- ═══════════════════════════════════════════════════════════════════════════
-- Adhésions membres reçues par le lien public (page adhesion.html)
-- Projet Supabase : cap-proteine-maroc (xsppsqjigdgaybmowzaq) — PAS la base ADM.
--
-- Principe de sécurité : la page publique n'a que la clé publishable. Elle peut
--   ① DÉPOSER un PDF dans le bucket privé `adhesions` (insertion seule, jamais relire),
--   ② APPELER `soumettre_adhesion` (fonction serveur, insertion seule).
-- Elle ne peut RIEN lire : ni la table, ni les PDF déposés par les autres.
-- Le CRM (utilisateurs connectés) lit, traite et intègre les adhésions.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.adhesions (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  statut        text not null default 'recue'
                check (statut in ('recue', 'traitee', 'integree', 'rejetee')),
  ref           text,                 -- paramètre ?ref= du lien envoyé (club, animateur…)
  data          jsonb not null,       -- toutes les réponses, telles que saisies
  pdf_path      text,                 -- chemin dans le bucket `adhesions`
  -- colonnes dérivées pour lister/chercher sans ouvrir le jsonb
  entreprise    text generated always as (data->>'ent_nom') stored,
  membre_nom    text generated always as (trim(coalesce(data->>'m_prenom','') || ' ' || coalesce(data->>'m_nom',''))) stored,
  email         text generated always as (data->>'m_email') stored,
  telephone     text generated always as (data->>'m_tel') stored,
  metier        text generated always as (data->>'metier') stored,
  membre_id     uuid references public.membres(id) on delete set null, -- membre créé à l'intégration
  traitee_par   uuid references auth.users(id),
  traitee_le    timestamptz,
  notes         text
);
create index if not exists adhesions_created_idx on public.adhesions (created_at desc);
create index if not exists adhesions_statut_idx  on public.adhesions (statut);

alter table public.adhesions enable row level security;

-- Lecture / traitement : comptes connectés du CRM. À resserrer par zone si besoin
-- (patron des helpers cap_* existants), comme les autres tables du CRM.
drop policy if exists adhesions_select_auth on public.adhesions;
create policy adhesions_select_auth on public.adhesions for select to authenticated using (true);
drop policy if exists adhesions_update_auth on public.adhesions;
create policy adhesions_update_auth on public.adhesions for update to authenticated using (true) with check (true);
-- Aucune policy pour anon : la page publique passe UNIQUEMENT par la fonction ci-dessous.

-- ─── Fonction d'envoi appelée par la page publique ───────────────────────
create or replace function public.soumettre_adhesion(
  p_id uuid, p_data jsonb, p_pdf_path text default null, p_ref text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  if p_data is null or jsonb_typeof(p_data) <> 'object' then raise exception 'données manquantes'; end if;
  if pg_column_size(p_data) > 20000 then raise exception 'données trop volumineuses'; end if;
  if coalesce(p_data->>'m_nom','') = '' or coalesce(p_data->>'m_email','') = '' or coalesce(p_data->>'ent_nom','') = '' then
    raise exception 'champs obligatoires manquants';
  end if;
  -- le PDF doit porter l'id de l'adhésion (évite de rattacher le fichier d'un autre)
  if p_pdf_path is not null and p_pdf_path <> p_id::text || '.pdf' then raise exception 'chemin de PDF invalide'; end if;
  -- anti-rafale simple : 20 envois max par heure, tous liens confondus
  if (select count(*) from public.adhesions where created_at > now() - interval '1 hour') >= 20 then
    raise exception 'trop d''envois, réessayez plus tard';
  end if;
  insert into public.adhesions (id, data, pdf_path, ref)
  values (p_id, p_data, p_pdf_path, left(p_ref, 80));
  return p_id;
end $$;

revoke all on function public.soumettre_adhesion(uuid, jsonb, text, text) from public;
grant execute on function public.soumettre_adhesion(uuid, jsonb, text, text) to anon, authenticated;

-- ─── Stockage des PDF remplis : bucket PRIVÉ ─────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('adhesions', 'adhesions', false, 2097152, array['application/pdf'])
on conflict (id) do nothing;

-- Dépôt seul pour la page publique (nom de fichier = un uuid + .pdf), aucune relecture.
drop policy if exists adhesions_pdf_insert_anon on storage.objects;
create policy adhesions_pdf_insert_anon on storage.objects for insert to anon
  with check (bucket_id = 'adhesions'
              and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$');
-- Le CRM relit les PDF (lien signé depuis la fiche d'adhésion).
drop policy if exists adhesions_pdf_select_auth on storage.objects;
create policy adhesions_pdf_select_auth on storage.objects for select to authenticated
  using (bucket_id = 'adhesions');
