-- v1.111 : planning des PSA par lien. Le directeur envoie à un animateur (qui n'utilise pas encore le CRM) un lien
-- personnel : il voit les créneaux du directeur, en réserve un, et le créneau est verrouillé pour tous à l'instant.
create table if not exists public.psa_liens (
  jeton        uuid primary key default gen_random_uuid(),
  directeur_id uuid not null,
  animateur_id uuid,
  nom          text not null,
  actif        boolean not null default true,
  cree_le      timestamptz not null default now(),
  vu_le        timestamptz
);
create unique index if not exists psa_liens_dir_anim on public.psa_liens (directeur_id, animateur_id) where animateur_id is not null;
alter table public.psa_liens enable row level security;
create policy psa_liens_lire on public.psa_liens for select to authenticated
  using (directeur_id = cap_uid() or coalesce(cap_role(), '') = 'superadmin');

alter table public.psa_creneaux add column if not exists reserve_lien uuid;

-- Le directeur crée (ou retrouve) le lien d'un animateur.
create or replace function public.cap_psa_lien(p_anim uuid, p_nom text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n text; j uuid;
begin
  if me is null or not cap_psa_gere() then raise exception 'Réservé au directeur de région'; end if;
  n := nullif(btrim(coalesce(p_nom, '')), '');
  if p_anim is not null then
    select nom into n from animateurs where id = p_anim;
    if n is null then raise exception 'Animateur introuvable'; end if;
    select jeton into j from psa_liens where directeur_id = me and animateur_id = p_anim;
    if j is not null then update psa_liens set actif = true, nom = n where jeton = j; end if;
  end if;
  if n is null then raise exception 'Indique un nom'; end if;
  if j is null then insert into psa_liens (directeur_id, animateur_id, nom) values (me, p_anim, left(n, 120)) returning jeton into j; end if;
  return jsonb_build_object('jeton', j, 'nom', n);
end $$;

-- Page publique : le planning vu par le porteur du lien. Aucune donnée sur les autres : un créneau pris est seulement « pris ».
create or replace function public.cap_psa_planning(p_jeton uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l record; pr uuid;
begin
  select * into l from psa_liens where jeton = p_jeton and actif;
  if l.jeton is null then return jsonb_build_object('ok', false); end if;
  update psa_liens set vu_le = now() where jeton = p_jeton and (vu_le is null or vu_le < now() - interval '1 minute');
  if l.animateur_id is not null then select id into pr from profiles where animateur_id = l.animateur_id limit 1; end if;
  return jsonb_build_object('ok', true, 'pour', l.nom,
    'directeur', (select coalesce(a.nom, p.nom) from profiles p left join animateurs a on a.id = p.animateur_id where p.id = l.directeur_id),
    'creneaux', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'debut', c.debut, 'duree', c.duree_min,
        'etat', case when c.reserve_lien = p_jeton or (pr is not null and c.reserve_par = pr) then 'moi'
                     when c.reserve_par is not null or c.reserve_lien is not null then 'pris' else 'libre' end,
        'lieu', c.lieu,
        'mode', case when c.reserve_lien = p_jeton or (pr is not null and c.reserve_par = pr) then c.mode end,
        'lien_visio', case when c.reserve_lien = p_jeton or (pr is not null and c.reserve_par = pr) then c.lien_visio end) order by c.debut)
      from psa_creneaux c where c.directeur_id = l.directeur_id and c.debut > now() and c.debut < now() + interval '62 days'), '[]'::jsonb));
end $$;

