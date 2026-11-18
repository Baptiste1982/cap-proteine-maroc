-- v1.68.0 — décisions de JB du 19/11 :
--  · un membre peut s'inscrire à la réunion de n'importe quel groupe du réseau ; inscrit, il voit les invités,
--    les membres du groupe et les chiffres de la quinzaine (jamais de coordonnées) ;
--  · la « quinzaine » se compte depuis la dernière réunion du groupe (sinon 14 jours).

-- Début de la quinzaine d'un groupe : date de sa dernière réunion (ni annulée, ni archivée) avant p_avant,
-- si elle a moins de 45 jours ; sinon 14 jours avant p_avant.
create or replace function public.cap_quinzaine_debut(p_club uuid, p_avant date default current_date)
 returns date language sql stable security definer set search_path to 'public'
as $function$
  select case when cap_est_equipe() or cap_membre_id() is not null then
    coalesce((select max(r.date) from reunions r where r.club_id = p_club and r.date < p_avant and r.date >= p_avant - 45
              and r.statut <> 'annulee' and r.archivee_le is null), p_avant - 14) end
$function$;

create or replace function public.cap_groupe_semaine(p_club uuid default null::uuid)
 returns json language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_club uuid := p_club; v_mb uuid := cap_membre_id(); v_res json; v_du date; v_reu boolean;
begin
  if v_club is null then select club_id into v_club from membres where id = v_mb; end if;
  if v_club is null or not cap_peut_voir_groupe(v_club) then raise exception 'accès refusé'; end if;
  v_du := cap_quinzaine_debut(v_club, current_date);
  v_reu := exists (select 1 from reunions r where r.club_id = v_club and r.date = v_du and r.statut <> 'annulee' and r.archivee_le is null);
  select json_build_object(
    'jours', current_date - v_du, 'du', v_du, 'au', current_date, 'depuis_reunion', v_reu,
    'recos', count(*) filter (where r.cree_le >= v_du),
    'affaires', count(*) filter (where r.statut = 'signee' and r.maj_le >= v_du),
    'ca', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= v_du), 0),
    'recos_avant', count(*) filter (where r.cree_le >= v_du - 14 and r.cree_le < v_du),
    'ca_avant', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= v_du - 14 and r.maj_le < v_du), 0))
  into v_res from recommandations r where r.club_id = v_club;
  return v_res;
end $function$;

-- Équipe : qui est prévu à une réunion (groupe visible, ou inscription « Je viens »).
create or replace function public.cap_reunion_prevus(p_reunion uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_club uuid; v_date date; v_du date;
begin
  if not cap_est_equipe() or coalesce(cap_role(),'') = 'visiteur' then raise exception 'réservé à l''équipe'; end if;
  select club_id, date into v_club, v_date from reunions where id = p_reunion;
  if v_club is null then return jsonb_build_object('acces', false); end if;
  if not (cap_can_see_club(v_club) or exists (select 1 from invites i where i.reunion_id = p_reunion and i.profil_id = cap_uid())) then
    return jsonb_build_object('acces', false);
  end if;
  v_du := cap_quinzaine_debut(v_club, least(v_date, current_date));
  return jsonb_build_object('acces', true,
    'invites', (select coalesce(jsonb_agg(jsonb_build_object('nom', i.nom, 'entreprise', coalesce(i.entreprise,''), 'metier', coalesce(i.metier,''), 'statut', i.statut, 'par', coalesce(i.invite_par,'')) order by i.created_at), '[]'::jsonb)
                from invites i where i.reunion_id = p_reunion and i.profil_id is null),
    'equipe', (select coalesce(jsonb_agg(i.nom order by i.created_at), '[]'::jsonb) from invites i where i.reunion_id = p_reunion and i.profil_id is not null),
    'membres', (select coalesce(jsonb_agg(jsonb_build_object('nom', mb.nom, 'metier', coalesce(cap_metier_membre(mb.infos, mb.specialite),'')) order by mb.nom), '[]'::jsonb)
                from reunion_reponses rr join membres mb on mb.id = rr.membre_id where rr.reunion_id = p_reunion and rr.reponse = 'oui'),
    'groupe', (select coalesce(jsonb_agg(jsonb_build_object('nom', mb.nom, 'metier', coalesce(cap_metier_membre(mb.infos, mb.specialite),''), 'entreprise', coalesce(mb.infos->>'ent_nom',''),
                  'vient', (select rr.reponse from reunion_reponses rr where rr.reunion_id = p_reunion and rr.membre_id = mb.id)) order by mb.num), '[]'::jsonb)
                from membres mb where mb.club_id = v_club),
    'quinzaine', (select jsonb_build_object('du', v_du,
                  'depuis_reunion', exists (select 1 from reunions x where x.club_id = v_club and x.date = v_du and x.statut <> 'annulee' and x.archivee_le is null),
                  'recos', count(*) filter (where r.cree_le >= v_du),
                  'affaires', count(*) filter (where r.statut = 'signee' and r.maj_le >= v_du),
                  'ca', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= v_du), 0))
                from recommandations r where r.club_id = v_club));
