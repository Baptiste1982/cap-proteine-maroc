-- ═══════════════════════════════════════════════════════════════════════════
-- Notification sur le téléphone à l'arrivée d'une adhésion (web push).
-- Projet Supabase : cap-proteine-maroc (xsppsqjigdgaybmowzaq).
--
-- 1. push_abonnements : un appareil abonné = une ligne, chaque compte ne voit et ne gère que les siennes.
-- 2. adhesions.notifiee_le : posée par l'edge `notif-adhesion` au moment de l'envoi ; une adhésion
--    n'est notifiée qu'une fois (l'edge « réserve » la ligne : update … where notifiee_le is null).
-- 3. Déclencheur : à chaque nouvelle adhésion, pg_net appelle l'edge avec l'id. L'edge vérifie
--    elle-même que l'adhésion existe, date de moins de 15 min et n'a pas été notifiée : un appel
--    forgé ne peut ni rien lire ni déclencher de doublon.
-- ═══════════════════════════════════════════════════════════════════════════
create extension if not exists pg_net;

create table if not exists public.push_abonnements (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  endpoint   text not null unique,
  p256dh     text not null,
  auth       text not null,
  appareil   text,
  created_at timestamptz not null default now()
);
alter table public.push_abonnements enable row level security;
create policy push_abo_select on public.push_abonnements for select to authenticated using (user_id = auth.uid());
create policy push_abo_insert on public.push_abonnements for insert to authenticated with check (user_id = auth.uid());
create policy push_abo_update on public.push_abonnements for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy push_abo_delete on public.push_abonnements for delete to authenticated using (user_id = auth.uid());

alter table public.adhesions add column if not exists notifiee_le timestamptz;

create or replace function public.adhesion_notifier()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'https://xsppsqjigdgaybmowzaq.supabase.co/functions/v1/notif-adhesion',
    body := jsonb_build_object('id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json')
  );
  return new;
end $$;

create or replace trigger adhesion_notifier after insert on public.adhesions
  for each row execute function public.adhesion_notifier();
