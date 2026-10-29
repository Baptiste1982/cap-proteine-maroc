-- Dossier de chaque membre : ses informations (entreprise, coordonnées) et ses documents
-- (formulaire d'adhésion, contrat du national, contrat signé, autres pièces).
-- Mêmes droits que les membres : lecture = qui voit le club, écriture = qui peut éditer le club.
-- Un document peut être rattaché à une adhésion avant que le membre existe (contrat généré avant
-- l'intégration) : il rejoint le dossier du membre à l'intégration.

alter table public.membres add column if not exists infos jsonb;
comment on column public.membres.infos is 'Informations du membre (mêmes clés que adhesions.data : ent_*, m_*, metier…), saisies à la main ou reprises du formulaire.';

create table if not exists public.membre_documents (
  id uuid primary key default gen_random_uuid(),
  membre_id uuid references public.membres(id) on delete cascade,
  adhesion_id uuid references public.adhesions(id) on delete set null,
  type text not null default 'autre' check (type in ('formulaire','contrat','contrat_signe','autre')),
  nom text not null,
  chemin text not null unique,
  source text,
  cree_le timestamptz not null default now(),
  cree_par uuid default auth.uid(),
  check (membre_id is not null or adhesion_id is not null)
);
create index if not exists membre_documents_membre on public.membre_documents(membre_id);
create index if not exists membre_documents_adhesion on public.membre_documents(adhesion_id);
alter table public.membre_documents enable row level security;

create or replace function public.cap_peut_voir_document(p_membre uuid, p_adhesion uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select cap_can_see_club(m.club_id) from membres m where m.id = p_membre), false)
      or coalesce((select cap_peut_voir_adhesion(a.ref, a.membre_id) from adhesions a where a.id = p_adhesion), false)
$$;
create or replace function public.cap_peut_ecrire_document(p_membre uuid, p_adhesion uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(cap_role(), 'visiteur') <> 'visiteur' and (
         coalesce((select cap_can_edit_club(m.club_id) from membres m where m.id = p_membre), false)
      or coalesce((select cap_peut_voir_adhesion(a.ref, a.membre_id) from adhesions a where a.id = p_adhesion), false))
$$;

create policy membre_documents_select on public.membre_documents for select to authenticated
  using (cap_peut_voir_document(membre_id, adhesion_id));
create policy membre_documents_insert on public.membre_documents for insert to authenticated
  with check (cap_peut_ecrire_document(membre_id, adhesion_id));
create policy membre_documents_update on public.membre_documents for update to authenticated
  using (cap_peut_ecrire_document(membre_id, adhesion_id)) with check (cap_peut_ecrire_document(membre_id, adhesion_id));
create policy membre_documents_delete on public.membre_documents for delete to authenticated
  using (cap_peut_ecrire_document(membre_id, adhesion_id));

-- Fichiers : bucket privé « membres », chemin <membre_id ou adh-<adhesion_id>>/<fichier>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('membres', 'membres', false, 20971520, array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy membres_docs_lire on storage.objects for select to authenticated
  using (bucket_id = 'membres' and exists (select 1 from public.membre_documents d where d.chemin = objects.name));
create policy membres_docs_deposer on storage.objects for insert to authenticated
  with check (bucket_id = 'membres' and coalesce(public.cap_role(), 'visiteur') <> 'visiteur');
create policy membres_docs_supprimer on storage.objects for delete to authenticated
  using (bucket_id = 'membres' and exists (select 1 from public.membre_documents d
         where d.chemin = objects.name and public.cap_peut_ecrire_document(d.membre_id, d.adhesion_id)));
