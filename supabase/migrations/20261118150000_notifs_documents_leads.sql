-- v1.45.0 — Notifications au téléphone : une pièce arrive dans « Mes documents » (au membre), un contact est
-- confié (à l'animateur). Même patron que les autres : déclencheur → pg_net → edge notif-membre, qui réserve
-- la ligne (notifie_le) avant d'envoyer. Une facture ne part qu'une fois le paiement coché.
alter table public.membre_documents add column if not exists notifie_le timestamptz;
alter table public.leads add column if not exists attribue_notifie_le timestamptz;

create or replace trigger membre_documents_notifier after insert or update of visible_membre on public.membre_documents
  for each row when (new.visible_membre and new.notifie_le is null and new.membre_id is not null)
  execute function public.membres_notifier('doc');

-- Le paiement vient d'être coché : les factures déjà déposées et pas encore annoncées partent.
create or replace function public.membres_paiement_docs() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare d record;
begin
  for d in select id from membre_documents where membre_id = new.id and nature = 'facture' and visible_membre and notifie_le is null loop
    perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-membre',
      body := jsonb_build_object('type', 'doc', 'id', d.id), headers := jsonb_build_object('Content-Type', 'application/json'));
  end loop;
  return new;
end $$;
create or replace trigger membres_paiement_docs after update of paiement on public.membres
  for each row when (new.paiement and old.paiement is distinct from new.paiement)
  execute function public.membres_paiement_docs();

create or replace trigger leads_attribue_notifier after update of attribue_a on public.leads
  for each row when (new.attribue_a is not null and new.attribue_a is distinct from old.attribue_a)
  execute function public.membres_notifier('lead');
