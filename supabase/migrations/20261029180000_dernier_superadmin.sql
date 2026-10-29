-- ═══════════════════════════════════════════════════════════════════════════
-- Garde-fou : le réseau garde toujours au moins un superadmin (demande JB du 29/10/2026).
-- Refuse toute modification ou suppression de profil qui ferait tomber à zéro le nombre de
-- superadmins, quel que soit le chemin (CRM, edge admin-users, SQL).
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.cap_garde_superadmin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.role = 'superadmin'
     and (tg_op = 'DELETE' or new.role is distinct from 'superadmin')
     and not exists (select 1 from profiles where role = 'superadmin' and id <> old.id) then
    raise exception 'Impossible : c''est le dernier compte superadmin du réseau.';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

create or replace trigger garde_dernier_superadmin before update or delete on public.profiles
  for each row execute function public.cap_garde_superadmin();
