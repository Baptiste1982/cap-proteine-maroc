-- v1.17.0 : lecture de « qui suis-je » pour l'espace membre, sans rien relier (utilisée en aperçu « Voir comme un membre »).
create or replace function public.cap_membre_moi() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('statut', 'ok', 'id', m.id, 'nom', m.nom,
    'club', c.nom, 'ville', c.ville, 'cherche', m.cherche, 'tel_visible', m.tel_visible, 'annuaire_visible', m.annuaire_visible,
    'metier', coalesce(nullif(m.infos->>'metier', ''), m.specialite), 'entreprise', m.infos->>'ent_nom')
  from membres m left join clubs c on c.id = m.club_id where m.id = cap_membre_id()
$$;
do $$ declare d text; begin
  d := pg_get_functiondef('public.cap_voir()'::regprocedure);
  d := replace(d, '|cap_voir_qui)$', '|cap_voir_qui|cap_membre_moi|cap_membre_invites_groupe)$');
  execute d;
end $$;
