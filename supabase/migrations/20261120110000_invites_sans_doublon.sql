-- v1.69.0 — une personne ne figure qu'une fois dans une réunion, qu'elle s'inscrive par le lien du national,
-- par « Je viens » dans le CRM, ou qu'on l'ajoute à la main. Rapprochement : même mobile, même e-mail ou même nom.

create or replace function public.cap_nom_cle(t text) returns text language sql immutable
as $function$ select regexp_replace(unaccent_simple(lower(coalesce(t, ''))), '[^a-z]', '', 'g') $function$;

-- L'invité déjà présent dans la réunion qui correspond à cette personne (sinon null).
create or replace function public.cap_invite_meme(p_reunion uuid, p_nom text, p_tel text, p_email text)
 returns uuid language sql stable security definer set search_path to 'public'
as $function$
  select i.id from invites i
  where i.reunion_id = p_reunion and (cap_est_equipe() or cap_membre_id() is not null)
    and ((cap_tel_norm(p_tel) is not null and cap_tel_norm(i.tel) = cap_tel_norm(p_tel))
      or (nullif(lower(trim(p_email)), '') is not null and lower(trim(i.email)) = lower(trim(p_email)))
      or (length(cap_nom_cle(p_nom)) >= 6 and cap_nom_cle(i.nom) = cap_nom_cle(p_nom)))
  order by (i.national_id is not null) desc, i.created_at limit 1
$function$;

create or replace function public.invites_sans_doublon() returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare e invites%rowtype; src text;
begin
  select i.* into e from invites i
  where i.reunion_id = new.reunion_id
    and ((cap_tel_norm(new.tel) is not null and cap_tel_norm(i.tel) = cap_tel_norm(new.tel))
      or (nullif(lower(trim(new.email)), '') is not null and lower(trim(i.email)) = lower(trim(new.email)))
      or (length(cap_nom_cle(new.nom)) >= 6 and cap_nom_cle(i.nom) = cap_nom_cle(new.nom)))
  order by (i.national_id is not null) desc, i.created_at limit 1;
  if not found then return new; end if;
  -- inscription par le lien du national : on complète la ligne existante
  if new.national_id is not null then
    if e.national_id is null then
      update invites set national_id = new.national_id, email = coalesce(email, new.email),
             entreprise = coalesce(nullif(entreprise, ''), new.entreprise), metier = coalesce(nullif(metier, ''), new.metier),
             note = trim(both ' ·' from coalesce(note, '') || ' · ' || coalesce(new.note, 'Inscrit aussi par le lien du national'))
       where id = e.id;
      return null;
    end if;
    return new;
  end if;
  -- « Je viens » d'un compte d'équipe : on relie son compte à la ligne existante
  if new.profil_id is not null then
    if e.profil_id is null then
      update invites set profil_id = new.profil_id,
             note = trim(both ' ·' from coalesce(note, '') || ' · Inscrit aussi depuis le CRM') where id = e.id;
      return null;
    end if;
    return new;
  end if;
  -- ajout à la main ou proposition d'un membre : refus, avec la raison
  src := case when e.national_id is not null then 'par le lien du national'
              when e.profil_id is not null then 'depuis le CRM (équipe)'
              when e.propose_par is not null then 'par un membre, depuis l''espace membre'
              else 'dans le CRM' end;
  raise exception '% est déjà inscrit à cette réunion (%).', e.nom, src using errcode = 'P0001';
end $function$;

create or replace trigger invites_sans_doublon before insert on public.invites
  for each row execute function public.invites_sans_doublon();

-- Membre : « Je viens » dit aussi s'il figure déjà parmi les inscrits du lien.
create or replace function public.cap_membre_repondre(p_reunion uuid, p_reponse text)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
declare v_mb uuid := cap_membre_id(); r reunions%rowtype; mb membres%rowtype; v_deja boolean;
begin
  if v_mb is null then raise exception 'aucune fiche membre liée'; end if;
  if p_reponse not in ('oui','non') then raise exception 'réponse inconnue'; end if;
  select * into r from reunions where id = p_reunion;
  if not found then raise exception 'réunion introuvable'; end if;
  if r.statut = 'annulee' then raise exception 'cette réunion est annulée'; end if;
  if r.date < current_date then raise exception 'cette réunion est passée'; end if;
  select * into mb from membres where id = v_mb;
  v_deja := exists (select 1 from invites i where i.id = cap_invite_meme(p_reunion, mb.nom, mb.infos->>'m_tel', mb.infos->>'m_email') and i.national_id is not null);
  insert into reunion_reponses (reunion_id, membre_id, reponse) values (p_reunion, v_mb, p_reponse)
  on conflict (reunion_id, membre_id) do update set reponse = excluded.reponse, maj_le = now();
  return json_build_object('ma_reponse', p_reponse, 'deja_lien', v_deja,
    'viennent', (select count(*) from reunion_reponses where reunion_id = p_reunion and reponse = 'oui'),
    'absents', (select count(*) from reunion_reponses where reunion_id = p_reunion and reponse = 'non'));
end $function$;
