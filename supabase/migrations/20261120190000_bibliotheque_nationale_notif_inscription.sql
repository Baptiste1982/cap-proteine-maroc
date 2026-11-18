-- v1.76.0
-- 1. Notification à l'animateur quand un membre d'un AUTRE groupe répond « Je viens » à sa réunion.
alter table public.reunion_reponses add column if not exists notifie_le timestamptz;
create or replace function public.inscription_notifier() returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
  perform net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-inscription',
    body := jsonb_build_object('id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json'));
  return new;
end $function$;
create or replace trigger reunion_reponses_notifier after insert or update of reponse on public.reunion_reponses
  for each row when (new.reponse = 'oui') execute function public.inscription_notifier();

-- 2. Bibliothèque nationale : un directeur de région lit tous les documents non archivés ;
--    `source` évite d'importer deux fois le même document (site, CRM national).
alter table public.documents_reseau add column if not exists source text;
create unique index if not exists documents_reseau_source_uq on public.documents_reseau (source) where source is not null;
alter policy documents_reseau_lire on public.documents_reseau using (
  cap_gere_documents()
  or ((not archive) and coalesce(cap_role(), '') = 'directeur')
  or ((not archive) and visible_animateurs and cap_est_equipe())
  or ((not archive) and visible_membres and (cap_membre_id() is not null))
  or ((not archive) and cap_doc_acces_ok(id)));

-- 3. Trame de présentation : images dans un bucket privé, lues par l'équipe connectée (liens signés).
insert into storage.buckets (id, name, public, file_size_limit)
  values ('presentations', 'presentations', false, 5242880) on conflict (id) do nothing;
create policy presentations_lire on storage.objects for select to authenticated
  using (bucket_id = 'presentations' and public.cap_est_equipe());
