-- v0.26.0 : recommandations d'affaires, présences par QR code, renouvellements d'abonnement, relance des invités.
-- Pas de DROP, pas de DELETE.
--
-- 1) Recommandations : un membre en donne une à un autre (un contact qui a un besoin). Celui qui la REÇOIT la fait
--    avancer (contact pris → devis → affaire signée + montant, ou sans suite). Lecture : les deux membres + l'équipe.
--    Le club voit un total collectif (cap_membre_recos_club) sans détail par personne.
-- 2) Présences : chaque réunion a un code de pointage (QR). Le membre connecté le scanne et se pointe lui-même ;
--    l'animateur coche les autres dans le CRM.
-- 3) Renouvellements : membres.abonnement_debut (à défaut, la date d'intégration côté appli). Échéance = début + 1 an.
-- 4) Relance des invités : invites.rappel_le / suivi_le (le message WhatsApp a été préparé et envoyé).

-- ---------- 1) Recommandations ----------
create table if not exists public.recommandations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid references public.clubs(id) on delete set null,          -- club de celui qui donne
  de uuid not null references public.membres(id) on delete cascade,
  a uuid not null references public.membres(id) on delete cascade,
  contact_nom text not null check (char_length(contact_nom) between 1 and 120),
  contact_tel text,
  contact_entreprise text,
  besoin text,
  statut text not null default 'envoyee' check (statut in ('envoyee','contact','devis','signee','sans_suite')),
  montant numeric(14,2) check (montant is null or montant >= 0),
  cree_le timestamptz not null default now(),
  maj_le timestamptz not null default now(),
  notifie_le timestamptz,
  suivi_notifie text,
  check (de <> a)
);
create index if not exists recommandations_de on public.recommandations (de, cree_le);
create index if not exists recommandations_a on public.recommandations (a, cree_le);
create index if not exists recommandations_club on public.recommandations (club_id, statut, maj_le);
alter table public.recommandations enable row level security;

create policy recos_lire on public.recommandations for select to authenticated
  using (de = public.cap_membre_id() or a = public.cap_membre_id()
         or (public.cap_est_equipe() and public.cap_can_see_club(club_id)));
create policy recos_equipe_modifier on public.recommandations for update to authenticated
  using (public.cap_est_equipe() and public.cap_can_edit_club(club_id))
  with check (public.cap_est_equipe() and public.cap_can_edit_club(club_id));

create or replace function public.cap_membre_reco_donner(p_a uuid, p_nom text, p_tel text, p_entreprise text, p_besoin text)
returns uuid language plpgsql security definer set search_path = public as $$
declare me membres%rowtype; n int; rid uuid;
begin
  select * into me from membres where user_id = auth.uid();
  if not found then raise exception 'aucune fiche membre liée'; end if;
  if p_a is null or p_a = me.id or not exists (select 1 from membres where id = p_a) then raise exception 'destinataire invalide'; end if;
  if coalesce(trim(p_nom), '') = '' then raise exception 'le nom du contact est obligatoire'; end if;
  select count(*) into n from recommandations where de = me.id and cree_le > now() - interval '1 day';
  if n >= 30 then raise exception 'trop de recommandations aujourd''hui'; end if;
  insert into recommandations (club_id, de, a, contact_nom, contact_tel, contact_entreprise, besoin)
  values (me.club_id, me.id, p_a, left(trim(p_nom), 120), nullif(left(trim(p_tel), 40), ''),
          nullif(left(trim(p_entreprise), 120), ''), nullif(left(trim(p_besoin), 1000), ''))
  returning id into rid;
  return rid;
end $$;

-- Seul celui qui a reçu la recommandation la fait avancer.
create or replace function public.cap_membre_reco_avancer(p_id uuid, p_statut text, p_montant numeric)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_statut not in ('envoyee','contact','devis','signee','sans_suite') then raise exception 'statut inconnu'; end if;
  if p_statut = 'signee' and (p_montant is null or p_montant < 0) then raise exception 'indique le montant de l''affaire'; end if;
  update recommandations
     set statut = p_statut, montant = case when p_statut = 'signee' then p_montant else montant end, maj_le = now()
   where id = p_id and a = cap_membre_id();
  if not found then raise exception 'recommandation introuvable'; end if;
end $$;