create or replace function public.cap_psa_reserver_lien(p_jeton uuid, p_id uuid, p_mode text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l record; c record; pr uuid;
begin
  select * into l from psa_liens where jeton = p_jeton and actif;
  if l.jeton is null then raise exception 'Lien inconnu'; end if;
  if p_mode not in ('visio','telephone','presentiel') then raise exception 'Mode inconnu'; end if;
  select * into c from psa_creneaux where id = p_id and directeur_id = l.directeur_id for update;
  if c.id is null then raise exception 'Créneau introuvable'; end if;
  if c.debut < now() then raise exception 'Ce créneau est passé'; end if;
  if c.reserve_par is not null or c.reserve_lien is not null then raise exception 'Créneau déjà pris'; end if;
  if l.animateur_id is not null then select id into pr from profiles where animateur_id = l.animateur_id limit 1; end if;
  if exists (select 1 from psa_creneaux x where x.directeur_id = l.directeur_id and x.debut > now() and x.id <> p_id
              and (x.reserve_lien = p_jeton or (pr is not null and x.reserve_par = pr))) then
    raise exception 'Tu as déjà un créneau réservé : annule-le d''abord';
  end if;
  update psa_creneaux set reserve_lien = p_jeton, reserve_par = pr, reserve_nom = l.nom, reserve_le = now(), mode = p_mode,
         note = nullif(left(btrim(coalesce(p_note, '')), 400), ''), notifie_le = null where id = p_id;
  perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
    body := jsonb_build_object('pour', jsonb_build_array(c.directeur_id), 'titre', '📅 PSA réservé', 'corps',
      l.nom || ' · ' || to_char(c.debut at time zone 'Africa/Casablanca', 'DD/MM à HH24"h"MI') || ' · ' || case p_mode when 'visio' then 'visio' when 'telephone' then 'téléphone' else 'présentiel' end || ' (par le lien)',
      'url', '/?psa=1', 'tag', 'psa-' || p_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-suivi-jeton', (select decrypted_secret from vault.decrypted_secrets where name = 'national_suivi_jeton')),
    timeout_milliseconds := 20000);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.cap_psa_annuler_lien(p_jeton uuid, p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l record; c record;
begin
  select * into l from psa_liens where jeton = p_jeton and actif;
  if l.jeton is null then raise exception 'Lien inconnu'; end if;
  select * into c from psa_creneaux where id = p_id and directeur_id = l.directeur_id for update;
  if c.id is null or c.reserve_lien is distinct from p_jeton then raise exception 'Ce n''est pas ta réservation'; end if;
  update psa_creneaux set reserve_lien = null, reserve_par = null, reserve_nom = null, reserve_le = null, mode = null, note = null where id = p_id;
  perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
    body := jsonb_build_object('pour', jsonb_build_array(c.directeur_id), 'titre', 'PSA annulé', 'corps',
      l.nom || ' · ' || to_char(c.debut at time zone 'Africa/Casablanca', 'DD/MM à HH24"h"MI'), 'url', '/?psa=1', 'tag', 'psa-' || p_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-suivi-jeton', (select decrypted_secret from vault.decrypted_secrets where name = 'national_suivi_jeton')),
    timeout_milliseconds := 20000);
  return jsonb_build_object('ok', true);
end $$;

-- Réservation depuis le CRM : un créneau pris par un lien est pris pour tous.
create or replace function public.cap_psa_reserver(p_id uuid, p_mode text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := cap_uid(); c record; n text; deja uuid;
begin
  if me is null or not cap_est_equipe() or cap_role()='visiteur' then raise exception 'Réservé à l''équipe'; end if;
  if p_mode not in ('visio','telephone','presentiel') then raise exception 'Mode inconnu'; end if;
  select * into c from psa_creneaux where id = p_id for update;
  if c.id is null then raise exception 'Créneau introuvable'; end if;
  if c.debut < now() then raise exception 'Ce créneau est passé'; end if;
  if (c.reserve_par is not null and c.reserve_par <> me) or (c.reserve_lien is not null and c.reserve_par is distinct from me) then raise exception 'Créneau déjà pris'; end if;
  if c.zone_id is distinct from (select zone_id from profiles where id = me) and cap_role() not in ('superadmin','directeur_national') and c.directeur_id <> me then raise exception 'Ce créneau n''est pas dans ta région'; end if;
  select id into deja from psa_creneaux where reserve_par = me and directeur_id = c.directeur_id and debut > now() and id <> p_id limit 1;
  if deja is not null then raise exception 'Tu as déjà un PSA réservé : annule-le d''abord'; end if;
  select nom into n from profiles where id = me;
  update psa_creneaux set reserve_par = me, reserve_nom = n, reserve_le = now(), mode = p_mode, note = nullif(btrim(coalesce(p_note,'')),''), notifie_le = null where id = p_id;
  perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
    body := jsonb_build_object('pour', jsonb_build_array(c.directeur_id), 'titre', '📅 PSA réservé', 'corps',
      coalesce(n,'Un animateur')||' · '||to_char(c.debut at time zone 'Africa/Casablanca','DD/MM à HH24"h"MI')||' · '||case p_mode when 'visio' then 'visio' when 'telephone' then 'téléphone' else 'présentiel' end, 'url', '/?psa=1', 'tag', 'psa-'||p_id),
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 20000);
  return jsonb_build_object('ok', true);
end $$;

-- Libérer un créneau (le directeur, ou celui qui l'a pris depuis le CRM) : la marque du lien part avec.
create or replace function public.cap_psa_annuler(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := cap_uid(); c record; n text;
begin
  select * into c from psa_creneaux where id = p_id for update;
  if c.id is null then raise exception 'Créneau introuvable'; end if;
  if c.reserve_par is distinct from me and c.directeur_id <> me and cap_role() <> 'superadmin' then raise exception 'Ce n''est pas ta réservation'; end if;
  n := c.reserve_nom;
  update psa_creneaux set reserve_par = null, reserve_lien = null, reserve_nom = null, reserve_le = null, mode = null, note = null where id = p_id;
  if c.reserve_par = me and c.directeur_id <> me then
    perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
      body := jsonb_build_object('pour', jsonb_build_array(c.directeur_id), 'titre', 'PSA annulé', 'corps', coalesce(n,'Un animateur')||' · '||to_char(c.debut at time zone 'Africa/Casablanca','DD/MM à HH24"h"MI'), 'url', '/?psa=1', 'tag', 'psa-'||p_id),
      headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
      timeout_milliseconds := 20000);
  end if;
  return jsonb_build_object('ok', true);
end $$;
