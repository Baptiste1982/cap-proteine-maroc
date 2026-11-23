-- v1.146 : inviter tout le réseau à un événement (interclub…). Ville de l'événement, suivi des relais par groupe,
-- inscriptions par une page publique (evenement.html). Aucune lecture publique des inscrits.
alter table public.evenements_reseau
  add column if not exists ville text,
  add column if not exists invitation jsonb not null default '{}'::jsonb,
  add column if not exists national jsonb;

create table if not exists public.evenement_inscrits (
  id uuid primary key default gen_random_uuid(),
  evenement_id uuid not null references public.evenements_reseau(id) on delete cascade,
  nom text not null,
  cle text not null,
  club_id uuid references public.clubs(id) on delete set null,
  qualite text not null default 'membre',
  tel text,
  source text,
  cree_le timestamptz not null default now(),
  unique (evenement_id, cle)
);
alter table public.evenement_inscrits enable row level security;
-- Lecture : qui gère le réseau, ou l'équipe qui voit le groupe de l'inscrit. Aucune écriture directe (RPC seulement).
create policy evenement_inscrits_lire on public.evenement_inscrits for select
  using (public.cap_gere_reseau() or (club_id is not null and public.cap_can_see_club(club_id)));
create policy evenement_inscrits_retirer on public.evenement_inscrits for delete using (public.cap_gere_reseau());

-- Page publique : ce qu'il faut pour afficher l'invitation (aucune coordonnée, aucun nom d'inscrit).
create or replace function public.cap_evenement_public(p_id uuid) returns jsonb
language sql stable security definer set search_path = public as $fn$
  select jsonb_build_object('titre', e.titre, 'genre', e.genre, 'date', e.date, 'heure', e.heure, 'lieu', e.lieu, 'ville', e.ville, 'note', e.note,
    'inscrits', (select count(*) from evenement_inscrits i where i.evenement_id = e.id),
    'groupes', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nom', c.nom, 'ville', c.ville) order by c.ville, c.nom), '[]'::jsonb) from clubs c))
  from evenements_reseau e where e.id = p_id and e.date >= current_date;
$fn$;

-- Inscription depuis la page publique. Une personne (même nom) ne compte qu'une fois ; plafonds contre l'abus.
create or replace function public.cap_evenement_inscrire(p_id uuid, p_nom text, p_club uuid, p_tel text, p_source text)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare v_nom text := btrim(regexp_replace(coalesce(p_nom, ''), '\s+', ' ', 'g')); v_cle text; v_deja boolean;
begin
  if not exists (select 1 from evenements_reseau where id = p_id and date >= current_date) then return jsonb_build_object('ok', false, 'motif', 'ferme'); end if;
  if length(v_nom) < 3 or length(v_nom) > 80 then return jsonb_build_object('ok', false, 'motif', 'nom'); end if;
  v_cle := cap_nom_cle(v_nom);
  if coalesce(v_cle, '') = '' then return jsonb_build_object('ok', false, 'motif', 'nom'); end if;
  if p_club is not null and not exists (select 1 from clubs where id = p_club) then p_club := null; end if;
  v_deja := exists (select 1 from evenement_inscrits where evenement_id = p_id and cle = v_cle);
  if not v_deja then
    if (select count(*) from evenement_inscrits where evenement_id = p_id) >= 800
       or (select count(*) from evenement_inscrits where evenement_id = p_id and cree_le > now() - interval '1 hour') >= 120 then
      return jsonb_build_object('ok', false, 'motif', 'plein');
    end if;
  end if;
  insert into evenement_inscrits (evenement_id, nom, cle, club_id, qualite, tel, source)
  values (p_id, v_nom, v_cle, p_club, case when p_club is null then 'invite' else 'membre' end, nullif(left(btrim(coalesce(p_tel, '')), 24), ''), nullif(left(coalesce(p_source, ''), 40), ''))
  on conflict (evenement_id, cle) do update set club_id = coalesce(excluded.club_id, evenement_inscrits.club_id), tel = coalesce(excluded.tel, evenement_inscrits.tel);
  return jsonb_build_object('ok', true, 'deja', v_deja);
end $fn$;

-- Décompte par groupe pour toute l'équipe (sans nom ni coordonnée) : chacun voit où en est l'ensemble du réseau.
create or replace function public.cap_evenement_decompte(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $fn$
begin
  if not cap_est_equipe() or cap_role() = 'visiteur' then raise exception 'réservé à l''équipe'; end if;
  return (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(club_id::text, 'ext') k, count(*) n from evenement_inscrits where evenement_id = p_id group by 1) t);
end $fn$;

-- Un animateur note qu'il a relayé le message dans son groupe (il ne peut pas modifier l'événement lui-même).
create or replace function public.cap_evenement_relais(p_id uuid, p_club uuid) returns void
language plpgsql security definer set search_path = public as $fn$
begin
  if not (cap_gere_reseau() or cap_can_edit_club(p_club)) then raise exception 'réservé à l''équipe du groupe'; end if;
  update evenements_reseau set invitation = coalesce(invitation, '{}'::jsonb) || jsonb_build_object(p_club::text, jsonb_build_object('le', now(),
    'par', (select split_part(coalesce(nom, ''), ' ', 1) from profiles where id = auth.uid()))) where id = p_id;
end $fn$;
