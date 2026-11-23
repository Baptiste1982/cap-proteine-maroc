-- v1.139 : les calculs et les listes qui comptent ou montrent les membres d'un groupe lisent « membres_groupe »
-- (sans les candidats) au lieu de « membres ». Le corps des fonctions n'est pas réécrit à la main : seule la table lue change.
do $do$
declare r record; d text;
begin
  for r in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f' and p.proname = any (array[
              'cap_club_statut_calc', 'cap_monitoring', 'cap_monitoring_groupe', 'cap_tableau_club',
              'cap_annuaire', 'cap_annuaire_fiche', 'cap_annuaire_contacts', 'cap_annuaire_plus',
              'cap_groupe_page', 'cap_groupe_vue', 'cap_reunion_prevus', 'cap_membre_reunion_prevus',
              'cap_reunion_qualites', 'cap_membres_vitrine'])
  loop
    d := pg_get_functiondef(r.oid);
    d := regexp_replace(d, '(from|join)(\s+)(public\.)?membres\M', '\1\2public.membres_groupe', 'gi');
    execute d;
  end loop;
end $do$;

-- Le statut des groupes concernés est recalculé (déclencheur clubs_statut_avant).
update public.clubs set statut_fixe = statut_fixe where id in (select club_id from public.membres where candidat);
