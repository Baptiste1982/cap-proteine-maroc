-- v1.17.0 : « Voir comme » (super admin). L'en-tête HTTP x-cap-voir = 'u:<compte>' (animateur, directeur…) ou 'm:<fiche membre>'
-- fait répondre la base comme si ce compte / ce membre était connecté. Pris en compte SEULEMENT si la vraie personne connectée
-- est superadmin, et en LECTURE SEULE : toute écriture (PATCH, DELETE, POST sur une table, appel d'une fonction hors liste
-- de lecture) est refusée tant que l'en-tête est présent.
create or replace function public.cap_voir() returns text
language plpgsql stable security definer set search_path = public as $$
declare v text; p text;
begin
  if auth.uid() is null then return null; end if;
  begin v := nullif(current_setting('request.headers', true)::json->>'x-cap-voir', ''); exception when others then return null; end;
  if v is null or v !~ '^[um]:[0-9a-f-]{36}$' then return null; end if;
  if not exists (select 1 from profiles where id = auth.uid() and role = 'superadmin') then return null; end if;
  p := coalesce(current_setting('request.path', true), '');
  if coalesce(current_setting('request.method', true), 'GET') not in ('GET', 'HEAD')
     and p !~ '^/rpc/(cap_annuaire|cap_annuaire_fiche|cap_groupe_vue|cap_membre_tableau|cap_tableau_club|cap_membre_prochaine_reunion|cap_membre_invites_groupe|cap_membre_mes_invites|cap_membre_recos_club|cap_membre_id|cap_role|cap_peut_voir_groupe|cap_docs_profil|cap_zone_villes|cap_membres_connexions|cap_qui_connecte|cap_equipe_etat|cap_acces_equipe|cap_voir_qui)$' then
    raise exception 'Aperçu en lecture seule : rien ne peut être modifié.';
  end if;
  return v;
end $$;

create or replace function public.cap_uid() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v text := cap_voir();
begin
  if v is null then return auth.uid(); end if;
  if v like 'u:%' then return substr(v, 3)::uuid; end if;
  return (select user_id from membres where id = substr(v, 3)::uuid);
end $$;

create or replace function public.cap_membre_id() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v text := cap_voir();
begin
  if v like 'm:%' then return substr(v, 3)::uuid; end if;
  return (select id from membres where user_id = cap_uid() limit 1);
end $$;

-- Qui est affiché (bandeau de l'aperçu) : réservé au superadmin.
create or replace function public.cap_voir_qui() returns json
language plpgsql stable security definer set search_path = public as $$
declare v text := cap_voir();
begin
  if v is null then return null; end if;
  if v like 'u:%' then return (select json_build_object('type','compte','id',p.id,'nom',p.nom,'role',p.role,'animateur_id',p.animateur_id,'zone_id',p.zone_id) from profiles p where p.id = substr(v,3)::uuid); end if;
  return (select json_build_object('type','membre','id',m.id,'nom',m.nom,'club_id',m.club_id) from membres m where m.id = substr(v,3)::uuid);
end $$;

-- Les fonctions qui identifiaient la personne par auth.uid() passent par cap_uid() / cap_membre_id().
do $$
declare f record; d text;
begin
  for f in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
    ('cap_animateur_id','cap_annuaire','cap_annuaire_fiche','cap_doc_acces_ok','cap_docs_profil','cap_est_equipe','cap_gere_documents',
     'cap_groupe_acces','cap_groupe_ecrire','cap_membre_fiche_maj','cap_membre_prochaine_reunion','cap_membre_profil',
     'cap_membre_proposer_invite','cap_membre_reco_donner','cap_membre_reco_donner_fiche','cap_membre_recos_club',
     'cap_peut_voir_groupe','cap_role','cap_zone_villes')
  loop
    d := pg_get_functiondef(f.oid);
    d := replace(d, 'm.user_id = auth.uid()', 'm.id = cap_membre_id()');
    d := replace(d, 'from membres where user_id = auth.uid()', 'from membres where id = cap_membre_id()');
    d := replace(d, 'where user_id = auth.uid()', 'where id = cap_membre_id()');
    d := replace(d, 'auth.uid()', 'cap_uid()');
    execute d;
  end loop;
end $$;

alter policy profiles_self_read on public.profiles using (id = cap_uid() or cap_role() = 'superadmin');
alter policy documents_acces_lire on public.documents_acces using (cap_gere_documents() or user_id = cap_uid());
