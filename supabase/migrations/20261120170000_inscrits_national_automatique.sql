-- v1.72.0 — les inscrits du lien national arrivent seuls : passage toutes les 10 minutes (8 h – 22 h, heure du Maroc),
-- seulement quand une réunion à venir a une invitation au national. Le passage horaire complet (annuaire, signatures) reste.
create or replace function public.cap_national_inscrits_lancer()
 returns bigint language plpgsql security definer set search_path to 'public'
as $function$
declare v_dernier timestamptz;
begin
  -- appelée par le planificateur (aucune session) ou par le super admin ; jamais par un autre compte ni sans connexion
  if coalesce(current_setting('request.jwt.claims', true), '') <> '' and coalesce(cap_role(), '') <> 'superadmin' then
    raise exception 'réservé au super admin';
  end if;
  if not exists (select 1 from reunions r where r.date >= current_date and r.statut <> 'annulee' and nullif(r.national->>'invitation_id', '') is not null) then
    return null;
  end if;
  select nullif(valeur, '')::timestamptz into v_dernier from reglages where cle = 'inscrits_lance_le';
  if v_dernier is not null and v_dernier > now() - interval '4 minutes' then return null; end if;
  insert into reglages (cle, valeur) values ('inscrits_lance_le', now()::text)
    on conflict (cle) do update set valeur = excluded.valeur;
  return net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/national-suivi',
    body := '{"action":"inscrits"}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 90000);
end $function$;

select cron.schedule('national-inscrits', '2-59/10 7-20 * * *', 'select public.cap_national_inscrits_lancer()');
