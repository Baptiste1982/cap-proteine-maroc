-- v1.14.0 : la fiche membre d'un animateur porte TOUJOURS son compte du CRM (membres.user_id), sans geste à faire.
-- Cas réel : Chrystel se connectait au CRM, mais sa fiche membre disait « Pas encore d'accès » (lien jamais posé).
-- Règles, tenues par la base :
--  1. fiche sans animateur_id : si son nom est celui de l'animateur du groupe ET qu'aucune autre fiche ne porte ce nom,
--     on pose animateur_id (un animateur à plusieurs fiches choisit la sienne lui-même, rien n'est deviné) ;
--  2. fiche avec animateur_id et sans user_id : on pose le compte du CRM de cet animateur, s'il n'est pas déjà sur une autre fiche ;
--  3. quand un compte est créé ou relié à un animateur après coup, sa fiche le reçoit.
create or replace function public.membres_lier_compte_animateur()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_anim uuid; v_cpt uuid;
begin
  if new.user_id is not null then return new; end if;
  v_anim := new.animateur_id;
  if v_anim is null then
    select a.id into v_anim from clubs c join animateurs a on a.id = c.animateur_id
     where c.id = new.club_id and lower(unaccent_simple(trim(a.nom))) = lower(unaccent_simple(trim(new.nom)));
    if v_anim is not null and (select count(*) from membres x where x.id <> new.id
         and lower(unaccent_simple(trim(x.nom))) = lower(unaccent_simple(trim(new.nom)))) = 0
       and not exists (select 1 from membres x where x.id <> new.id and x.animateur_id = v_anim) then
      new.animateur_id := v_anim;
    else
      return new;
    end if;
  end if;
  select p.id into v_cpt from profiles p where p.animateur_id = v_anim order by p.id limit 1;
  if v_cpt is not null and not exists (select 1 from membres x where x.user_id = v_cpt and x.id <> new.id) then
    new.user_id := v_cpt;
  end if;
  return new;
end $$;

create trigger membres_lier_compte before insert or update of animateur_id, nom, club_id on public.membres
  for each row execute function public.membres_lier_compte_animateur();

create or replace function public.profiles_lier_fiche_membre()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.animateur_id is null then return new; end if;
  if exists (select 1 from membres where user_id = new.id) then return new; end if;
  update membres set user_id = new.id
   where id = (select id from membres where animateur_id = new.animateur_id and user_id is null order by created_at limit 1);
  return new;
end $$;

create trigger profiles_lier_fiche_membre after insert or update of animateur_id on public.profiles
  for each row execute function public.profiles_lier_fiche_membre();

-- rattrapage : on rejoue la règle sur les fiches existantes
update public.membres set nom = nom where user_id is null;
