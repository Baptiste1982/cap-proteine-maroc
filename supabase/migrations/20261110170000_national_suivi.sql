-- Suivi au CRM national (appliqué le 10/11/2026 en deux migrations : national_suivi_jeton, national_suivi_programme).
do $$ begin
  if not exists (select 1 from vault.secrets where name='national_suivi_jeton') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(24),'hex'),'national_suivi_jeton','Jeton de la fonction national-suivi');
  end if;
end $$;
create or replace function public.cap_national_jeton_ok(p text) returns boolean
language sql security definer set search_path=public as $$
  select exists(select 1 from vault.decrypted_secrets where name='national_suivi_jeton' and decrypted_secret=p and p is not null and length(p)>20)
$$;
revoke all on function public.cap_national_jeton_ok(text) from public, anon, authenticated;
grant execute on function public.cap_national_jeton_ok(text) to service_role;
create extension if not exists pg_cron;
create or replace function public.cap_national_suivi_lancer() returns bigint
language sql security definer set search_path=public as $$
  select net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/national-suivi',
    body := '{"action":"verifier"}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 90000)
$$;
revoke all on function public.cap_national_suivi_lancer() from public, anon, authenticated;
select cron.schedule('national-suivi', '5 7-20 * * *', 'select public.cap_national_suivi_lancer()');
