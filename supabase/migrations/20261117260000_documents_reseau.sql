-- v1.10.0 : les documents du réseau (demande JB du 17/11/2026).
-- Rita (bureau national) y dépose les documents dont les groupes ont besoin (PDF, Excel, Word, présentations, images…),
-- sans passer par nous. Chaque document se partage par un lien, et peut être montré aux animateurs dans le CRM
-- et aux membres dans leur espace.
-- Gérer = superadmin, directeur_national, ou un compte d'équipe qui porte profiles.gere_documents.
-- Fichiers dans le bucket public « reseau », sous un chemin aléatoire : seul qui a le lien y accède.

alter table public.profiles add column if not exists gere_documents boolean not null default false;
comment on column public.profiles.gere_documents is 'Ce compte gère les documents du réseau (dépôt, modification, partage, retrait).';

create or replace function public.cap_gere_documents() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p where p.id = auth.uid()
    and (p.role in ('superadmin','directeur_national') or p.gere_documents));
$$;
grant execute on function public.cap_gere_documents() to authenticated;

create table if not exists public.documents_reseau (
  id uuid primary key default gen_random_uuid(),
  titre text not null check (char_length(titre) between 1 and 200),
  description text check (description is null or char_length(description) <= 2000),
  categorie text not null default 'Autres',
  chemin text not null unique,
  nom_fichier text not null,
  type_mime text,
  taille bigint,
  lien_public boolean not null default true,
  visible_animateurs boolean not null default true,
  visible_membres boolean not null default false,
  epingle boolean not null default false,
  archive boolean not null default false,
  vues integer not null default 0,
  cree_par uuid references auth.users(id) on delete set null,
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now()
);
comment on table public.documents_reseau is 'Documents du réseau déposés par le bureau national : visibles par les animateurs (CRM), les membres (espace membre) et partageables par lien.';
alter table public.documents_reseau enable row level security;

create policy documents_reseau_lire on public.documents_reseau for select to authenticated
  using (
    public.cap_gere_documents()
    or (not archive and visible_animateurs and public.cap_est_equipe())
    or (not archive and visible_membres and public.cap_membre_id() is not null)
  );
create policy documents_reseau_ajouter on public.documents_reseau for insert to authenticated
  with check (public.cap_gere_documents());
create policy documents_reseau_modifier on public.documents_reseau for update to authenticated
  using (public.cap_gere_documents()) with check (public.cap_gere_documents());
create policy documents_reseau_retirer on public.documents_reseau for delete to authenticated
  using (public.cap_gere_documents());

-- Lien partagé : la page doc.html lit la fiche d'un document par son identifiant, sans connexion,
-- seulement s'il est partageable par lien et pas archivé. Chaque ouverture est comptée.
create or replace function public.cap_document_lien(p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare d documents_reseau%rowtype;
begin
  select * into d from documents_reseau where id = p_id and lien_public and not archive;
  if not found then return null; end if;
  update documents_reseau set vues = vues + 1 where id = p_id;
  return json_build_object('id', d.id, 'titre', d.titre, 'description', d.description, 'categorie', d.categorie,
    'chemin', d.chemin, 'nom_fichier', d.nom_fichier, 'type_mime', d.type_mime, 'taille', d.taille, 'maj_le', d.maj_le);
end $$;
grant execute on function public.cap_document_lien(uuid) to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('reseau', 'reseau', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800;

create policy "reseau lecture" on storage.objects for select using (bucket_id = 'reseau');
create policy "reseau ajout" on storage.objects for insert to authenticated
  with check (bucket_id = 'reseau' and public.cap_gere_documents());
create policy "reseau maj" on storage.objects for update to authenticated
  using (bucket_id = 'reseau' and public.cap_gere_documents());
create policy "reseau retrait" on storage.objects for delete to authenticated
  using (bucket_id = 'reseau' and public.cap_gere_documents());
