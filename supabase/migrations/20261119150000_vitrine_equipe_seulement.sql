-- Les deux fonctions « vitrine » ne répondent qu'à un compte d'équipe
-- (avant : les inscriptions « Je viens » de l'équipe sortaient sans connexion).
create or replace function public.cap_invites_vitrine()
 returns table(id uuid, reunion_id uuid, nom text, statut text, profil_id uuid)
 language sql stable security definer set search_path to 'public'
as $function$
  select i.id, i.reunion_id, i.nom, i.statut, i.profil_id from invites i
  where cap_est_equipe() and (coalesce(cap_role(), '') = 'visiteur' or i.profil_id is not null
     or exists (select 1 from reunions r where r.id = i.reunion_id and cap_can_see_club(r.club_id)))
$function$;
create or replace function public.cap_membres_vitrine()
 returns table(id uuid, club_id uuid, num integer, nom text, specialite text, formulaire boolean, contrat boolean, facture boolean, paiement boolean, created_at timestamp with time zone, animateur_id uuid)
 language sql stable security definer set search_path to 'public'
as $function$
  select m.id, m.club_id, m.num, m.nom, m.specialite, m.formulaire, m.contrat, m.facture, m.paiement, m.created_at, m.animateur_id
  from membres m where cap_est_equipe() and (coalesce(cap_role(), '') = 'visiteur' or cap_can_see_club(m.club_id))
$function$;
