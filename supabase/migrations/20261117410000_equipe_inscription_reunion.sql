-- v1.23.0 (appliquée le 17/11/2026 : equipe_inscription_reunion) : tout compte de l'équipe (sauf visiteur)
-- s'inscrit lui-même à n'importe quelle réunion du réseau. Une ligne d'invité par réunion et par compte.
alter table public.invites add column if not exists profil_id uuid references public.profiles(id) on delete set null;
create unique index if not exists invites_reunion_profil_uniq on public.invites(reunion_id, profil_id) where profil_id is not null;
-- cap_equipe_inscrire(p_reunion uuid, p_viens boolean default true) security definer : insère (nom, téléphone du profil
-- ou de l'animateur, statut « Intéressé », invite_par « Équipe CAP ») ou retire sa propre ligne. Définition complète en base.