end $function$;

-- Équipe : les réponses des membres à une réunion, avec leur nom et leur groupe (un membre d'un autre groupe peut venir).
create or replace function public.cap_reunion_reponses(p_reunion uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_club uuid;
begin
  if not cap_est_equipe() or coalesce(cap_role(),'') = 'visiteur' then raise exception 'réservé à l''équipe'; end if;
  select club_id into v_club from reunions where id = p_reunion;
  if v_club is null or not (cap_can_see_club(v_club) or exists (select 1 from invites i where i.reunion_id = p_reunion and i.profil_id = cap_uid())) then
    return '[]'::jsonb;
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('nom', mb.nom, 'reponse', rr.reponse, 'groupe', c.nom, 'autre_groupe', mb.club_id is distinct from v_club) order by rr.maj_le), '[]'::jsonb)
          from reunion_reponses rr join membres mb on mb.id = rr.membre_id left join clubs c on c.id = mb.club_id where rr.reunion_id = p_reunion);
end $function$;

-- Membre : répondre à la réunion de n'importe quel groupe du réseau (avant : seulement celle de son groupe).
create or replace function public.cap_membre_repondre(p_reunion uuid, p_reponse text)
 returns json language plpgsql security definer set search_path to 'public'
as $function$
declare v_mb uuid := cap_membre_id(); r reunions%rowtype;
begin
  if v_mb is null then raise exception 'aucune fiche membre liée'; end if;
  if p_reponse not in ('oui','non') then raise exception 'réponse inconnue'; end if;
  select * into r from reunions where id = p_reunion;
  if not found then raise exception 'réunion introuvable'; end if;
  if r.statut = 'annulee' then raise exception 'cette réunion est annulée'; end if;
  if r.date < current_date then raise exception 'cette réunion est passée'; end if;
  insert into reunion_reponses (reunion_id, membre_id, reponse) values (p_reunion, v_mb, p_reponse)
  on conflict (reunion_id, membre_id) do update set reponse = excluded.reponse, maj_le = now();
  return json_build_object('ma_reponse', p_reponse,
    'viennent', (select count(*) from reunion_reponses where reunion_id = p_reunion and reponse = 'oui'),
    'absents', (select count(*) from reunion_reponses where reunion_id = p_reunion and reponse = 'non'));
end $function$;

-- Membre : les réunions à venir de tout le réseau.
create or replace function public.cap_membre_reunions_reseau()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_mb uuid := cap_membre_id(); v_club uuid;
begin
  if v_mb is null then raise exception 'aucune fiche membre liée'; end if;
  select club_id into v_club from membres where id = v_mb;
  return (select coalesce(jsonb_agg(x.j order by x.d, x.h nulls last), '[]'::jsonb) from (
    select r.date d, r.heure h, jsonb_build_object('id', r.id, 'date', r.date, 'heure', r.heure, 'type', r.type, 'format', r.format, 'theme', r.theme,
      'club', c.nom, 'club_id', c.id, 'ville', coalesce(l.ville, c.ville), 'lieu', l.nom, 'adresse', l.adresse, 'lien_carte', l.lien_carte,
      'mon_groupe', c.id = v_club,
      'ma_reponse', (select rr.reponse from reunion_reponses rr where rr.reunion_id = r.id and rr.membre_id = v_mb),
      'viennent', (select count(*) from reunion_reponses rr where rr.reunion_id = r.id and rr.reponse = 'oui')) j
    from reunions r join clubs c on c.id = r.club_id left join lieux l on l.id = r.lieu_id
    where r.date >= current_date and r.statut <> 'annulee' and r.archivee_le is null
    order by r.date, r.heure nulls last limit 60) x);
end $function$;

