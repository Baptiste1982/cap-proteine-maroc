-- v1.14.0 : lien d'inscription suivi. Le lien partagé passe par i.html?n=<invitation>&s=<source>,
-- qui compte le clic puis renvoie vers le formulaire du CRM national.
create table if not exists public.liens_clics (
  id bigint generated always as identity primary key,
  reunion_id uuid not null references public.reunions(id) on delete cascade,
  invitation text not null,
  source text,
  visiteur text,
  created_at timestamptz not null default now()
);
create index if not exists liens_clics_reunion_idx on public.liens_clics(reunion_id, created_at);
alter table public.liens_clics enable row level security;
create policy liens_clics_lire on public.liens_clics for select
  using (public.cap_est_equipe() and public.cap_can_see_club((select r.club_id from public.reunions r where r.id = reunion_id)));
comment on table public.liens_clics is 'Clics sur le lien d''inscription suivi (i.html) : un clic par ouverture, sans les aperçus WhatsApp (pas de JS).';

-- Appelée sans connexion par i.html. Rend le lien du national, ou null si l'invitation est inconnue.
create or replace function public.cap_lien_clic(p_inv text, p_source text, p_visiteur text)
returns text language plpgsql security definer set search_path = public as $$
declare v_r record; v_src text; v_vis text;
begin
  if p_inv is null or p_inv !~ '^\d{1,9}$' then return null; end if;
  select id, national->>'lien' as lien into v_r from reunions
   where national->>'invitation_id' = p_inv order by date desc limit 1;
  if v_r.id is null then return null; end if;
  v_src := nullif(left(regexp_replace(coalesce(p_source,''), '[^a-zA-Z0-9-]', '', 'g'), 20), '');
  v_vis := nullif(left(regexp_replace(coalesce(p_visiteur,''), '[^a-zA-Z0-9-]', '', 'g'), 40), '');
  -- pas de double compte d'un même visiteur en 30 s, et plafond de 600 clics par heure et par réunion
  if not exists (select 1 from liens_clics where reunion_id = v_r.id and visiteur is not distinct from v_vis and created_at > now() - interval '30 seconds')
     and (select count(*) from liens_clics where reunion_id = v_r.id and created_at > now() - interval '1 hour') < 600 then
    insert into liens_clics(reunion_id, invitation, source, visiteur) values (v_r.id, p_inv, v_src, v_vis);
  end if;
  return v_r.lien;
end $$;
grant execute on function public.cap_lien_clic(text, text, text) to anon, authenticated;
