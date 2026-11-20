-- v1.105 : le compte commun du CRM national (celui du super admin) ne sert plus aux autres comptes.
-- Une invitation créée par quelqu'un d'autre part avec le compte de l'animateur de la réunion s'il est branché, sinon avec le sien.
-- Sans compte branché, la demande est refusée tout de suite, avec un message clair.
create or replace function public.cap_invitation_nationale(p_reunion uuid) returns bigint
language plpgsql security definer set search_path = public as $function$
declare c uuid; s text; a uuid; ca uuid; moi uuid := cap_animateur_id(); sup boolean := coalesce(cap_role(), '') = 'superadmin';
begin
  select club_id, statut, animateur_id into c, s, a from reunions where id = p_reunion;
  if c is null then raise exception 'Réunion introuvable'; end if;
  if s = 'annulee' then raise exception 'Réunion annulée'; end if;
  if cap_role() = 'visiteur' or not cap_can_edit_club(c) then raise exception 'Ce groupe n''est pas le tien'; end if;
  select animateur_id into ca from clubs where id = c;
  if not sup and not exists (select 1 from national_comptes n where n.actif and n.identifiant <> '' and n.animateur_id in (a, ca, moi)) then
    raise exception 'Branche d''abord ton compte du CRM national : sans lui, rien ne part au national.';
  end if;
  return net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/national-suivi',
    body := case when sup then jsonb_build_object('action','invitation_reunion','reunion_id',p_reunion)
                 else jsonb_build_object('action','invitation_reunion','reunion_id',p_reunion,'par_anim',coalesce(moi::text, 'sans-fiche')) end,
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 90000);
end $function$;