-- Membre : qui est prévu à une réunion (celle de son groupe, ou une réunion où il a répondu « Je viens »).
create or replace function public.cap_membre_reunion_prevus(p_reunion uuid)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_mb uuid := cap_membre_id(); v_club uuid; v_date date; v_du date;
begin
  if v_mb is null then raise exception 'aucune fiche membre liée'; end if;
  select club_id, date into v_club, v_date from reunions where id = p_reunion;
  if v_club is null then return jsonb_build_object('acces', false); end if;
  if not (exists (select 1 from membres where id = v_mb and club_id = v_club)
       or exists (select 1 from reunion_reponses rr where rr.reunion_id = p_reunion and rr.membre_id = v_mb and rr.reponse = 'oui')) then
    return jsonb_build_object('acces', false);
  end if;
  v_du := cap_quinzaine_debut(v_club, least(v_date, current_date));
  return jsonb_build_object('acces', true,
    'invites', (select coalesce(jsonb_agg(jsonb_build_object('nom', i.nom, 'entreprise', coalesce(i.entreprise,''), 'metier', coalesce(i.metier,''), 'par', coalesce(i.invite_par,'')) order by i.created_at), '[]'::jsonb)
                from invites i where i.reunion_id = p_reunion and i.profil_id is null),
    'groupe', (select coalesce(jsonb_agg(jsonb_build_object('id', mb.id, 'nom', mb.nom, 'metier', coalesce(cap_metier_membre(mb.infos, mb.specialite),''), 'entreprise', coalesce(mb.infos->>'ent_nom',''),
                  'vient', (select rr.reponse from reunion_reponses rr where rr.reunion_id = p_reunion and rr.membre_id = mb.id)) order by mb.num), '[]'::jsonb)
                from membres mb where mb.club_id = v_club and (mb.annuaire_visible or mb.id = v_mb)),
    'visiteurs', (select coalesce(jsonb_agg(jsonb_build_object('nom', mb.nom, 'groupe', c.nom) order by mb.nom), '[]'::jsonb)
                from reunion_reponses rr join membres mb on mb.id = rr.membre_id left join clubs c on c.id = mb.club_id
                where rr.reunion_id = p_reunion and rr.reponse = 'oui' and mb.club_id is distinct from v_club),
    'quinzaine', (select jsonb_build_object('du', v_du,
                  'depuis_reunion', exists (select 1 from reunions x where x.club_id = v_club and x.date = v_du and x.statut <> 'annulee' and x.archivee_le is null),
                  'recos', count(*) filter (where r.cree_le >= v_du),
                  'affaires', count(*) filter (where r.statut = 'signee' and r.maj_le >= v_du),
                  'ca', coalesce(sum(r.montant) filter (where r.statut = 'signee' and r.maj_le >= v_du), 0))
                from recommandations r where r.club_id = v_club));
end $function$;

-- Aperçu « voir comme » : les nouvelles lectures sont permises.
create or replace function public.cap_voir()
 returns text language plpgsql stable security definer set search_path to 'public'
as $function$
declare v text; p text;
begin
  if auth.uid() is null then return null; end if;
  begin v := nullif(current_setting('request.headers', true)::json->>'x-cap-voir', ''); exception when others then return null; end;
  if v is null or v !~ '^[um]:[0-9a-f-]{36}$' then return null; end if;
  if not exists (select 1 from profiles where id = auth.uid() and role = 'superadmin') then return null; end if;
  p := coalesce(current_setting('request.path', true), '');
  if coalesce(current_setting('request.method', true), 'GET') not in ('GET', 'HEAD')
     and p !~ '^/rpc/(cap_annuaire|cap_annuaire_fiche|cap_annuaire_contacts|cap_annuaire_regions|cap_groupe_vue|cap_groupe_semaine|cap_membre_tableau|cap_tableau_club|cap_membre_prochaine_reunion|cap_membre_invites_groupe|cap_membre_mes_invites|cap_membre_recos_club|cap_membre_id|cap_role|cap_peut_voir_groupe|cap_docs_profil|cap_zone_villes|cap_membres_connexions|cap_qui_connecte|cap_equipe_etat|cap_acces_equipe|cap_voir_qui|cap_membre_moi|cap_membre_reunions_reseau|cap_membre_reunion_prevus|cap_reunion_prevus|cap_reunion_reponses|cap_quinzaine_debut)$' then
    raise exception 'Aperçu en lecture seule : rien ne peut être modifié.';
  end if;
  return v;
end $function$;
