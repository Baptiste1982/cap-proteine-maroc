-- Espace membre (v0.23.0) : les membres se connectent avec leur numéro de téléphone et un code reçu par WhatsApp
-- (Supabase Auth, fournisseur téléphone Twilio Verify, canal whatsapp). Ils voient l'annuaire du réseau et
-- s'écrivent en messages directs (pas de groupes). Ils n'ont AUCUN accès au CRM.
--
-- 1) Fermer le CRM aux comptes sans profil d'équipe. Jusqu'ici « authentifié » suffisait pour lire clubs,
--    réunions, membres, animateurs, lieux, zones et pour écrire dans le bucket lieux : un membre connecté
--    aurait tout lu. Désormais il faut une ligne dans profiles (cap_est_equipe).
-- 2) Rattacher un compte membre à sa fiche par le numéro de téléphone (infos.m_tel, ou celui de sa demande d'adhésion),
--    vérifié par le code. Une demande d'adhésion pas encore intégrée répond « en_cours ».
-- 3) Annuaire (champs choisis, via une fonction), messages directs, préférences du membre.
-- Pas de DROP : les policies existantes sont modifiées par ALTER POLICY.

create or replace function public.cap_est_equipe() returns boolean
language sql stable security definer set search_path = public as
$$ select exists(select 1 from profiles where id = auth.uid()) $$;

create or replace function public.cap_can_see_club(c_id uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select cap_est_equipe() $$;

alter policy anim_read on public.animateurs using (cap_est_equipe());
alter policy lieux_read on public.lieux using (cap_est_equipe());
alter policy zones_read on public.zones using (cap_est_equipe());
alter policy lieux_auth_insert on storage.objects with check (bucket_id = 'lieux' and public.cap_est_equipe());
alter policy lieux_auth_update on storage.objects using (bucket_id = 'lieux' and public.cap_est_equipe()) with check (bucket_id = 'lieux' and public.cap_est_equipe());
alter policy lieux_auth_delete on storage.objects using (bucket_id = 'lieux' and public.cap_est_equipe());

-- Fiche membre ↔ compte
alter table public.membres add column if not exists user_id uuid unique references auth.users(id) on delete set null;
alter table public.membres add column if not exists tel_visible boolean not null default false;
alter table public.membres add column if not exists annuaire_visible boolean not null default true;
alter table public.membres add column if not exists cherche text;

-- Numéro marocain → chiffres E.164 sans « + » (format de auth.users.phone) : 0661… → 212661…
create or replace function public.cap_tel_norm(t text) returns text
language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(t, ''), '\D', '', 'g');
begin
  if d like '00%' then d := substr(d, 3); end if;
  if length(d) = 10 and d like '0%' then d := '212' || substr(d, 2); end if;
  if length(d) = 9 and d ~ '^[5-7]' then d := '212' || d; end if;
  return nullif(d, '');
end $$;

create or replace function public.cap_membre_id() returns uuid
language sql stable security definer set search_path = public as
$$ select id from membres where user_id = auth.uid() $$;

