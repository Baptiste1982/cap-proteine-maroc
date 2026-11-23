-- v1.139 : une personne dont la demande d'adhésion n'a pas encore de contrat signé au national est « candidate » :
-- elle a sa fiche, mais ne compte pas dans le groupe. Dès la signature (adhesions.national.signe_le) elle en fait partie.
-- Une fiche sans demande d'adhésion liée (animateurs, fiches saisies à la main) n'est jamais candidate.
alter table public.membres add column if not exists candidat boolean not null default false;

create or replace function public.cap_membre_candidat_calc(p uuid) returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (select 1 from adhesions a where a.membre_id = p and a.statut <> 'rejetee')
     and not exists (select 1 from adhesions a where a.membre_id = p and a.statut <> 'rejetee' and coalesce(a.national->>'signe_le', '') <> '')
$fn$;

create or replace function public.adhesions_candidat_maj() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.membre_id is not null then
    update membres set candidat = cap_membre_candidat_calc(id) where id = new.membre_id and candidat is distinct from cap_membre_candidat_calc(id);
  end if;
  if tg_op = 'UPDATE' and old.membre_id is not null and old.membre_id is distinct from new.membre_id then
    update membres set candidat = cap_membre_candidat_calc(id) where id = old.membre_id and candidat is distinct from cap_membre_candidat_calc(id);
  end if;
  return new;
end $fn$;

create or replace trigger adhesions_candidat after insert or update of membre_id, statut, national on public.adhesions
  for each row execute function public.adhesions_candidat_maj();

-- Les membres qui comptent dans un groupe. security_invoker : les droits de lecture restent ceux de la table.
create or replace view public.membres_groupe with (security_invoker = true) as
  select * from public.membres where not candidat;

update public.membres set candidat = cap_membre_candidat_calc(id) where candidat is distinct from cap_membre_candidat_calc(id);
