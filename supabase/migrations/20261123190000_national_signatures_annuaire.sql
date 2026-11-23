-- v1.136 : un contrat sorti de « En attente de signature » au national est cherché dans l'annuaire national des
-- entreprises membres (fonction serveur national-signatures), 7 minutes après chaque passage horaire de national-suivi.
create or replace function public.cap_national_signatures_lancer() returns bigint
language plpgsql security definer set search_path = public as $fn$
begin
  -- Planificateur (aucune session) ou super admin seulement.
  if coalesce(current_setting('request.jwt.claims', true), '') <> '' and cap_role() is distinct from 'superadmin' then
    raise exception 'réservé';
  end if;
  return net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/national-signatures',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 90000);
end $fn$;

select cron.schedule('national-signatures', '12 6-20 * * *', $$select public.cap_national_signatures_lancer()$$);
