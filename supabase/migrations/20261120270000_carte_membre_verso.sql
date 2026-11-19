-- v1.87.0 — verso de la carte de visite : spécialité, contacts recherchés, loisirs (listés par JB). Toujours aucune donnée légale.
create or replace function public.cap_carte_membre(p_jeton uuid) returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select jsonb_build_object('nom', m.nom, 'fonction', m.infos->>'m_fonction', 'metier', cap_metier_membre(m.infos, m.specialite),
    'entreprise', m.infos->>'ent_nom', 'groupe', c.nom, 'ville', coalesce(nullif(m.infos->>'ent_ville', ''), c.ville),
    'photo', m.photo_url, 'logo', m.logo_url,
    'presentation', coalesce(nullif(m.presentation, ''), nullif(m.infos->>'ent_activite', '')),
    'specialite', nullif(m.specialite_detail, ''), 'cherche', nullif(m.cherche, ''), 'loisirs', nullif(m.loisirs, ''),
    'site', coalesce(nullif(m.site, ''), nullif(m.infos->>'ent_web', '')), 'linkedin', m.linkedin,
    'telephone', case when m.tel_visible then nullif(m.infos->>'m_tel', '') end,
    'email', case when m.tel_visible then nullif(m.infos->>'m_email', '') end,
    'club_id', m.club_id)
  from membres m left join clubs c on c.id = m.club_id
  where p_jeton is not null and m.carte_jeton = p_jeton
$function$;
