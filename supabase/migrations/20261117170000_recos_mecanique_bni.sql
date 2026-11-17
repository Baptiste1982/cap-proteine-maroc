-- v1.5.0 : recommandations façon BNI (demande JB du 17/11/2026).
-- Celui qui DONNE la reco l'a à son actif (CA transmis). Celui qui la REÇOIT la fait avancer et saisit le montant
-- signé (CA reçu). Le contact (le client final) ne regarde que les deux membres : le CRM ne l'affiche pas.
-- La fiche du contact s'enrichit pour aider celui qui reçoit : e-mail, fonction, ville, chaleur 1 à 5, prévenu ou non.
-- Celui qui reçoit peut expliquer l'issue (note de suivi). Pas de DROP, pas de DELETE.

alter table public.recommandations add column if not exists contact_email text;
alter table public.recommandations add column if not exists contact_fonction text;
alter table public.recommandations add column if not exists contact_ville text;
alter table public.recommandations add column if not exists chaleur smallint check (chaleur is null or chaleur between 1 and 5);
alter table public.recommandations add column if not exists contact_prevenu boolean;
alter table public.recommandations add column if not exists note_suivi text;
comment on column public.recommandations.chaleur is 'Chaleur de la reco donnée par celui qui la passe : 1 = simple piste, 5 = le contact attend l''appel et est prêt à signer.';
comment on column public.recommandations.note_suivi is 'Mot de celui qui a reçu la reco sur son issue (signée, sans suite, annulée…).';

-- Donner une recommandation, avec la fiche complète du contact.
create or replace function public.cap_membre_reco_donner(p_a uuid, p_nom text, p_tel text, p_entreprise text, p_besoin text,
  p_email text, p_fonction text, p_ville text, p_chaleur int, p_prevenu boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare me membres%rowtype; n int; rid uuid;
begin
  select * into me from membres where user_id = auth.uid();
  if not found then raise exception 'aucune fiche membre liée'; end if;
  if p_a is null or p_a = me.id or not exists (select 1 from membres where id = p_a) then raise exception 'destinataire invalide'; end if;
  if coalesce(trim(p_nom), '') = '' then raise exception 'le nom du contact est obligatoire'; end if;
  if coalesce(trim(p_tel), '') = '' and coalesce(trim(p_email), '') = '' then
    raise exception 'indique au moins un moyen de joindre le contact (téléphone ou e-mail)'; end if;
  if p_chaleur is not null and (p_chaleur < 1 or p_chaleur > 5) then raise exception 'chaleur entre 1 et 5'; end if;
  select count(*) into n from recommandations where de = me.id and cree_le > now() - interval '1 day';
  if n >= 30 then raise exception 'trop de recommandations aujourd''hui'; end if;
  insert into recommandations (club_id, de, a, contact_nom, contact_tel, contact_entreprise, besoin,
                               contact_email, contact_fonction, contact_ville, chaleur, contact_prevenu)
  values (me.club_id, me.id, p_a, left(trim(p_nom), 120), nullif(left(trim(p_tel), 40), ''),
          nullif(left(trim(p_entreprise), 120), ''), nullif(left(trim(p_besoin), 1000), ''),
          nullif(left(lower(trim(p_email)), 160), ''), nullif(left(trim(p_fonction), 120), ''),
          nullif(left(trim(p_ville), 80), ''), p_chaleur, p_prevenu)
  returning id into rid;
  return rid;
end $$;

-- Seul celui qui a reçu la recommandation la fait avancer, saisit le montant signé (il peut le corriger) et explique l'issue.
create or replace function public.cap_membre_reco_avancer(p_id uuid, p_statut text, p_montant numeric, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_statut not in ('envoyee','contact','devis','signee','sans_suite') then raise exception 'statut inconnu'; end if;
  if p_statut = 'signee' and (p_montant is null or p_montant < 0) then raise exception 'indique le montant de l''affaire'; end if;
  update recommandations
     set statut = p_statut,
         montant = case when p_statut = 'signee' then p_montant else montant end,
         note_suivi = coalesce(nullif(left(trim(p_note), 1000), ''), note_suivi),
         maj_le = now()
   where id = p_id and a = cap_membre_id();
  if not found then raise exception 'recommandation introuvable'; end if;
end $$;

grant execute on function public.cap_membre_reco_donner(uuid, text, text, text, text, text, text, text, int, boolean) to authenticated;
grant execute on function public.cap_membre_reco_avancer(uuid, text, numeric, text) to authenticated;
