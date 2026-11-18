-- v1.78.0 — carte de visite du membre (lien + QR), kit de l'invité, rappels automatiques.

-- 1. Carte de visite : un lien non devinable par membre. Le membre le crée en ouvrant « Ma carte » ; il montre ce
--    qu'il partage déjà avec les autres membres (jamais RC, ICE, patente, capital).
alter table public.membres add column if not exists carte_jeton uuid;
create unique index if not exists membres_carte_jeton_uq on public.membres (carte_jeton) where carte_jeton is not null;

create or replace function public.cap_membre_carte() returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_mb uuid := cap_membre_id(); v_j uuid;
begin
  if v_mb is null then raise exception 'aucune fiche membre liée'; end if;
  select carte_jeton into v_j from membres where id = v_mb;
  if v_j is null then
    if cap_voir() is not null then return null; end if; -- aperçu « voir comme » : on ne crée rien
    v_j := gen_random_uuid();
    update membres set carte_jeton = v_j where id = v_mb;
  end if;
  return v_j;
end $function$;

create or replace function public.cap_carte_membre(p_jeton uuid) returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select jsonb_build_object('nom', m.nom, 'fonction', m.infos->>'m_fonction', 'metier', cap_metier_membre(m.infos, m.specialite),
    'entreprise', m.infos->>'ent_nom', 'groupe', c.nom, 'ville', coalesce(nullif(m.infos->>'ent_ville', ''), c.ville),
    'photo', m.photo_url, 'logo', m.logo_url,
    'presentation', coalesce(nullif(m.presentation, ''), nullif(m.infos->>'ent_activite', '')),
    'site', coalesce(nullif(m.site, ''), nullif(m.infos->>'ent_web', '')), 'linkedin', m.linkedin,
    'telephone', case when m.tel_visible then nullif(m.infos->>'m_tel', '') end,
    'email', case when m.tel_visible then nullif(m.infos->>'m_email', '') end,
    'club_id', m.club_id)
  from membres m left join clubs c on c.id = m.club_id
  where p_jeton is not null and m.carte_jeton = p_jeton
$function$;

-- 2. Kit de l'invité : ce qu'un invité a besoin de savoir sur la réunion, par le numéro de l'invitation nationale.
create or replace function public.cap_reunion_kit(p_inv text) returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select jsonb_build_object('date', r.date, 'heure', r.heure, 'type', r.type, 'format', r.format, 'theme', r.theme,
    'groupe', c.nom, 'ville', coalesce(l.ville, c.ville), 'lieu', l.nom, 'adresse', l.adresse, 'lien_carte', l.lien_carte,
    'lat', l.lat, 'lng', l.lng, 'animateur', a.nom, 'animateur_photo', a.photo, 'animateur_role', a.profil->>'role')
  from reunions r join clubs c on c.id = r.club_id left join lieux l on l.id = r.lieu_id
  left join animateurs a on a.id = coalesce(r.animateur_id, c.animateur_id)
  where p_inv ~ '^[0-9]{1,9}$' and r.national->>'invitation_id' = p_inv and r.statut <> 'annulee' and r.date >= current_date - 1
  limit 1
$function$;

-- 3. Rappels automatiques aux membres : réunion du lendemain, recommandation restée sans suite 7 jours.
alter table public.reunions add column if not exists rappel_membres_le timestamptz;
alter table public.recommandations add column if not exists relance_notif_le timestamptz;

create or replace function public.cap_rappels_lancer() returns bigint language plpgsql security definer set search_path to 'public'
as $function$
begin
  if coalesce(current_setting('request.jwt.claims', true), '') <> '' and coalesce(cap_role(), '') <> 'superadmin' then
    raise exception 'réservé au super admin';
  end if;
  return net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/rappels',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 60000);
end $function$;

select cron.schedule('rappels-membres', '0 16 * * *', 'select public.cap_rappels_lancer()');
