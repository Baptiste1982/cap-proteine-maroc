-- v1.147 : carnet du national. Les contacts que chaque personne a saisis dans l'Annuaire du CRM national sont
-- rapatriés chez nous avec SON compte branché (animateur_id vide = compte commun, celui du super admin).
-- Lecture : le super admin (tout) et la personne (son carnet). Aucune écriture directe : la fonction serveur seule.
create table if not exists public.carnet_national (
  id uuid primary key default gen_random_uuid(),
  animateur_id uuid references public.animateurs(id) on delete cascade,
  national_id bigint not null,
  civilite text, prenom text, nom text, fonction text, entreprise text,
  email text, tel1 text, tel2 text, adresse text, code_postal text, ville text, profils text,
  actif boolean not null default true,
  absent_le timestamptz,
  cree_le timestamptz not null default now(),
  vu_le timestamptz not null default now()
);
create unique index if not exists carnet_national_cle on public.carnet_national (coalesce(animateur_id::text, 'commun'), national_id);
alter table public.carnet_national enable row level security;
create policy carnet_national_lire on public.carnet_national for select
  using (coalesce(public.cap_role(), '') = 'superadmin' or (animateur_id is not null and animateur_id = public.cap_animateur_id()));

alter table public.national_comptes add column if not exists carnet_le timestamptz, add column if not exists carnet_nb integer;

-- État du carnet pour l'appelant : son dernier rapatriement (ou celui du compte commun pour le super admin).
create or replace function public.cap_carnet_etat() returns jsonb
language plpgsql stable security definer set search_path = public as $fn$
declare v_anim uuid := cap_animateur_id(); v_sup boolean := coalesce(cap_role(), '') = 'superadmin';
begin
  if not cap_est_equipe() then raise exception 'réservé à l''équipe'; end if;
  return jsonb_build_object(
    'moi', (select jsonb_build_object('le', c.carnet_le, 'nb', c.carnet_nb, 'branche', c.actif) from national_comptes c where c.animateur_id = v_anim),
    'commun', case when v_sup then (select jsonb_build_object('le', valeur) from reglages where cle = 'carnet_commun_le') end,
    'comptes', case when v_sup then (select coalesce(jsonb_agg(jsonb_build_object('animateur_id', c.animateur_id, 'nom', a.nom, 'le', c.carnet_le, 'nb', c.carnet_nb)), '[]'::jsonb) from national_comptes c join animateurs a on a.id = c.animateur_id where c.actif) end);
end $fn$;

-- Passage quotidien (6 h 40 au Maroc) : tous les comptes branchés et le compte commun.
create or replace function public.cap_carnet_lancer() returns bigint
language plpgsql security definer set search_path = public as $fn$
begin
  if coalesce(current_setting('request.jwt.claims', true), '') <> '' and cap_role() is distinct from 'superadmin' then raise exception 'réservé'; end if;
  return net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/national-carnet',
    body := '{"tous":true}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-suivi-jeton',(select decrypted_secret from vault.decrypted_secrets where name='national_suivi_jeton')),
    timeout_milliseconds := 120000);
end $fn$;
select cron.schedule('national-carnet', '40 5 * * *', $$select public.cap_carnet_lancer()$$);
