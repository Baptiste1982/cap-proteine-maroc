-- Didacticiel de première connexion : on retient, par compte, qu'il a été vu ou passé.
alter table public.profiles add column if not exists tuto_vu_le timestamptz;
create or replace function public.cap_tuto_vu()
returns void language sql security definer set search_path = public as $$
  update profiles set tuto_vu_le = now() where id = auth.uid();
$$;
revoke all on function public.cap_tuto_vu() from public, anon;
grant execute on function public.cap_tuto_vu() to authenticated;
