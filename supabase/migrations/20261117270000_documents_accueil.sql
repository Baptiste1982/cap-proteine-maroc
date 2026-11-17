-- v1.10.1 : fenêtre d'accueil de la personne qui gère les documents du réseau (Rita, bureau national).
-- Affichée à sa première connexion (espace documents et CRM), puis plus jamais, sur aucun appareil.
alter table public.profiles add column if not exists docs_accueil_vu_le timestamptz;
comment on column public.profiles.docs_accueil_vu_le is 'Date à laquelle ce compte a fermé la fenêtre d''accueil des documents du réseau.';

-- Ce qu'il faut pour décider d'afficher l'accueil : rôle, prénom, gestion des documents, déjà vu ou non.
create or replace function public.cap_docs_profil() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('role', p.role, 'nom', p.nom, 'gere', public.cap_gere_documents(),
    'gere_seul', p.gere_documents and p.role not in ('superadmin','directeur_national'), 'vu', p.docs_accueil_vu_le is not null)
  from profiles p where p.id = auth.uid();
$$;
grant execute on function public.cap_docs_profil() to authenticated;

create or replace function public.cap_docs_accueil_vu() returns void
language sql security definer set search_path = public as $$
  update profiles set docs_accueil_vu_le = now() where id = auth.uid();
$$;
grant execute on function public.cap_docs_accueil_vu() to authenticated;
