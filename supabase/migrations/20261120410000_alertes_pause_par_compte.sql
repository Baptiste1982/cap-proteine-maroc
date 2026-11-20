-- v1.121 : une alerte mise de côté l'est sur tous les appareils de la personne (téléphone et ordinateur).
alter table public.profiles add column if not exists alertes_pause jsonb not null default '{}'::jsonb;

create or replace function public.cap_alertes_pauses() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select alertes_pause from profiles where id = auth.uid()), '{}'::jsonb)
$$;

-- p_jusqua vide ou passé = l'alerte est réaffichée.
create or replace function public.cap_alerte_pause(p_cle text, p_jusqua timestamptz) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if auth.uid() is null or not exists (select 1 from profiles where id = auth.uid()) then raise exception 'Réservé à l''équipe'; end if;
  if p_cle !~ '^[a-z]{2,20}$' then raise exception 'Alerte inconnue'; end if;
  update profiles set alertes_pause = case when p_jusqua is null or p_jusqua <= now() then alertes_pause - p_cle
      else jsonb_set(alertes_pause, array[p_cle], to_jsonb((extract(epoch from p_jusqua) * 1000)::bigint)) end
   where id = auth.uid() returning alertes_pause into v;
  return v;
end $$;
