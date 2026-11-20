-- v1.113 : suivi des points sur activité (PSA). Qui a calé le sien ce mois-ci, quelle région n'a pas de créneau ouvert,
-- relance d'un animateur, et rappel automatique chaque lundi matin.
-- Règle : un animateur est « à caler » s'il n'a ni PSA à venir, ni PSA tenu depuis le début du mois.

-- Calcul interne (jamais appelé seul depuis l'appli : il exige le drapeau posé par les fonctions ci-dessous, ou le planificateur).
create or replace function public.cap_psa_suivi_calc() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare debut_mois timestamptz := date_trunc('month', now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
begin
  if coalesce(current_setting('cap.psa_interne', true), '') <> '1' and coalesce(current_setting('request.jwt.claims', true), '') <> '' then
    raise exception 'réservé';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'zone_id', z.id, 'nom', z.nom,
      'directeurs', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nom', coalesce(a.nom, p.nom)) order by p.nom)
                                from profiles p left join animateurs a on a.id = p.animateur_id
                               where p.zone_id = z.id and p.role in ('directeur', 'superadmin')), '[]'::jsonb),
      'creneaux', (select count(*) from psa_creneaux c where c.zone_id = z.id and c.debut > now()),
      'libres', (select count(*) from psa_creneaux c where c.zone_id = z.id and c.debut > now() and c.reserve_par is null and c.reserve_lien is null),
      'animateurs', coalesce((
        select jsonb_agg(jsonb_build_object('id', x.id, 'nom', x.nom, 'groupes', x.groupes, 'compte', x.compte, 'profils', x.profils,
                 'prochain', x.prochain, 'dernier', x.dernier,
                 'a_caler', x.prochain is null and (x.dernier is null or x.dernier < debut_mois)) order by x.nom)
        from (
          select a.id, a.nom,
                 (select jsonb_agg(c.nom order by c.nom) from clubs c where c.animateur_id = a.id) as groupes,
                 exists (select 1 from profiles p where p.animateur_id = a.id) as compte,
                 coalesce((select jsonb_agg(p.id) from profiles p where p.animateur_id = a.id), '[]'::jsonb) as profils,
                 (select min(s.debut) from psa_creneaux s where s.debut > now()
                    and (s.reserve_par in (select p.id from profiles p where p.animateur_id = a.id)
                      or s.reserve_lien in (select l.jeton from psa_liens l where l.animateur_id = a.id))) as prochain,
                 (select max(s.debut) from psa_creneaux s where s.debut <= now()
                    and (s.reserve_par in (select p.id from profiles p where p.animateur_id = a.id)
                      or s.reserve_lien in (select l.jeton from psa_liens l where l.animateur_id = a.id))) as dernier
            from animateurs a
           where exists (select 1 from clubs c where c.animateur_id = a.id
                           and lower(unaccent_simple(c.ville)) in (select lower(unaccent_simple(v)) from unnest(z.villes) v))
             and not exists (select 1 from profiles p where p.animateur_id = a.id and p.role in ('superadmin', 'directeur', 'directeur_national'))
        ) x), '[]'::jsonb)) order by z.nom)
    from zones z), '[]'::jsonb);
end $$;

-- Ce que voit l'appelant : tout le réseau (super admin, direction nationale), sa région (directeur), ou sa seule ligne (animateur).
create or replace function public.cap_psa_suivi() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r text := coalesce(cap_role(), ''); me uuid := cap_uid(); z uuid; an uuid; t jsonb;
begin
  if me is null or not cap_est_equipe() or r in ('', 'visiteur') then raise exception 'Réservé à l''équipe'; end if;
  select zone_id, animateur_id into z, an from profiles where id = me;
  perform set_config('cap.psa_interne', '1', true);
  t := cap_psa_suivi_calc();
  perform set_config('cap.psa_interne', '', true);
  if r in ('superadmin', 'directeur_national') then return jsonb_build_object('portee', 'national', 'regions', t); end if;
  if r = 'directeur' then
    return jsonb_build_object('portee', 'region', 'regions', coalesce((select jsonb_agg(x) from jsonb_array_elements(t) x where (x->>'zone_id')::uuid = z), '[]'::jsonb));
  end if;
  return jsonb_build_object('portee', 'moi', 'regions', coalesce((
    select jsonb_agg(jsonb_set(x, '{animateurs}', coalesce((select jsonb_agg(y - 'profils') from jsonb_array_elements(x->'animateurs') y where (y->>'id')::uuid = an), '[]'::jsonb)))
      from jsonb_array_elements(t) x
     where exists (select 1 from jsonb_array_elements(x->'animateurs') y where (y->>'id')::uuid = an)), '[]'::jsonb));
