-- v0.46.0 : la fiche membre d'un animateur (il compte comme membre de son groupe, étiqueté « Animateur »).
-- Appliquée le 16/11/2026 (version prod 20261116152703).
alter table public.membres add column if not exists animateur_id uuid references public.animateurs(id) on delete set null;
create unique index if not exists membres_animateur_unique on public.membres(animateur_id) where animateur_id is not null;
comment on column public.membres.animateur_id is 'Fiche membre d''un animateur (il compte comme membre, étiqueté Animateur)';
