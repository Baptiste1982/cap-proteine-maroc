-- Vérification hebdomadaire des membres du CRM national (lundi 7 h 30 au Maroc) : la fonction serveur national-annuaire
-- (action verifier) ajoute les nouveaux membres et signale les écarts ; rapport dans reglages.national_verif.
create or replace function public.cap_national_annuaire_lancer() returns bigint
language plpgsql security definer set search_path = public as $fn$
begin
  -- Planificateur (aucune session) ou super admin seulement.
  if coalesce(current_setting('request.jwt.claims', true), '') <> '' and cap_role() is distinct from 'superadmin' then
    raise exception 'réservé';
  end if;
  return net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/national-annuaire',
    body := '{"action":"verifier"}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 90000);
end $fn$;

select cron.schedule('national-annuaire', '30 6 * * 1', $$select public.cap_national_annuaire_lancer()$$);