end $$;

-- Relancer un animateur : notification sur son téléphone (s'il a un compte et a activé les notifications).
create or replace function public.cap_psa_relancer(p_anim uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ids jsonb; qui text;
begin
  if auth.uid() is null or not cap_psa_gere() then raise exception 'Réservé aux directeurs'; end if;
  if coalesce(cap_role(), '') = 'directeur' and not exists (
       select 1 from clubs c join zones z on z.id = (select zone_id from profiles where id = auth.uid())
        where c.animateur_id = p_anim and lower(unaccent_simple(c.ville)) in (select lower(unaccent_simple(v)) from unnest(z.villes) v)) then
    raise exception 'Cet animateur n''est pas dans ta région';
  end if;
  select coalesce(jsonb_agg(id), '[]'::jsonb) into ids from profiles where animateur_id = p_anim;
  if jsonb_array_length(ids) = 0 then return jsonb_build_object('ok', true, 'compte', false); end if;
  select coalesce(a.nom, p.nom) into qui from profiles p left join animateurs a on a.id = p.animateur_id where p.id = auth.uid();
  perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
    body := jsonb_build_object('pour', ids, 'titre', '📅 Point sur activité à caler', 'corps',
      coalesce(qui, 'Ton directeur') || ' te demande de choisir ton créneau de PSA.', 'url', '/?psa=1', 'tag', 'psa-relance'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-suivi-jeton', (select decrypted_secret from vault.decrypted_secrets where name = 'national_suivi_jeton')),
    timeout_milliseconds := 20000);
  return jsonb_build_object('ok', true, 'compte', true);
end $$;

-- Rappel du lundi : aux animateurs sans PSA ce mois-ci, et aux directeurs dont la région n'a plus de créneau libre.
create or replace function public.cap_psa_alertes_lancer() returns jsonb
language plpgsql security definer set search_path = public as $$
declare t jsonb; x jsonb; ids jsonb; dirs jsonb; n int; na int := 0; nd int := 0; ent jsonb;
begin
  if coalesce(current_setting('request.jwt.claims', true), '') <> '' and coalesce(cap_role(), '') <> 'superadmin' then raise exception 'réservé au super admin'; end if;
  perform set_config('cap.psa_interne', '1', true);
  t := cap_psa_suivi_calc();
  perform set_config('cap.psa_interne', '', true);
  ent := jsonb_build_object('Content-Type', 'application/json', 'x-suivi-jeton', (select decrypted_secret from vault.decrypted_secrets where name = 'national_suivi_jeton'));
  for x in select * from jsonb_array_elements(t) loop
    select count(*), coalesce(jsonb_agg(p), '[]'::jsonb) into n, ids
      from jsonb_array_elements(x->'animateurs') y, jsonb_array_elements(y->'profils') p where (y->>'a_caler')::boolean;
    select count(*) into n from jsonb_array_elements(x->'animateurs') y where (y->>'a_caler')::boolean;
    if n = 0 then continue; end if;
    if (x->>'libres')::int > 0 and jsonb_array_length(ids) > 0 then
      na := na + jsonb_array_length(ids);
      perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
        body := jsonb_build_object('pour', ids, 'titre', '📅 Point sur activité à caler', 'corps', 'Tu n''as pas encore de PSA ce mois-ci. Choisis ton créneau.', 'url', '/?psa=1', 'tag', 'psa-rappel'),
        headers := ent, timeout_milliseconds := 20000);
    end if;
    if (x->>'libres')::int = 0 then
      select coalesce(jsonb_agg(d->'id'), '[]'::jsonb) into dirs from jsonb_array_elements(x->'directeurs') d;
      if jsonb_array_length(dirs) = 0 then select coalesce(jsonb_agg(id), '[]'::jsonb) into dirs from profiles where role = 'directeur_national'; end if;
      if jsonb_array_length(dirs) > 0 then
        nd := nd + 1;
        perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
          body := jsonb_build_object('pour', dirs, 'titre', '📅 PSA : aucun créneau ouvert', 'corps',
            (x->>'nom') || ' : ' || n || ' animateur' || case when n > 1 then 's' else '' end || ' sans PSA ce mois-ci et aucun créneau libre. Ouvre des créneaux.', 'url', '/?psa=1', 'tag', 'psa-region'),
          headers := ent, timeout_milliseconds := 20000);
      end if;
    end if;
  end loop;
  return jsonb_build_object('animateurs', na, 'regions', nd);
end $$;

select cron.schedule('psa-alertes', '30 8 * * 1', $c$select public.cap_psa_alertes_lancer()$c$);
