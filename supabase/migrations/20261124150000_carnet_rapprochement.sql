-- v1.148 : rapprochement du carnet du national avec ce que le CRM connaît déjà (membres, leads, invités),
-- et passage d'un contact du carnet en lead. Même personne = même mobile, même e-mail, ou même prénom + nom.
alter table public.carnet_national add column if not exists lead_id uuid references public.leads(id) on delete set null;

create or replace function public.cap_carnet_rapprochement() returns jsonb
language plpgsql stable security definer set search_path = public as $fn$
declare v_anim uuid := cap_animateur_id(); v_sup boolean := coalesce(cap_role(), '') = 'superadmin';
begin
  if not cap_est_equipe() or coalesce(cap_role(), '') = 'visiteur' then raise exception 'réservé à l''équipe'; end if;
  return (
    with c as (
      select k.id, k.lead_id, cap_tel_norm(k.tel1) t1, cap_tel_norm(k.tel2) t2, nullif(lower(btrim(coalesce(k.email, ''))), '') mail,
             nullif(cap_nom_cle(coalesce(k.prenom, '') || ' ' || coalesce(k.nom, '')), '') n1, nullif(cap_nom_cle(coalesce(k.nom, '') || ' ' || coalesce(k.prenom, '')), '') n2,
             (coalesce(k.prenom, '') <> '' and coalesce(k.nom, '') <> '') complet
      from carnet_national k where v_sup or (k.animateur_id is not null and k.animateur_id = v_anim)),
    mb as (select m.id, m.nom, m.club_id, m.candidat, cap_tel_norm(m.infos->>'m_tel') t, nullif(lower(btrim(coalesce(m.infos->>'m_email', ''))), '') mail, cap_nom_cle(m.nom) n from membres m),
    ld as (select l.id, l.statut, cap_tel_norm(l.telephone) t, cap_nom_cle(l.nom) n from leads l),
    iv as (select i.reunion_id, cap_tel_norm(i.tel) t, nullif(lower(btrim(coalesce(i.email, ''))), '') mail, cap_nom_cle(i.nom) n, r.date from invites i join reunions r on r.id = i.reunion_id where i.profil_id is null)
    select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select jsonb_strip_nulls(jsonb_build_object('id', c.id,
        'membre', (select jsonb_build_object('id', mb.id, 'nom', mb.nom, 'club_id', mb.club_id, 'groupe', (select nom from clubs where id = mb.club_id), 'candidat', mb.candidat)
                   from mb where (mb.t is not null and mb.t in (c.t1, c.t2)) or (mb.mail is not null and mb.mail = c.mail) or (c.complet and mb.n in (c.n1, c.n2)) limit 1),
        'lead', (select jsonb_build_object('id', ld.id, 'statut', ld.statut)
                 from ld where ld.id = c.lead_id or (ld.t is not null and ld.t in (c.t1, c.t2)) or (c.complet and ld.n in (c.n1, c.n2)) order by (ld.id = c.lead_id) desc limit 1),
        'invite', (select jsonb_build_object('n', count(*), 'derniere', max(iv.date))
                   from iv where (iv.t is not null and iv.t in (c.t1, c.t2)) or (iv.mail is not null and iv.mail = c.mail) or (c.complet and iv.n in (c.n1, c.n2)) having count(*) > 0))) x
      from c) s where x ? 'membre' or x ? 'lead' or x ? 'invite');
end $fn$;

-- Un contact du carnet devient un lead (le sien : il lui est confié d'office). Un lead déjà connu est repris, pas doublé.
create or replace function public.cap_carnet_vers_lead(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare k carnet_national; v_lead uuid; v_nom text; v_qui text; v_t text;
begin
  if not cap_est_equipe() or coalesce(cap_role(), '') = 'visiteur' then raise exception 'réservé à l''équipe'; end if;
  select * into k from carnet_national where id = p_id;
  if k.id is null or not (coalesce(cap_role(), '') = 'superadmin' or (k.animateur_id is not null and k.animateur_id = cap_animateur_id())) then raise exception 'contact introuvable dans ton carnet'; end if;
  v_nom := btrim(coalesce(k.prenom, '') || ' ' || coalesce(k.nom, ''));
  if v_nom = '' then raise exception 'ce contact n''a pas de nom'; end if;
  v_t := cap_tel_norm(coalesce(k.tel1, k.tel2));
  select l.id into v_lead from leads l where l.id = k.lead_id or (v_t is not null and cap_tel_norm(l.telephone) = v_t)
    or (coalesce(k.prenom, '') <> '' and coalesce(k.nom, '') <> '' and cap_nom_cle(l.nom) in (cap_nom_cle(k.prenom || ' ' || k.nom), cap_nom_cle(k.nom || ' ' || k.prenom))) limit 1;
  if v_lead is not null then update carnet_national set lead_id = v_lead where id = p_id; return jsonb_build_object('lead_id', v_lead, 'deja', true); end if;
  select nom into v_qui from profiles where id = auth.uid();
  insert into leads (nom, specialite, telephone, source, ville, commentaire, origine, feuille, attribue_a, attribue_par, attribue_par_nom, attribue_le, attribue_lu_le, attribue_notifie_le)
  values (v_nom, nullif(btrim(concat_ws(' · ', k.fonction, k.entreprise)), ''), coalesce(k.tel1, k.tel2), 'Carnet du national', k.ville, nullif(k.email, ''), 'carnet', coalesce(nullif(k.ville, ''), 'Carnet'),
    k.animateur_id, case when k.animateur_id is not null then auth.uid() end, case when k.animateur_id is not null then v_qui end,
    case when k.animateur_id is not null then now() end, case when k.animateur_id is not null then now() end, case when k.animateur_id is not null then now() end)
  returning id into v_lead;
  update carnet_national set lead_id = v_lead where id = p_id;
  return jsonb_build_object('lead_id', v_lead, 'deja', false);
end $fn$;
