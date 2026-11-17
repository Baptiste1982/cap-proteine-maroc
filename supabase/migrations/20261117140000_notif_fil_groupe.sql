-- v1.4.0 — Notifications du fil de groupe : à chaque message, les membres du groupe (avec un compte) et l'animateur
-- du groupe sont prévenus, jamais l'auteur. Même circuit que les messages directs (edge notif-membre, type « groupe »).
alter table public.messages_groupe add column if not exists notifie_le timestamptz;
create trigger messages_groupe_notifier after insert on public.messages_groupe
  for each row execute function public.membres_notifier('groupe');
