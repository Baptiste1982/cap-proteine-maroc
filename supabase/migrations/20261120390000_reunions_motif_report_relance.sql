-- v1.115 : suivi national des réunions. Motif d'annulation, trace des déplacements, relance de l'animateur.
alter table public.reunions add column if not exists annule_motif text;
alter table public.reunions add column if not exists annule_le timestamptz;
alter table public.reunions add column if not exists annule_par uuid;
alter table public.reunions add column if not exists report_motif text;
alter table public.reunions add column if not exists date_initiale date;
alter table public.reunions add column if not exists reports integer not null default 0;

-- Tenu par la base, quel que soit l'écran qui change la date ou annule : nombre de déplacements, date prévue au départ, qui annule et quand.
create or replace function public.reunions_suivre() returns trigger language plpgsql as $$
begin
  if new.date is distinct from old.date and old.statut <> 'realisee' then
    new.reports := coalesce(old.reports, 0) + 1;
    new.date_initiale := coalesce(old.date_initiale, old.date);
  end if;
  if new.statut = 'annulee' and old.statut is distinct from 'annulee' then
    new.annule_le := coalesce(new.annule_le, now());
    new.annule_par := coalesce(new.annule_par, auth.uid());
  end if;
  return new;
end $$;
create trigger reunions_suivre before update on public.reunions for each row execute function public.reunions_suivre();

-- Relancer l'animateur d'un groupe : bilan à saisir, motif d'une annulation, ou groupe sans réunion récente.
create or replace function public.cap_reunion_relancer(p_club uuid, p_reunion uuid, p_quoi text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare an uuid; ids jsonb; g text; d date; qui text; titre text; corps text; lien text;
begin
  if auth.uid() is null or coalesce(cap_role(), '') not in ('superadmin', 'directeur_national', 'directeur') or not cap_can_see_club(p_club) then
    raise exception 'Réservé à la direction';
  end if;
  if p_quoi not in ('bilan', 'motif', 'trou') then raise exception 'Demande inconnue'; end if;
  select nom, animateur_id into g, an from clubs where id = p_club;
  if p_reunion is not null then
    select r.date, coalesce(r.animateur_id, an) into d, an from reunions r where r.id = p_reunion and r.club_id = p_club;
    if d is null then raise exception 'Réunion introuvable'; end if;
  end if;
  select coalesce(jsonb_agg(id), '[]'::jsonb) into ids from profiles where animateur_id = an and id <> auth.uid();
  if an is null or jsonb_array_length(ids) = 0 then return jsonb_build_object('ok', true, 'compte', false); end if;
  select coalesce(a.nom, p.nom) into qui from profiles p left join animateurs a on a.id = p.animateur_id where p.id = auth.uid();
  titre := case p_quoi when 'bilan' then '📝 Bilan de réunion à saisir' when 'motif' then '🗓 Motif d''annulation à indiquer' else '🗓 Pas de réunion récente' end;
  corps := case p_quoi
    when 'bilan' then g || ' · réunion du ' || to_char(d, 'DD/MM') || '. ' || coalesce(qui, 'La direction') || ' te demande de saisir le bilan.'
    when 'motif' then g || ' · réunion du ' || to_char(d, 'DD/MM') || ' annulée : indique pourquoi.'
    else g || ' : planifie la prochaine réunion, ou indique pourquoi il n''y en a pas eu.' end;
  lien := case when p_reunion is not null then '/?reunion=' || p_reunion else '/?groupe=' || p_club end;
  perform net.http_post(url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-leads',
    body := jsonb_build_object('pour', ids, 'titre', titre, 'corps', corps, 'url', lien, 'tag', 'reu-' || coalesce(p_reunion, p_club)),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-suivi-jeton', (select decrypted_secret from vault.decrypted_secrets where name = 'national_suivi_jeton')),
    timeout_milliseconds := 20000);
  return jsonb_build_object('ok', true, 'compte', true);
end $$;
