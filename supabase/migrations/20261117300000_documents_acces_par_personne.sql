-- v1.13.0 : donner / retirer l'accès à un document, personne par personne (demande JB 17/11/2026). Appliquée le 17/11.
create table if not exists public.documents_acces (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents_reseau(id) on delete cascade,
  user_id uuid not null,
  donne_par uuid,
  donne_le timestamptz not null default now(),
  retire_par uuid,
  retire_le timestamptz
);
create unique index if not exists documents_acces_actif on public.documents_acces(document_id, user_id) where retire_le is null;
create index if not exists documents_acces_user on public.documents_acces(user_id) where retire_le is null;
alter table public.documents_acces enable row level security;

create or replace function public.cap_doc_acces_ok(p_doc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from documents_acces a where a.document_id = p_doc and a.user_id = auth.uid() and a.retire_le is null)
$$;

create policy documents_acces_lire on public.documents_acces for select
  using (cap_gere_documents() or user_id = auth.uid());
create policy documents_acces_ajouter on public.documents_acces for insert
  with check (cap_gere_documents());
create policy documents_acces_modifier on public.documents_acces for update
  using (cap_gere_documents()) with check (cap_gere_documents());

alter policy documents_reseau_lire on public.documents_reseau
  using (cap_gere_documents()
    or ((not archive) and visible_animateurs and cap_est_equipe())
    or ((not archive) and visible_membres and (cap_membre_id() is not null))
    or ((not archive) and cap_doc_acces_ok(id)));

create or replace function public.cap_docs_personnes() returns table(user_id uuid, nom text, type text, detail text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not cap_gere_documents() then raise exception 'Réservé à la gestion des documents'; end if;
  return query
    select p.id, coalesce(nullif(p.nom,''), a.nom, 'Compte'), 'equipe'::text, p.role::text
      from profiles p left join animateurs a on a.id = p.animateur_id
    union all
    select m.user_id, m.nom, 'membre'::text, coalesce(c.nom,'')
      from membres m left join clubs c on c.id = m.club_id
     where m.user_id is not null and not exists(select 1 from profiles p2 where p2.id = m.user_id);
end $$;
grant execute on function public.cap_docs_personnes() to authenticated;
grant execute on function public.cap_doc_acces_ok(uuid) to authenticated;
