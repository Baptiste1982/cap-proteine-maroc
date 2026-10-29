-- ═══════════════════════════════════════════════════════════════════════════
-- Adhésions et PDF : chacun voit son périmètre (décision JB du 29/10/2026).
--   superadmin, directeur_national : tout ;
--   directeur (régional) : les clubs de sa zone + les adhésions sans groupe (à rattacher) ;
--   animateur : les adhésions de ses clubs ; visiteur : rien.
-- Le groupe d'une adhésion = le club du membre intégré, sinon le club du lien (?ref=).
-- Aucune politique de suppression n'existe sur adhesions ni sur le bucket : la trace est permanente.
-- Les politiques existantes sont MODIFIÉES (alter policy), pas supprimées.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.cap_peut_voir_adhesion(p_ref text, p_membre uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare r text := cap_role(); c uuid;
begin
  if r is null or r = 'visiteur' then return false; end if;
  if r in ('superadmin', 'directeur_national') then return true; end if;
  select club_id into c from membres where id = p_membre;
  if c is null and p_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then c := p_ref::uuid; end if;
  if c is null then return r = 'directeur'; end if;
  if r = 'directeur' then return exists(select 1 from clubs where id = c and ville = any(cap_zone_villes())); end if;
  if r = 'animateur' then return exists(select 1 from clubs where id = c and animateur_id = cap_animateur_id()); end if;
  return false;
end $$;

alter policy adhesions_select_auth on public.adhesions using (cap_peut_voir_adhesion(ref, membre_id));
alter policy adhesions_update_auth on public.adhesions using (cap_peut_voir_adhesion(ref, membre_id));

-- PDF : lisible seulement si l'adhésion correspondante est visible (la sous-requête passe par la RLS ci-dessus).
alter policy adhesions_pdf_select_auth on storage.objects
  using (bucket_id = 'adhesions' and exists (select 1 from public.adhesions a where a.pdf_path = name));
