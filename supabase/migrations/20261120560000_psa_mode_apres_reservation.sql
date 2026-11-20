-- v1.135 : le mode d'un PSA (en ligne, sur place, téléphone) se change après la réservation, des deux côtés,
-- et l'autre personne est prévenue. Par le lien (animateur sans compte) ou depuis le CRM (celui qui mène, ou celui qui a réservé).
create or replace function public.cap_psa_mode_lien(p_jeton uuid, p_id uuid, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare l record; c record;
begin
  select * into l from psa_liens where jeton = p_jeton and actif;
  if l.jeton is null then raise exception 'Lien inconnu'; end if;
  if p_mode not in ('visio','telephone','presentiel') then raise exception 'Mode inconnu'; end if;
  select * into c from psa_creneaux where id = p_id and directeur_id = l.directeur_id for update;
  if c.id is null or c.reserve_lien is distinct from p_jeton then raise exception 'Ce n''est pas ta réservation'; end if;
  if c.debut < now() then raise exception 'Ce créneau est passé'; end if;
  if c.mode is not distinct from p_mode then return jsonb_build_object('ok', true); end if;
  update psa_creneaux set mode = p_mode where id = p_id;
  perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
    body := jsonb_build_object('pour', jsonb_build_array(c.directeur_id), 'titre', '📅 PSA : mode changé', 'corps',
      l.nom || ' · ' || to_char(c.debut at time zone 'Africa/Casablanca', 'DD/MM à HH24"h"MI') || ' · ' || case p_mode when 'visio' then 'en ligne' when 'telephone' then 'par téléphone' else 'sur place' end,
      'url', '/?psa=1', 'tag', 'psa-' || p_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-suivi-jeton', (select decrypted_secret from vault.decrypted_secrets where name = 'national_suivi_jeton')),
    timeout_milliseconds := 20000);
  return jsonb_build_object('ok', true);
end $fn$;

create or replace function public.cap_psa_mode(p_id uuid, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare moi uuid := auth.uid(); c record; mon_nom text; cible uuid; a_compte boolean := false;
begin
  if moi is null or cap_voir() is not null or not cap_est_equipe() then raise exception 'réservé'; end if;
  if p_mode not in ('visio','telephone','presentiel') then raise exception 'Mode inconnu'; end if;
  select * into c from psa_creneaux where id = p_id for update;
  if c.id is null then raise exception 'Créneau introuvable'; end if;
  if c.reserve_par is null and c.reserve_lien is null then raise exception 'Ce créneau n''est pas réservé'; end if;
  if not (c.directeur_id = moi or c.reserve_par = moi or coalesce(cap_role(), '') = 'superadmin') then raise exception 'Ce n''est pas ton PSA'; end if;
  if c.mode is not distinct from p_mode then return jsonb_build_object('ok', true, 'inchange', true); end if;
  update psa_creneaux set mode = p_mode where id = p_id;
  select nom into mon_nom from profiles where id = moi;
  cible := case when c.reserve_par = moi then c.directeur_id else c.reserve_par end;
  a_compte := cible is not null;
  if a_compte then
    perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
      body := jsonb_build_object('pour', jsonb_build_array(cible), 'titre', '📅 PSA : mode changé', 'corps',
        coalesce(mon_nom, 'Ton PSA') || ' · ' || to_char(c.debut at time zone 'Africa/Casablanca', 'DD/MM à HH24"h"MI') || ' · ' || case p_mode when 'visio' then 'en ligne' when 'telephone' then 'par téléphone' else 'sur place' end,
        'url', '/?psa=1', 'tag', 'psa-' || p_id),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-suivi-jeton', (select decrypted_secret from vault.decrypted_secrets where name = 'national_suivi_jeton')),
      timeout_milliseconds := 20000);
  end if;
  return jsonb_build_object('ok', true, 'compte', a_compte);
end $fn$;
