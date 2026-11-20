-- v1.123 : proposer la visite guidée à un compte donné à sa prochaine connexion (profiles.tuto_proposer, levé quand la visite est lancée).
alter table public.profiles add column if not exists tuto_proposer boolean not null default false;

create or replace function public.cap_tuto_propose_fait() returns void
language sql security definer set search_path = public as $$
  update profiles set tuto_proposer = false where id = auth.uid()
$$;
