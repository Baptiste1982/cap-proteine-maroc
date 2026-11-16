-- v1.1.0 — Espace membre : fiche signalétique, invités du groupe, fil de discussion du groupe.
-- Uniquement des ajouts (aucune suppression).

-- 1) Fiche signalétique du membre (pré-remplie à l'affichage avec la demande d'adhésion : infos.ent_web, infos.ent_activite…)
alter table public.membres add column if not exists photo_url text;
alter table public.membres add column if not exists logo_url text;
alter table public.membres add column if not exists presentation text;
alter table public.membres add column if not exists site text;
alter table public.membres add column if not exists linkedin text;
alter table public.membres add column if not exists reseaux text;

-- Photos et logos : bucket public (images non sensibles, montrées dans l'annuaire), 5 Mo, rangées par fiche membre.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profils', 'profils', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "profils lecture" on storage.objects for select using (bucket_id = 'profils');
create policy "profils ajout" on storage.objects for insert to authenticated
  with check (bucket_id = 'profils' and (
    (cap_est_equipe() and exists (select 1 from membres m where m.id::text = split_part(name, '/', 1) and cap_can_edit_club(m.club_id)))
    or split_part(name, '/', 1) = cap_membre_id()::text));
create policy "profils maj" on storage.objects for update to authenticated
  using (bucket_id = 'profils' and (
    (cap_est_equipe() and exists (select 1 from membres m where m.id::text = split_part(name, '/', 1) and cap_can_edit_club(m.club_id)))
    or split_part(name, '/', 1) = cap_membre_id()::text));
create policy "profils retrait" on storage.objects for delete to authenticated
  using (bucket_id = 'profils' and (
    (cap_est_equipe() and exists (select 1 from membres m where m.id::text = split_part(name, '/', 1) and cap_can_edit_club(m.club_id)))
    or split_part(name, '/', 1) = cap_membre_id()::text));

-- Annuaire enrichi (nouvelle fonction : cap_annuaire reste pour les anciennes versions de la page).
create or replace function public.cap_annuaire_fiche()
returns table(id uuid, nom text, club text, club_id uuid, ville text, metier text, entreprise text, activite text, cherche text,
              telephone text, inscrit boolean, moi boolean, photo text, logo text, presentation text, site text, linkedin text,
              reseaux text, fonction text)
language sql stable security definer set search_path = public as $$
  select m.id, m.nom, c.nom, m.club_id, coalesce(nullif(m.infos->>'ent_ville', ''), c.ville),
         coalesce(nullif(m.infos->>'metier', ''), m.specialite), m.infos->>'ent_nom', m.infos->>'ent_activite', m.cherche,
         case when m.tel_visible then m.infos->>'m_tel' end, m.user_id is not null, m.user_id = auth.uid(),
         m.photo_url, m.logo_url,
         coalesce(nullif(m.presentation, ''), nullif(m.infos->>'ent_activite', '')),
         coalesce(nullif(m.site, ''), nullif(m.infos->>'ent_web', '')),
         m.linkedin, m.reseaux, m.infos->>'m_fonction'
  from membres m left join clubs c on c.id = m.club_id
  where (cap_membre_id() is not null or cap_est_equipe())
    and (m.annuaire_visible or m.user_id = auth.uid())
  order by m.nom
$$;

-- Le membre met à jour sa propre fiche signalétique.
create or replace function public.cap_membre_fiche_maj(p_presentation text, p_site text, p_linkedin text, p_reseaux text,
                                                       p_photo text, p_logo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update membres set presentation = nullif(trim(left(p_presentation, 1500)), ''), site = nullif(trim(left(p_site, 300)), ''),
         linkedin = nullif(trim(left(p_linkedin, 300)), ''), reseaux = nullif(trim(left(p_reseaux, 300)), ''),
         photo_url = coalesce(p_photo, photo_url), logo_url = coalesce(p_logo, logo_url)
   where user_id = auth.uid();
  if not found then raise exception 'aucune fiche membre liée'; end if;
end $$;

-- 2) Invités des réunions du groupe du membre (à venir et passées), coordonnées comprises (choix JB du 16/11).
create or replace function public.cap_membre_invites_groupe()
returns table(id uuid, nom text, entreprise text, metier text, tel text, email text, statut text, date date, type text,
              invite_par text, propose_par_nom text)
language sql stable security definer set search_path = public as $$
  select i.id, i.nom, i.entreprise, i.metier, i.tel, i.email, i.statut, r.date, r.type, i.invite_par, pm.nom
  from invites i join reunions r on r.id = i.reunion_id
  left join membres pm on pm.id = i.propose_par
  where r.club_id = (select club_id from membres where id = cap_membre_id())
  order by r.date desc, i.nom
$$;

-- 3) Fil de discussion du groupe : les membres du groupe et l'équipe qui anime le groupe.
create table if not exists public.messages_groupe (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  auteur uuid not null default auth.uid(),
  auteur_nom text not null,
  membre_id uuid references public.membres(id) on delete set null,
  texte text not null check (char_length(texte) between 1 and 2000),
  cree_le timestamptz not null default now()
);
create index if not exists messages_groupe_club on public.messages_groupe (club_id, cree_le desc);
alter table public.messages_groupe enable row level security;

create or replace function public.cap_groupe_acces(p_club uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (cap_est_equipe() and cap_can_edit_club(p_club))
      or exists (select 1 from membres m where m.user_id = auth.uid() and m.club_id = p_club)
$$;

create policy "groupe lecture" on public.messages_groupe for select to authenticated using (cap_groupe_acces(club_id));

create or replace function public.cap_groupe_ecrire(p_club uuid, p_texte text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_nom text; v_mb uuid;
begin
  if not cap_groupe_acces(p_club) then raise exception 'accès refusé'; end if;
  if char_length(trim(coalesce(p_texte, ''))) = 0 then raise exception 'message vide'; end if;
  select id, nom into v_mb, v_nom from membres where user_id = auth.uid() and club_id = p_club limit 1;
  if v_nom is null then select coalesce(nom, login) into v_nom from profiles where id = auth.uid(); end if;
  insert into messages_groupe (club_id, auteur, auteur_nom, membre_id, texte)
  values (p_club, auth.uid(), coalesce(v_nom, 'Équipe'), v_mb, left(trim(p_texte), 2000)) returning id into v_id;
  return v_id;
end $$;

alter publication supabase_realtime add table public.messages_groupe;