-- Appelée par l'espace membre après la vérification du code : rattache le compte à la fiche dont le mobile correspond.
create or replace function public.cap_membre_lier() returns json
language plpgsql security definer set search_path = public as $$
declare p text; n int; m membres%rowtype;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  select * into m from membres where user_id = auth.uid();
  if not found then
    select cap_tel_norm(phone) into p from auth.users where id = auth.uid();
    if p is null then return json_build_object('statut', 'sans_telephone'); end if;
    -- Le mobile vient de la fiche (infos.m_tel) ou, à défaut, de la demande d'adhésion rattachée à la fiche.
    select count(distinct x.id) into n from membres x left join adhesions a on a.membre_id = x.id
     where x.user_id is null and p in (cap_tel_norm(x.infos->>'m_tel'), cap_tel_norm(a.data->>'m_tel'));
    if n = 0 then
      if exists (select 1 from adhesions a where a.membre_id is null and a.statut <> 'rejetee' and cap_tel_norm(a.data->>'m_tel') = p)
        then return json_build_object('statut', 'en_cours'); end if;
      return json_build_object('statut', 'inconnu');
    end if;
    if n > 1 then return json_build_object('statut', 'ambigu'); end if;
    update membres set user_id = auth.uid() where id = (select x.id from membres x left join adhesions a on a.membre_id = x.id
     where x.user_id is null and p in (cap_tel_norm(x.infos->>'m_tel'), cap_tel_norm(a.data->>'m_tel')) limit 1) returning * into m;
  end if;
  return json_build_object('statut', 'ok', 'id', m.id, 'nom', m.nom,
    'club', (select nom from clubs where id = m.club_id), 'ville', (select ville from clubs where id = m.club_id),
    'cherche', m.cherche, 'tel_visible', m.tel_visible, 'annuaire_visible', m.annuaire_visible,
    'metier', coalesce(nullif(m.infos->>'metier', ''), m.specialite), 'entreprise', m.infos->>'ent_nom');
end $$;

-- Annuaire : seuls des champs choisis sortent, jamais les documents, commentaires ou suivi administratif.
create or replace function public.cap_annuaire() returns table(
  id uuid, nom text, club text, ville text, metier text, entreprise text, activite text, cherche text,
  telephone text, inscrit boolean, moi boolean)
language sql stable security definer set search_path = public as $$
  select m.id, m.nom, c.nom, coalesce(nullif(m.infos->>'ent_ville', ''), c.ville),
         coalesce(nullif(m.infos->>'metier', ''), m.specialite), m.infos->>'ent_nom', m.infos->>'ent_activite', m.cherche,
         case when m.tel_visible then m.infos->>'m_tel' end, m.user_id is not null, m.user_id = auth.uid()
  from membres m left join clubs c on c.id = m.club_id
  where (cap_membre_id() is not null or cap_est_equipe())
    and (m.annuaire_visible or m.user_id = auth.uid())
  order by m.nom
$$;

create or replace function public.cap_membre_profil(p_cherche text, p_tel_visible boolean, p_annuaire boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update membres set cherche = nullif(trim(p_cherche), ''), tel_visible = coalesce(p_tel_visible, false),
         annuaire_visible = coalesce(p_annuaire, true)
   where user_id = auth.uid();
  if not found then raise exception 'aucune fiche membre liée'; end if;
end $$;

-- Messages directs entre membres (pas de groupes)
create table if not exists public.messages_membres (
  id uuid primary key default gen_random_uuid(),
  de uuid not null references public.membres(id) on delete cascade,
  a uuid not null references public.membres(id) on delete cascade,
  texte text not null check (char_length(texte) between 1 and 4000),
  cree_le timestamptz not null default now(),
  lu_le timestamptz,
  check (de <> a)
);
create index if not exists messages_membres_de_a on public.messages_membres (de, a, cree_le);
create index if not exists messages_membres_a_lu on public.messages_membres (a, lu_le);
alter table public.messages_membres enable row level security;

create policy messages_lire on public.messages_membres for select to authenticated
  using (de = public.cap_membre_id() or a = public.cap_membre_id());
create policy messages_ecrire on public.messages_membres for insert to authenticated
  with check (de = public.cap_membre_id() and lu_le is null
    and exists (select 1 from public.membres d where d.id = a and d.user_id is not null and d.annuaire_visible));

create or replace function public.cap_messages_lus(p_avec uuid) returns void
language sql security definer set search_path = public as $$
  update messages_membres set lu_le = now() where a = cap_membre_id() and de = p_avec and lu_le is null
$$;

alter publication supabase_realtime add table public.messages_membres;

comment on table public.messages_membres is 'Messages directs entre membres (espace membre). Privés : l''équipe du CRM ne les lit pas.';
