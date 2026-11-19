-- v1.98 : un compte du CRM national par animateur.
-- Quand le CRM agit au national pour un groupe (invitation, inscrits), il se connecte avec le compte de l'animateur
-- du groupe s'il l'a branché ; sinon avec le compte commun (secrets CAP_NATIONAL_*), comme avant.
-- Le mot de passe est dans le coffre (vault) ; la table ne garde que l'identifiant et l'état de la connexion.
-- Personne ne relit un mot de passe : seule la fonction serveur (service_role) y a accès.

create table if not exists public.national_comptes (
  animateur_id uuid primary key,
  identifiant  text not null default '',
  secret_id    uuid,
  actif        boolean not null default true,
  ok_le        timestamptz,
  erreur       text,
  erreur_le    timestamptz,
  infos        jsonb,
  maj_le       timestamptz not null default now(),
  maj_par      uuid
);
alter table public.national_comptes enable row level security;
comment on table public.national_comptes is 'Compte du CRM national de chaque animateur (identifiant ; le mot de passe est dans le coffre). Aucune lecture directe : RPC cap_national_compte*.';

create or replace function public.cap_national_compte_peut(p_anim uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_anim is not null and (coalesce(cap_role(), '') = 'superadmin' or cap_animateur_id() = p_anim)
$$;

create or replace function public.cap_national_compte_poser(p_anim uuid, p_identifiant text, p_mdp text) returns jsonb
language plpgsql security definer set search_path = public, vault as $$
declare v_sid uuid; v_id text := btrim(coalesce(p_identifiant, ''));
begin
  if not cap_national_compte_peut(p_anim) then raise exception 'Ce compte national n''est pas le tien'; end if;
  if length(v_id) < 2 or length(coalesce(p_mdp, '')) < 2 then raise exception 'Identifiant et mot de passe requis'; end if;
  if not exists (select 1 from animateurs where id = p_anim) then raise exception 'Animateur introuvable'; end if;
  select secret_id into v_sid from national_comptes where animateur_id = p_anim;
  if v_sid is null then
    v_sid := vault.create_secret(p_mdp, 'national_compte_' || p_anim::text, 'Mot de passe du CRM national d''un animateur');
  else
    perform vault.update_secret(v_sid, p_mdp);
  end if;
  insert into national_comptes (animateur_id, identifiant, secret_id, actif, ok_le, erreur, erreur_le, infos, maj_le, maj_par)
  values (p_anim, v_id, v_sid, true, null, null, null, null, now(), auth.uid())
  on conflict (animateur_id) do update
    set identifiant = excluded.identifiant, secret_id = excluded.secret_id, actif = true,
        ok_le = null, erreur = null, erreur_le = null, infos = null, maj_le = now(), maj_par = auth.uid();
  return jsonb_build_object('ok', true);
end $$;

-- Retirer : le mot de passe du coffre est écrasé par une valeur au hasard, la ligne est désactivée.
create or replace function public.cap_national_compte_retirer(p_anim uuid) returns jsonb
language plpgsql security definer set search_path = public, vault as $$
declare v_sid uuid;
begin
  if not cap_national_compte_peut(p_anim) then raise exception 'Ce compte national n''est pas le tien'; end if;
  select secret_id into v_sid from national_comptes where animateur_id = p_anim;
  if v_sid is not null then perform vault.update_secret(v_sid, encode(extensions.gen_random_bytes(24), 'hex')); end if;
  update national_comptes set actif = false, identifiant = '', ok_le = null, erreur = null, erreur_le = null, infos = null,
         maj_le = now(), maj_par = auth.uid() where animateur_id = p_anim;
  return jsonb_build_object('ok', true);
end $$;

-- État des comptes : le super admin les voit tous, un animateur le sien. L'identifiant est masqué.
create or replace function public.cap_national_comptes_etat() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'animateur_id', c.animateur_id,
           'identifiant', case when length(c.identifiant) > 3 then left(c.identifiant, 2) || '•••' || right(c.identifiant, 1) else '•••' end,
           'ok_le', c.ok_le, 'erreur', c.erreur, 'erreur_le', c.erreur_le, 'infos', c.infos, 'maj_le', c.maj_le)), '[]'::jsonb)
  from national_comptes c
  where c.actif and cap_est_equipe() and (coalesce(cap_role(), '') = 'superadmin' or c.animateur_id = cap_animateur_id())
$$;

-- Lecture du mot de passe : réservée aux fonctions serveur (clé service_role). Jamais depuis l'appli.
create or replace function public.cap_national_compte_secret(p_anim uuid) returns jsonb
language plpgsql stable security definer set search_path = public, vault as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'réservé au serveur'; end if;
  return (select jsonb_build_object('identifiant', c.identifiant, 'mdp', s.decrypted_secret)
            from national_comptes c join vault.decrypted_secrets s on s.id = c.secret_id
           where c.animateur_id = p_anim and c.actif and c.identifiant <> '');
end $$;
