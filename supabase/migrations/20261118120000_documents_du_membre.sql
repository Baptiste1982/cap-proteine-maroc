-- v1.44.0 — Documents remis à chaque membre dans son espace (demande JB du 18/11/2026) : sa facture une fois le
-- règlement fait, et les pièces qu'on lui donne (attestation de régularité fiscale, reçu…) pour son comptable.
-- Les fichiers restent dans le bucket privé « membres ». Un membre ne lit que SES documents partagés ;
-- une facture ne lui apparaît que lorsque son paiement est coché.
alter table public.membre_documents
  add column if not exists nature text check (nature is null or nature in ('facture','recu','attestation','autre')),
  add column if not exists visible_membre boolean not null default false,
  add column if not exists partage_le timestamptz;
comment on column public.membre_documents.nature is 'Pièce remise au membre : facture, recu, attestation, autre. Vide = pièce interne du dossier.';
comment on column public.membre_documents.visible_membre is 'Le membre la voit dans son espace (une facture seulement une fois son paiement coché).';

create or replace function public.cap_doc_du_membre(p_membre uuid, p_visible boolean, p_nature text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce(p_visible, false) and p_membre is not null and p_membre = cap_membre_id()
     and (coalesce(p_nature, '') <> 'facture' or exists (select 1 from membres m where m.id = p_membre and m.paiement))
$$;

alter policy membre_documents_select on public.membre_documents
  using (cap_peut_voir_document(membre_id, adhesion_id) or cap_doc_du_membre(membre_id, visible_membre, nature));