-- Total collectif du club du membre connecté (aucun détail par personne).
create or replace function public.cap_membre_recos_club() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'club', c.nom,
    'mois_montant', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= date_trunc('month', now())), 0),
    'mois_affaires', count(r.id) filter (where r.statut = 'signee' and r.maj_le >= date_trunc('month', now())),
    'mois_recos', count(r.id) filter (where r.cree_le >= date_trunc('month', now())),
    'annee_montant', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= date_trunc('year', now())), 0),
    'annee_affaires', count(r.id) filter (where r.statut = 'signee' and r.maj_le >= date_trunc('year', now())),
    'annee_recos', count(r.id) filter (where r.cree_le >= date_trunc('year', now())))
  from membres m join clubs c on c.id = m.club_id
  left join recommandations r on r.club_id = c.id
  where m.user_id = auth.uid()
  group by c.nom
$$;

create or replace trigger recommandations_notifier after insert on public.recommandations
  for each row execute function public.membres_notifier('reco');
create or replace trigger recommandations_suivi_notifier after update of statut on public.recommandations
  for each row when (new.statut is distinct from old.statut) execute function public.membres_notifier('reco_suivi');

alter publication supabase_realtime add table public.recommandations;

-- ---------- 2) Présences ----------
alter table public.reunions add column if not exists presence_code text;

create table if not exists public.presences (
  id uuid primary key default gen_random_uuid(),
  reunion_id uuid not null references public.reunions(id) on delete cascade,
  membre_id uuid not null references public.membres(id) on delete cascade,
  mode text not null default 'animateur' check (mode in ('qr','animateur')),
  pointe_le timestamptz not null default now(),
  pointe_par uuid,
  unique (reunion_id, membre_id)
);
alter table public.presences enable row level security;
create policy presences_lire on public.presences for select to authenticated
  using (membre_id = public.cap_membre_id()
         or (public.cap_est_equipe() and exists (select 1 from public.reunions r where r.id = reunion_id and public.cap_can_see_club(r.club_id))));
create policy presences_ajouter on public.presences for insert to authenticated
  with check (public.cap_est_equipe() and exists (select 1 from public.reunions r where r.id = reunion_id and public.cap_can_edit_club(r.club_id)));
create policy presences_retirer on public.presences for delete to authenticated
  using (public.cap_est_equipe() and exists (select 1 from public.reunions r where r.id = reunion_id and public.cap_can_edit_club(r.club_id)));

-- L'équipe (re)génère le code de pointage d'une réunion.
create or replace function public.cap_reunion_code(p_reunion uuid) returns text
language plpgsql security definer set search_path = public as $$
declare c uuid; k text;
begin
  select club_id, presence_code into c, k from reunions where id = p_reunion;
  if not found then raise exception 'réunion introuvable'; end if;
  if not (cap_est_equipe() and cap_can_edit_club(c)) then raise exception 'pas autorisé'; end if;
  if k is null then
    k := substr(md5(gen_random_uuid()::text), 1, 10);
    update reunions set presence_code = k where id = p_reunion;
  end if;
  return k;
end $$;

-- Le membre se pointe en scannant le QR (le jour de la réunion, à un jour près).
create or replace function public.cap_membre_pointer(p_reunion uuid, p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare me uuid; r reunions%rowtype; deja boolean;
begin
  me := cap_membre_id();
  if me is null then raise exception 'aucune fiche membre liée'; end if;
  select * into r from reunions where id = p_reunion;
  if not found or r.presence_code is null or r.presence_code <> coalesce(p_code, '') then raise exception 'code de présence invalide'; end if;
  if r.statut = 'annulee' then raise exception 'cette réunion est annulée'; end if;
  if abs(r.date - current_date) > 1 then raise exception 'le pointage n''est ouvert que le jour de la réunion'; end if;
  select exists(select 1 from presences where reunion_id = r.id and membre_id = me) into deja;
  if not deja then insert into presences (reunion_id, membre_id, mode) values (r.id, me, 'qr'); end if;
  return json_build_object('deja', deja, 'date', r.date, 'heure', r.heure,
    'club', (select nom from clubs where id = r.club_id));
end $$;

-- ---------- 3) Renouvellements ----------
alter table public.membres add column if not exists abonnement_debut date;
alter table public.membres add column if not exists relance_renouv_le timestamptz;

-- ---------- 4) Relance des invités ----------
alter table public.invites add column if not exists rappel_le timestamptz;
alter table public.invites add column if not exists suivi_le timestamptz;
