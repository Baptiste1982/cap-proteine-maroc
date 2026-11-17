-- v1.22.0 (appliquées le 17/11/2026 : profiles_choix_region, invitation_nationale_par_animateur)
alter table public.profiles add column if not exists choix_region boolean not null default false;
comment on column public.profiles.choix_region is 'Peut choisir la région affichée en vue régionale (en plus du superadmin et du directeur national).';
-- L'animateur d'un groupe (et la direction) demande l'invitation du CRM national pour SA réunion :
-- appel asynchrone (pg_net) de national-suivi action invitation_reunion avec le jeton du coffre ; résultat dans reunions.national.
create or replace function public.cap_invitation_nationale(p_reunion uuid)
returns bigint language plpgsql security definer set search_path=public as $$
declare c uuid; s text;
begin
  select club_id, statut into c, s from reunions where id = p_reunion;
  if c is null then raise exception 'Réunion introuvable'; end if;
  if s = 'annulee' then raise exception 'Réunion annulée'; end if;
  if cap_role() = 'visiteur' or not cap_can_edit_club(c) then raise exception 'Ce groupe n''est pas le tien'; end if;
  return net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/national-suivi',
    body := jsonb_build_object('action','invitation_reunion','reunion_id',p_reunion),
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 90000);
end $$;
grant execute on function public.cap_invitation_nationale(uuid) to authenticated;
