-- v1.130 : un titre affiché à la place du libellé du rôle (ex. « Office Manager »). Les droits restent ceux du rôle.
alter table public.profiles add column if not exists titre text;

create or replace function public.cap_journal() returns trigger
language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); j jsonb; o jsonb; d jsonb := '{}'::jsonb; k text; a text; lib text; cid uuid; v text; nomq text; roleq text;
  bruit text[] := array['vu_le','notifie_le','notifiee_le','attribue_notifie_le','suivi_notifie','relance_notif_le','rappel_membres_le','sheet_le','sheet_err','sheet_vu_le','attribue_lu_le','updated_at','maj_le','vues'];
  lourd text[] := array['compte_rendu','presentation','national','photo','photo_url','logo_url','infos','data','profil','metiers_recherches'];
begin
  begin
    if tg_op = 'DELETE' then j := to_jsonb(old); a := 'retrait';
    elsif tg_op = 'INSERT' then j := to_jsonb(new); a := 'ajout';
    else j := to_jsonb(new); o := to_jsonb(old); a := 'modif'; end if;
    if u is null and not (tg_table_name = 'adhesions' and tg_op = 'INSERT') then return null; end if;
    if tg_op = 'UPDATE' then
      for k in select key from jsonb_each(j) loop
        if k = any(bruit) or (tg_table_name = 'clubs' and k = 'statut') then continue; end if;
        if (j -> k) is distinct from (o -> k) then
          if k = any(lourd) or length(coalesce(j ->> k, '')) > 300 or length(coalesce(o ->> k, '')) > 300
            then d := d || jsonb_build_object(k, jsonb_build_array('…', '…'));
            else d := d || jsonb_build_object(k, jsonb_build_array(o -> k, j -> k)); end if;
        end if;
      end loop;
      if d = '{}'::jsonb then return null; end if;
    end if;
    case tg_table_name
      when 'clubs' then lib := j ->> 'nom'; cid := (j ->> 'id')::uuid; v := j ->> 'ville';
      when 'reunions' then cid := (j ->> 'club_id')::uuid; lib := coalesce(j ->> 'format', j ->> 'type') || ' du ' || to_char((j ->> 'date')::date, 'DD/MM/YYYY');
      when 'membres' then lib := j ->> 'nom'; cid := (j ->> 'club_id')::uuid;
      when 'invites' then lib := j ->> 'nom'; select r.club_id into cid from reunions r where r.id = (j ->> 'reunion_id')::uuid;
      when 'adhesions' then lib := coalesce(nullif(j ->> 'membre_nom', ''), j ->> 'entreprise');
        begin cid := (j ->> 'ref')::uuid; exception when others then cid := null; end;
      when 'recommandations' then lib := coalesce(nullif(j ->> 'objet', ''), 'Recommandation'); cid := (j ->> 'club_id')::uuid;
      when 'lieux', 'animateurs', 'leads' then lib := j ->> 'nom'; v := j ->> 'ville';
      when 'zones' then lib := j ->> 'nom';
      when 'psa_creneaux' then lib := 'PSA du ' || to_char((j ->> 'debut')::timestamptz at time zone 'Africa/Casablanca', 'DD/MM/YYYY HH24:MI');
      when 'membre_documents' then select m.nom, m.club_id into lib, cid from membres m where m.id = (j ->> 'membre_id')::uuid;
        lib := coalesce(j ->> 'nature', j ->> 'type', 'pièce') || coalesce(' · ' || lib, '');
      when 'presences' then select m.nom, m.club_id into lib, cid from membres m where m.id = (j ->> 'membre_id')::uuid;
      else lib := coalesce(j ->> 'titre', j ->> 'nom', j ->> 'nom_fichier');
    end case;
    if cid is not null and v is null then select c.ville into v from clubs c where c.id = cid; end if;
    select p.nom, coalesce(nullif(p.titre, ''), p.role) into nomq, roleq from profiles p where p.id = u;
    if nomq is null and u is not null then select m.nom, 'membre' into nomq, roleq from membres m where m.user_id = u limit 1; end if;
    insert into journal (par, par_nom, role, action, objet, objet_id, libelle, club_id, ville, detail)
    values (u, coalesce(nomq, case when u is null then 'Formulaire public' else 'Compte inconnu' end), coalesce(roleq, case when u is null then 'public' end),
            a, tg_table_name, j ->> 'id', left(lib, 160), cid, v, nullif(d, '{}'::jsonb));
  exception when others then null;
  end;
  return null;
end $$;

create or replace function public.cap_journal_connexion() returns void
language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); n text; r text;
begin
  if u is null then return; end if;
  select p.nom, coalesce(nullif(p.titre, ''), p.role) into n, r from profiles p where p.id = u;
  if n is null then return; end if;
  if exists (select 1 from journal where par = u and action = 'connexion' and le > now() - interval '30 minutes') then return; end if;
  insert into journal (par, par_nom, role, action, objet, libelle) values (u, n, r, 'connexion', 'crm', 'Connexion au CRM');
end $$;

-- Les titres, pour les afficher à la place du rôle (équipe seulement).
create or replace function public.cap_titres() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.cap_est_equipe() then coalesce((select jsonb_object_agg(p.id, p.titre) from profiles p where nullif(p.titre, '') is not null), '{}'::jsonb) else '{}'::jsonb end
$$;
