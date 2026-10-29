-- Espace membre (v0.25.0) : notifications des messages + invités proposés par les membres.
--
-- 1) Notifications : chaque nouveau message déclenche l'edge notif-membre (web push vers les appareils du
--    destinataire, table push_abonnements déjà en place). Réservation atomique de notifie_le : pas de doublon.
-- 2) Invités : un membre propose un invité pour la PROCHAINE réunion de son club. La ligne entre dans la table
--    invites existante (statut « À confirmer »), avec propose_par = le membre ; l'animateur du club et la
--    direction reçoivent une notification. Le membre ne lit que ses propres propositions, par RPC.
-- Pas de DROP.

alter table public.messages_membres add column if not exists notifie_le timestamptz;

alter table public.invites add column if not exists entreprise text;
alter table public.invites add column if not exists metier text;
alter table public.invites add column if not exists note text;
alter table public.invites add column if not exists propose_par uuid references public.membres(id) on delete set null;
alter table public.invites add column if not exists notifie_le timestamptz;

create or replace function public.membres_notifier() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-membre',
    body := jsonb_build_object('type', tg_argv[0], 'id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json'));
  return new;
end $$;

create or replace trigger messages_membres_notifier after insert on public.messages_membres
  for each row execute function public.membres_notifier('message');
create or replace trigger invites_proposes_notifier after insert on public.invites
  for each row when (new.propose_par is not null) execute function public.membres_notifier('invite');

-- Prochaine réunion du club du membre connecté (aujourd'hui ou plus tard, non annulée).
create or replace function public.cap_membre_prochaine_reunion() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('id', r.id, 'date', r.date, 'heure', r.heure, 'type', r.type,
    'lieu', l.nom, 'adresse', l.adresse, 'ville', coalesce(l.ville, c.ville), 'club', c.nom)
  from membres m join clubs c on c.id = m.club_id
  join reunions r on r.club_id = c.id and r.date >= current_date and r.statut <> 'annulee'
  left join lieux l on l.id = r.lieu_id
  where m.user_id = auth.uid()
  order by r.date, r.heure nulls last limit 1
$$;

create or replace function public.cap_membre_proposer_invite(p_nom text, p_entreprise text, p_metier text, p_tel text, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare me membres%rowtype; rid uuid; n int; iid uuid;
begin
  select * into me from membres where user_id = auth.uid();
  if not found then raise exception 'aucune fiche membre liée'; end if;
  if coalesce(trim(p_nom), '') = '' then raise exception 'le nom de l''invité est obligatoire'; end if;
  select count(*) into n from invites where propose_par = me.id and created_at > now() - interval '1 day';
  if n >= 20 then raise exception 'trop de propositions aujourd''hui'; end if;
  select r.id into rid from reunions r where r.club_id = me.club_id and r.date >= current_date and r.statut <> 'annulee'
   order by r.date, r.heure nulls last limit 1;
  if rid is null then raise exception 'aucune réunion planifiée pour ton club'; end if;
  insert into invites (reunion_id, nom, tel, invite_par, statut, entreprise, metier, note, propose_par, created_at)
  values (rid, left(trim(p_nom), 120), nullif(left(trim(p_tel), 40), ''), me.nom, 'À confirmer',
          nullif(left(trim(p_entreprise), 120), ''), nullif(left(trim(p_metier), 120), ''), nullif(left(trim(p_note), 600), ''), me.id, now())
  returning id into iid;
  return json_build_object('id', iid, 'reunion_id', rid);
end $$;

create or replace function public.cap_membre_mes_invites() returns table(
  id uuid, nom text, entreprise text, metier text, statut text, date date, cree_le timestamptz)
language sql stable security definer set search_path = public as $$
  select i.id, i.nom, i.entreprise, i.metier, i.statut, r.date, i.created_at
  from invites i join reunions r on r.id = i.reunion_id
  where i.propose_par = cap_membre_id()
  order by i.created_at desc limit 100
$$;
