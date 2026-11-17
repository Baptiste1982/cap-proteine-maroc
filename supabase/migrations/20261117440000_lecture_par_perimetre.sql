-- v1.29.0 — Lecture par périmètre (plan du 17/11/2026, lots A2 / B1 / A3).
-- Avant : tout compte d'équipe lisait les membres, invités, documents, recommandations et leads de tout le réseau.
-- Après : super admin et directeur national lisent tout ; un directeur lit sa zone ; un animateur lit ses groupes ;
-- le compte en lecture seule ne lit plus ces tables (il passe par deux fonctions « vitrine », sans coordonnées).
-- L'agenda reste commun : groupes, réunions, lieux, zones et animateurs restent lisibles par toute l'équipe
-- (chacun peut s'inscrire à n'importe quelle réunion du réseau).

create or replace function public.cap_can_see_club(c_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select case coalesce(cap_role(), '')
    when 'superadmin' then true
    when 'directeur_national' then true
    when 'directeur' then exists (select 1 from clubs c where c.id = c_id and c.ville = any (cap_zone_villes()))
    when 'animateur' then exists (select 1 from clubs c where c.id = c_id and c.animateur_id = cap_animateur_id())
    else false end
$$;

alter policy clubs_read on public.clubs using (cap_est_equipe());
alter policy reunions_read on public.reunions using (cap_est_equipe());

-- Invités : ceux des réunions de son périmètre, plus les inscriptions de l'équipe (« Je viens »), visibles de toute l'équipe.
alter policy invites_read on public.invites using (
  (profil_id is not null and cap_est_equipe())
  or exists (select 1 from reunions r where r.id = invites.reunion_id and cap_can_see_club(r.club_id)));

-- Leads : réservés à la direction, comme dans le menu.
alter policy leads_lire on public.leads using (coalesce(cap_role(), '') in ('superadmin', 'directeur_national', 'directeur'));
alter policy leads_ajouter on public.leads with check (coalesce(cap_role(), '') in ('superadmin', 'directeur_national', 'directeur'));
alter policy leads_modifier on public.leads using (coalesce(cap_role(), '') in ('superadmin', 'directeur_national', 'directeur'));

-- Vitrine pour le compte en lecture seule : les membres et les invités sans aucune coordonnée.
create or replace function public.cap_membres_vitrine()
returns table (id uuid, club_id uuid, num integer, nom text, specialite text, formulaire boolean, contrat boolean, facture boolean, paiement boolean, created_at timestamptz, animateur_id uuid)
language sql stable security definer set search_path to 'public' as $$
  select m.id, m.club_id, m.num, m.nom, m.specialite, m.formulaire, m.contrat, m.facture, m.paiement, m.created_at, m.animateur_id
  from membres m where coalesce(cap_role(), '') = 'visiteur' or cap_can_see_club(m.club_id)
$$;
create or replace function public.cap_invites_vitrine()
returns table (id uuid, reunion_id uuid, nom text, statut text, profil_id uuid)
language sql stable security definer set search_path to 'public' as $$
  select i.id, i.reunion_id, i.nom, i.statut, i.profil_id from invites i
  where coalesce(cap_role(), '') = 'visiteur' or i.profil_id is not null
     or exists (select 1 from reunions r where r.id = i.reunion_id and cap_can_see_club(r.club_id))
$$;

-- Espace membre : l'équipe inscrite à une réunion n'est pas un invité du groupe.
create or replace function public.cap_membre_invites_groupe()
returns table (id uuid, nom text, entreprise text, metier text, tel text, email text, statut text, date date, type text, invite_par text, propose_par_nom text)
language sql stable security definer set search_path to 'public' as $$
  select i.id, i.nom, i.entreprise, i.metier, i.tel, i.email, i.statut, r.date, r.type, i.invite_par, pm.nom
  from invites i join reunions r on r.id = i.reunion_id
  left join membres pm on pm.id = i.propose_par
  where r.club_id = (select club_id from membres where id = cap_membre_id()) and i.profil_id is null
  order by r.date desc, i.nom
$$;
