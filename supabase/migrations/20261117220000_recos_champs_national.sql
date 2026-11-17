-- v1.7.0 : la fiche de recommandation reprend les champs du CRM national (Recommandations → saisie), relevés le 17/11/2026 :
-- type (Information commerciale 4 / Mise en relation 3), objet, précision (= besoin), origine (idOrigine), budget,
-- date limite (datePeremption), appel d'offres + entreprises consultées, civilité, 2e téléphone, adresse ;
-- suivi : montant devisé (« Devisé »), montant gagné (« Gagné » = montant), date de relance. Pas de DROP.
-- Appliquée telle quelle par apply_migration (nom : recos_champs_national).
alter table public.recommandations add column if not exists type_reco text check (type_reco is null or type_reco in ('information','mise_en_relation'));
alter table public.recommandations add column if not exists objet text check (objet is null or char_length(objet) <= 200);
alter table public.recommandations add column if not exists origine smallint;
alter table public.recommandations add column if not exists budget numeric(14,2) check (budget is null or budget >= 0);
alter table public.recommandations add column if not exists date_limite date;
alter table public.recommandations add column if not exists appel_offre boolean;
alter table public.recommandations add column if not exists entreprises_consultees text;
alter table public.recommandations add column if not exists contact_civilite text;
alter table public.recommandations add column if not exists contact_tel2 text;
alter table public.recommandations add column if not exists contact_adresse text;
alter table public.recommandations add column if not exists montant_devis numeric(14,2) check (montant_devis is null or montant_devis >= 0);
alter table public.recommandations add column if not exists relance_le date;
alter table public.recommandations add column if not exists national jsonb;
comment on column public.recommandations.type_reco is 'Type au national : information (« Information commerciale », 4) ou mise_en_relation (3).';
comment on column public.recommandations.origine is 'Origine au national (idOrigine) : 1 Relationnel Protéine, 9 Réunion interclub, 8 Speed Business, 10 Réseaux sociaux, 4 Demande site public, 2 eMailing, 6 Téléprospection, 7 Presse, 11 Relvicom.';
comment on column public.recommandations.montant_devis is 'Montant devisé (le national suit « Devisé » et « Gagné »). montant = gagné.';
comment on column public.recommandations.national is 'Suivi de l''envoi au CRM national (id de la reco là-bas, envoyée le, erreur).';

create or replace function public.cap_membre_reco_donner_fiche(p jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare me membres%rowtype; n int; rid uuid; v_a uuid := nullif(p->>'a','')::uuid;
  t text := nullif(trim(p->>'tel'),''); e text := nullif(lower(trim(p->>'email')),'');
begin
  select * into me from membres where user_id = auth.uid();
  if not found then raise exception 'aucune fiche membre liée'; end if;
  if v_a is null or v_a = me.id or not exists (select 1 from membres where id = v_a) then raise exception 'destinataire invalide'; end if;
  if coalesce(trim(p->>'nom'), '') = '' then raise exception 'le nom du contact est obligatoire'; end if;
  if coalesce(trim(p->>'objet'), '') = '' then raise exception 'indique l''objet de la recommandation'; end if;
  if t is null and e is null then raise exception 'indique au moins un moyen de joindre le contact (téléphone ou e-mail)'; end if;
  select count(*) into n from recommandations where de = me.id and cree_le > now() - interval '1 day';
  if n >= 30 then raise exception 'trop de recommandations aujourd''hui'; end if;
  insert into recommandations (club_id, de, a, contact_nom, contact_tel, contact_entreprise, besoin, contact_email, contact_fonction,
      contact_ville, chaleur, contact_prevenu, type_reco, objet, origine, budget, date_limite, appel_offre, entreprises_consultees,
      contact_civilite, contact_tel2, contact_adresse)
  values (me.club_id, me.id, v_a, left(trim(p->>'nom'), 120), left(t, 40), nullif(left(trim(p->>'entreprise'), 120), ''),
      nullif(left(trim(p->>'besoin'), 1000), ''), left(e, 160), nullif(left(trim(p->>'fonction'), 120), ''),
      nullif(left(trim(p->>'ville'), 80), ''), nullif(p->>'chaleur','')::smallint, (p->>'prevenu')::boolean,
      case when p->>'type_reco' in ('information','mise_en_relation') then p->>'type_reco' end,
      left(trim(p->>'objet'), 200), coalesce(nullif(p->>'origine','')::smallint, 1),
      nullif(p->>'budget','')::numeric, nullif(p->>'date_limite','')::date, (p->>'appel_offre')::boolean,
      nullif(left(trim(p->>'entreprises_consultees'), 500), ''),
      case when p->>'civilite' in ('Monsieur','Madame') then p->>'civilite' end,
      nullif(left(trim(p->>'tel2'), 40), ''), nullif(left(trim(p->>'adresse'), 300), ''))
  returning id into rid;
  return rid;
end $$;

create or replace function public.cap_membre_reco_suivre(p_id uuid, p jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare st text := p->>'statut';
begin
  if st not in ('envoyee','contact','devis','signee','sans_suite') then raise exception 'statut inconnu'; end if;
  if st = 'signee' and nullif(p->>'montant','') is null then raise exception 'indique le montant de l''affaire'; end if;
  update recommandations set statut = st,
      montant = case when st = 'signee' then (p->>'montant')::numeric else montant end,
      montant_devis = coalesce(nullif(p->>'montant_devis','')::numeric, montant_devis),
      relance_le = case when p ? 'relance_le' then nullif(p->>'relance_le','')::date else relance_le end,
      note_suivi = coalesce(nullif(left(trim(p->>'note'), 1000), ''), note_suivi),
      maj_le = now()
   where id = p_id and a = cap_membre_id();
  if not found then raise exception 'recommandation introuvable'; end if;
end $$;

grant execute on function public.cap_membre_reco_donner_fiche(jsonb) to authenticated;
grant execute on function public.cap_membre_reco_suivre(uuid, jsonb) to authenticated;
