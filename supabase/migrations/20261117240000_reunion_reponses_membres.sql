-- v1.9.0 : le membre dit s'il vient à la prochaine réunion (« Je viens » / « Je ne viens pas ») depuis son espace.
-- L'animateur (et la direction) voit les réponses dans la fiche de la réunion du CRM.
-- Une réponse par membre et par réunion, modifiable jusqu'au jour de la réunion. Écriture par RPC seulement.
-- Pas de DROP, pas de DELETE.

create table if not exists public.reunion_reponses (
  id uuid primary key default gen_random_uuid(),
  reunion_id uuid not null references public.reunions(id) on delete cascade,
  membre_id uuid not null references public.membres(id) on delete cascade,
  reponse text not null check (reponse in ('oui','non')),
  maj_le timestamptz not null default now(),
  unique (reunion_id, membre_id)
);
comment on table public.reunion_reponses is 'Réponse d''un membre à la prochaine réunion de son groupe (oui = il vient, non = il ne vient pas), saisie dans l''espace membre.';
alter table public.reunion_reponses enable row level security;

-- Lecture : l'équipe qui voit le club de la réunion, et le membre pour sa propre réponse.
create policy reunion_reponses_lire on public.reunion_reponses for select to authenticated
  using (
    membre_id = public.cap_membre_id()
    or exists (select 1 from public.reunions r where r.id = reunion_id and public.cap_can_see_club(r.club_id))
  );

-- Répondre : membre du club de la réunion, réunion à venir et non annulée. Rend les totaux.
create or replace function public.cap_membre_repondre(p_reunion uuid, p_reponse text)
returns json language plpgsql security definer set search_path = public as $$
declare v_mb uuid := cap_membre_id(); r reunions%rowtype;
begin
  if v_mb is null then raise exception 'aucune fiche membre liée'; end if;
  if p_reponse not in ('oui','non') then raise exception 'réponse inconnue'; end if;
  select * into r from reunions where id = p_reunion;
  if not found then raise exception 'réunion introuvable'; end if;
  if not exists (select 1 from membres where id = v_mb and club_id = r.club_id) then raise exception 'cette réunion n''est pas celle de ton groupe'; end if;
  if r.statut = 'annulee' then raise exception 'cette réunion est annulée'; end if;
  if r.date < current_date then raise exception 'cette réunion est passée'; end if;
  insert into reunion_reponses (reunion_id, membre_id, reponse) values (p_reunion, v_mb, p_reponse)
  on conflict (reunion_id, membre_id) do update set reponse = excluded.reponse, maj_le = now();
  return json_build_object('ma_reponse', p_reponse,
    'viennent', (select count(*) from reunion_reponses where reunion_id = p_reunion and reponse = 'oui'),
    'absents', (select count(*) from reunion_reponses where reunion_id = p_reunion and reponse = 'non'));
end $$;
grant execute on function public.cap_membre_repondre(uuid, text) to authenticated;

-- La vue du groupe porte la réponse du membre et les totaux sur la prochaine réunion.
create or replace function public.cap_groupe_vue(p_club uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_club uuid := p_club; v_mb uuid := cap_membre_id(); v_prochaine uuid; v_res json;
begin
  if v_club is null then select club_id into v_club from membres where id = v_mb; end if;
  if v_club is null or not cap_peut_voir_groupe(v_club) then raise exception 'accès refusé'; end if;
  select r.id into v_prochaine from reunions r where r.club_id = v_club and r.date >= current_date and r.statut <> 'annulee'
   order by r.date, r.heure nulls last limit 1;
  select json_build_object(
    'club', (select json_build_object('id', c.id, 'nom', c.nom, 'ville', c.ville, 'statut', c.statut, 'objectif', c.objectif,
        'animateur', a.nom, 'rythme_jour', c.rythme_jour, 'rythme_rang', c.rythme_rang, 'rythme_pas', c.rythme_pas,
        'heure', c.heure_habituelle, 'lieu', l.nom, 'metiers_recherches', coalesce(c.metiers_recherches, '[]'::jsonb))
      from clubs c left join animateurs a on a.id = c.animateur_id left join lieux l on l.id = c.lieu_habituel_id where c.id = v_club),
    'prochaine', (select json_build_object('id', r.id, 'date', r.date, 'heure', r.heure, 'type', r.type, 'format', r.format, 'theme', r.theme, 'lieu', l.nom,
        'adresse', l.adresse, 'ville', coalesce(l.ville, c.ville), 'invites', (select count(*) from invites i where i.reunion_id = r.id),
        'ma_reponse', (select rr.reponse from reunion_reponses rr where rr.reunion_id = r.id and rr.membre_id = v_mb),
        'viennent', (select count(*) from reunion_reponses rr where rr.reunion_id = r.id and rr.reponse = 'oui'),
        'absents', (select count(*) from reunion_reponses rr where rr.reunion_id = r.id and rr.reponse = 'non'))
      from reunions r join clubs c on c.id = r.club_id left join lieux l on l.id = r.lieu_id where r.id = v_prochaine),
    'reunions', (select json_build_object('a_venir', count(*) filter (where r.date >= current_date and r.statut <> 'annulee'),
        'faites_annee', count(*) filter (where r.statut = 'realisee' and r.date >= date_trunc('year', now())),
        'presents_moyen', round(avg(r.presents) filter (where r.statut = 'realisee' and r.presents is not null)))
      from reunions r where r.club_id = v_club),
    'membres', (select coalesce(json_agg(json_build_object('id', m.id, 'nom', m.nom,
        'metier', cap_metier_membre(m.infos, m.specialite), 'entreprise', m.infos->>'ent_nom',
        'photo', m.photo_url, 'inscrit', m.user_id is not null, 'moi', m.id = v_mb) order by m.num nulls last, m.nom), '[]')
      from membres m where m.club_id = v_club),
    'invites', (select coalesce(json_agg(json_build_object('id', i.id, 'nom', i.nom, 'entreprise', i.entreprise, 'metier', i.metier,
        'tel', i.tel, 'email', i.email, 'statut', i.statut, 'invite_par', coalesce(pm.nom, i.invite_par)) order by i.nom), '[]')
      from invites i left join membres pm on pm.id = i.propose_par where i.reunion_id = v_prochaine),
    'recos', (select coalesce(json_agg(x order by x.cree_le desc), '[]') from (
        select r.id, d.nom de_nom, b.nom a_nom, r.statut, r.montant, r.cree_le, r.maj_le
        from recommandations r left join membres d on d.id = r.de left join membres b on b.id = r.a
        where r.club_id = v_club order by r.cree_le desc limit 8) x),
    'messages', (select coalesce(json_agg(x order by x.cree_le), '[]') from (
        select g.id, g.auteur_nom, g.membre_id, g.texte, g.cree_le from messages_groupe g
        where g.club_id = v_club order by g.cree_le desc limit 4) x),
    'chiffres', cap_tableau_club(v_club, v_mb),
    'vue_equipe', v_mb is null or not exists (select 1 from membres where id = v_mb and club_id = v_club)) into v_res;
  return v_res;
end $function$;
