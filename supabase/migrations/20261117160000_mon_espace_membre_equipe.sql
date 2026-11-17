-- v1.5.0 — « Mon espace membre » depuis le CRM : un animateur ou un directeur qui est aussi membre ouvre son espace membre
-- avec sa session du CRM, sans code. Sa fiche membre est reliée à son compte (membres.user_id, unique : une fiche à la fois).
-- Fiche autorisée : celle liée à son animateur (animateur_id), ou une fiche à son nom dans un groupe qu'il peut modifier.
create or replace function public.cap_lier_mon_espace(p_membre uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_anim uuid; v_nom text; m membres%rowtype;
begin
  if auth.uid() is null or not cap_est_equipe() then raise exception 'réservé à l''équipe'; end if;
  select p.animateur_id, coalesce(a.nom, p.nom) into v_anim, v_nom from profiles p left join animateurs a on a.id = p.animateur_id where p.id = auth.uid();
  select * into m from membres where id = p_membre;
  if not found then raise exception 'fiche introuvable'; end if;
  if m.user_id = auth.uid() then return json_build_object('statut', 'ok'); end if;
  if m.user_id is not null then raise exception 'cette fiche est déjà reliée à un autre compte'; end if;
  if not ((v_anim is not null and m.animateur_id = v_anim)
       or (lower(unaccent_simple(trim(m.nom))) = lower(unaccent_simple(trim(v_nom))) and cap_can_edit_club(m.club_id))) then
    raise exception 'cette fiche n''est pas la tienne';
  end if;
  update membres set user_id = null where user_id = auth.uid() and id <> p_membre;
  update membres set user_id = auth.uid() where id = p_membre;
  return json_build_object('statut', 'ok');
end $$;
