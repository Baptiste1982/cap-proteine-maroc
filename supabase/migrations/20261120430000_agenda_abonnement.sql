-- v1.122 : agenda par abonnement. Chaque compte d'équipe a une adresse d'agenda secrète (jeton) ; Google Agenda, Apple ou Outlook
-- s'y abonnent une fois et y lisent ses PSA et ses réunions (groupes qu'il anime, réunions où il s'est inscrit).
alter table public.profiles add column if not exists agenda_jeton uuid not null default gen_random_uuid();
create unique index if not exists profiles_agenda_jeton on public.profiles (agenda_jeton);

create or replace function public.cap_agenda_jeton() returns uuid
language sql stable security definer set search_path = public as $$
  select agenda_jeton from profiles where id = auth.uid()
$$;

-- Lecture par le jeton (page publique : l'edge « agenda » la transforme en calendrier .ics). Aucune coordonnée.
create or replace function public.cap_agenda_flux(p_jeton uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p record;
begin
  select id, nom, animateur_id, role into p from profiles where agenda_jeton = p_jeton;
  if p.id is null or p.role = 'visiteur' then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'nom', p.nom,
    'psa', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'debut', c.debut, 'duree', c.duree_min, 'lieu', c.lieu, 'lien', c.lien_visio, 'mode', c.mode,
              'avec', case when c.directeur_id = p.id then c.reserve_nom
                           else (select coalesce(a.nom, d.nom) from profiles d left join animateurs a on a.id = d.animateur_id where d.id = c.directeur_id) end) order by c.debut)
        from psa_creneaux c
       where c.debut > now() - interval '30 days' and (c.reserve_par is not null or c.reserve_lien is not null)
         and (c.directeur_id = p.id or c.reserve_par = p.id)), '[]'::jsonb),
    'reunions', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'date', r.date, 'heure', r.heure, 'groupe', g.nom, 'type', r.type, 'format', r.format, 'theme', r.theme,
              'lieu', l.nom, 'adresse', l.adresse, 'statut', r.statut) order by r.date)
        from reunions r join clubs g on g.id = r.club_id left join lieux l on l.id = r.lieu_id
       where r.statut <> 'annulee' and r.date > current_date - 30 and r.date < current_date + 200
         and ((p.animateur_id is not null and (g.animateur_id = p.animateur_id or r.animateur_id = p.animateur_id))
           or exists (select 1 from invites i where i.reunion_id = r.id and i.profil_id = p.id))), '[]'::jsonb));
end $$;
