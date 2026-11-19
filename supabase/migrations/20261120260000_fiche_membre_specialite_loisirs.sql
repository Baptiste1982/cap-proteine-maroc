-- v1.86.0 — fiche du membre : spécialité détaillée et loisirs (les contacts recherchés sont la colonne `cherche`).
alter table public.membres add column if not exists specialite_detail text;
alter table public.membres add column if not exists loisirs text;
comment on column public.membres.specialite_detail is 'Ce que le membre fait précisément dans son entreprise (texte libre, visible des membres).';
comment on column public.membres.loisirs is 'Loisirs et hobbies, séparés par des virgules (visible des membres).';

create or replace function public.cap_annuaire_plus() returns jsonb language sql stable security definer set search_path to 'public'
as $function$
  select case when cap_membre_id() is not null or cap_est_equipe() then
    (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'specialite', m.specialite_detail, 'loisirs', m.loisirs)), '[]'::jsonb)
       from membres m
      where (m.annuaire_visible or m.id = cap_membre_id())
        and (nullif(m.specialite_detail, '') is not null or nullif(m.loisirs, '') is not null))
  else '[]'::jsonb end
$function$;

create or replace function public.cap_membre_fiche_plus(p_specialite text, p_cherche text, p_loisirs text) returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  update membres set specialite_detail = nullif(trim(left(p_specialite, 800)), ''),
         cherche = nullif(trim(left(p_cherche, 800)), ''),
         loisirs = nullif(trim(left(p_loisirs, 300)), '')
   where id = cap_membre_id();
  if not found then raise exception 'aucune fiche membre liée'; end if;
end $function$;

-- L'aperçu « voir comme » accepte cette lecture.
do $do$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.proname = 'cap_voir' and p.pronamespace = 'public'::regnamespace;
  if d is not null and position('cap_annuaire_plus' in d) = 0 and (length(d) - length(replace(d, 'cap_annuaire_contacts', ''))) / length('cap_annuaire_contacts') = 1 then
    execute replace(d, 'cap_annuaire_contacts', 'cap_annuaire_contacts|cap_annuaire_plus');
  end if;
end $do$;
