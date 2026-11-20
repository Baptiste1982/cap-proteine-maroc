-- v1.134 : chaque région a UN responsable, attribué par la direction (super admin, direction nationale) et cessible
-- par le responsable lui-même. L'historique garde qui a tenu la région, de quand à quand. Un compte national
-- (directeur national, super admin) peut tenir une ou plusieurs régions sans changer de rôle ; un animateur
-- qui reçoit une région devient « directeur » de cette région. Les PSA d'une région sont menés par son responsable.
alter table public.zones add column if not exists responsable_id uuid references public.profiles(id) on delete set null;
alter table public.zones add column if not exists responsable_depuis timestamptz;

create table if not exists public.zones_responsables (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.zones(id) on delete cascade,
  profil_id uuid references public.profiles(id) on delete set null,
  nom text, du timestamptz not null default now(), au timestamptz,
  attribue_par uuid, par_nom text, note text);
alter table public.zones_responsables enable row level security;
create policy zones_responsables_lire on public.zones_responsables for select to authenticated using (cap_est_equipe());

create or replace function public.cap_region_attribuer(p_zone uuid, p_profil uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare moi uuid := auth.uid(); r text; cur uuid; v_role text; v_zone uuid; v_nom text; mon_nom text; old_role text; old_zone uuid;
begin
  if moi is null or cap_voir() is not null then raise exception 'réservé'; end if;
  select role, nom into r, mon_nom from profiles where id = moi;
  select responsable_id into cur from zones where id = p_zone;
  if not found then raise exception 'région inconnue'; end if;
  if not (coalesce(r, '') in ('superadmin', 'directeur_national') or (cur is not null and cur = moi and p_profil is not null)) then
    raise exception 'Seuls la direction nationale et le responsable actuel peuvent attribuer cette région';
  end if;
  if cur is not distinct from p_profil then return jsonb_build_object('ok', true, 'inchange', true); end if;
  if p_profil is not null then
    select p.role, p.zone_id, coalesce(a.nom, p.nom) into v_role, v_zone, v_nom from profiles p left join animateurs a on a.id = p.animateur_id where p.id = p_profil;
    if v_role is null then raise exception 'compte inconnu'; end if;
    if v_role = 'visiteur' then raise exception 'le compte visiteur ne peut pas tenir une région'; end if;
    if v_role = 'directeur' and v_zone is distinct from p_zone and exists (select 1 from zones where responsable_id = p_profil) then
      raise exception '% est déjà responsable d''une autre région : fais-lui d''abord céder la sienne', v_nom;
    end if;
  end if;
  update zones_responsables set au = now() where zone_id = p_zone and au is null;
  if p_profil is not null then
    insert into zones_responsables (zone_id, profil_id, nom, attribue_par, par_nom, note)
    values (p_zone, p_profil, v_nom, moi, mon_nom, nullif(btrim(coalesce(p_note, '')), ''));
  end if;
  update zones set responsable_id = p_profil, responsable_depuis = case when p_profil is null then null else now() end where id = p_zone;
  if cur is not null then
    select role, zone_id into old_role, old_zone from profiles where id = cur;
    if old_role = 'directeur' and old_zone = p_zone then update profiles set role = 'animateur' where id = cur; end if;
  end if;
  if p_profil is not null and v_role in ('animateur', 'directeur') then
    update profiles set role = 'directeur', zone_id = p_zone where id = p_profil;
  end if;
  return jsonb_build_object('ok', true, 'responsable', p_profil, 'nom', v_nom);
end $fn$;

create or replace function public.cap_regions_responsables() returns jsonb
language sql stable security definer set search_path = public as $fn$
  select case when cap_est_equipe() then coalesce((
    select jsonb_agg(jsonb_build_object('zone_id', z.id, 'profil', z.responsable_id,
             'nom', (select coalesce(a.nom, p.nom) from profiles p left join animateurs a on a.id = p.animateur_id where p.id = z.responsable_id),
             'role', (select p.role from profiles p where p.id = z.responsable_id),
             'depuis', z.responsable_depuis,
             'historique', coalesce((select jsonb_agg(jsonb_build_object('nom', h.nom, 'du', h.du, 'au', h.au, 'par', h.par_nom, 'note', h.note) order by h.du desc)
                                       from zones_responsables h where h.zone_id = z.id), '[]'::jsonb)) order by z.nom)
      from zones z), '[]'::jsonb) else '[]'::jsonb end
$fn$;

-- PSA : la région est menée par son responsable quand elle en a un (sinon, comme avant, par ses comptes de direction).
create or replace function public.cap_psa_suivi_calc() returns jsonb
language plpgsql stable security definer set search_path = public as $fn$
declare debut_mois timestamptz := date_trunc('month', now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
begin
  if coalesce(current_setting('cap.psa_interne', true), '') <> '1' and coalesce(current_setting('request.jwt.claims', true), '') <> '' then
    raise exception 'réservé';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'zone_id', z.id, 'nom', z.nom,
      'directeurs', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nom', coalesce(a.nom, p.nom)) order by p.nom)
                                from profiles p left join animateurs a on a.id = p.animateur_id
                               where case when z.responsable_id is not null then p.id = z.responsable_id
                                          else p.zone_id = z.id and p.role in ('directeur', 'superadmin') end), '[]'::jsonb),
      'responsable_id', z.responsable_id,
      'creneaux', (select count(*) from psa_creneaux c where c.zone_id = z.id and c.debut > now()),
      'libres', (select count(*) from psa_creneaux c where c.zone_id = z.id and c.debut > now() and c.reserve_par is null and c.reserve_lien is null),
      'animateurs', coalesce((
        select jsonb_agg(jsonb_build_object('id', x.id, 'nom', x.nom, 'groupes', x.groupes, 'compte', x.compte, 'profils', x.profils,
                 'prochain', x.prochain, 'dernier', x.dernier,
                 'a_caler', x.prochain is null and (x.dernier is null or x.dernier < debut_mois)) order by x.nom)
        from (
          select a.id, a.nom,
                 (select jsonb_agg(c.nom order by c.nom) from clubs c where c.animateur_id = a.id) as groupes,
                 exists (select 1 from profiles p where p.animateur_id = a.id) as compte,
                 coalesce((select jsonb_agg(p.id) from profiles p where p.animateur_id = a.id), '[]'::jsonb) as profils,
                 (select min(s.debut) from psa_creneaux s where s.debut > now()
                    and (s.reserve_par in (select p.id from profiles p where p.animateur_id = a.id)
                      or s.reserve_lien in (select l.jeton from psa_liens l where l.animateur_id = a.id))) as prochain,
                 (select max(s.debut) from psa_creneaux s where s.debut <= now()
                    and (s.reserve_par in (select p.id from profiles p where p.animateur_id = a.id)
                      or s.reserve_lien in (select l.jeton from psa_liens l where l.animateur_id = a.id))) as dernier
            from animateurs a
           where exists (select 1 from clubs c where c.animateur_id = a.id
                           and lower(unaccent_simple(c.ville)) in (select lower(unaccent_simple(v)) from unnest(z.villes) v))
             and not exists (select 1 from profiles p where p.animateur_id = a.id and p.role in ('superadmin', 'directeur', 'directeur_national'))
        ) x), '[]'::jsonb)) order by z.nom)
    from zones z), '[]'::jsonb);
end $fn$;
