-- v1.31.0 — Ce qu'un membre voit d'un autre membre (règle JB du 17/11/2026) : les informations de base seulement
-- (photo, logo, présentation, site, téléphone, e-mail). Jamais les données légales (RC, ICE, patente, capital, adresse
-- de facturation…) : elles restent dans membres.infos, lisibles par la direction et l'animateur du groupe uniquement.
-- Les coordonnées sont partagées par défaut ; chaque membre peut les masquer dans son profil (tel_visible).
alter table public.membres alter column tel_visible set default true;
update public.membres set tel_visible = true where tel_visible is distinct from true;

create or replace function public.cap_annuaire_contacts()
returns table (id uuid, email text, telephone text)
language sql stable security definer set search_path to 'public' as $$
  select m.id,
         case when m.tel_visible or m.id = cap_membre_id() then nullif(m.infos->>'m_email', '') end,
         case when m.tel_visible or m.id = cap_membre_id() then nullif(m.infos->>'m_tel', '') end
  from membres m
  where (cap_membre_id() is not null or cap_est_equipe())
    and (m.annuaire_visible or m.id = cap_membre_id())
$$;
grant execute on function public.cap_annuaire_contacts() to authenticated;
