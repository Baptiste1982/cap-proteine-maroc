-- v1.110 : coffre des comptes du CRM national. Le super admin (et lui seul) peut relire l'identifiant et le mot de passe
-- qu'un animateur a branchés, pour les lui redonner s'il les oublie. Chaque lecture est notée.
alter table public.national_comptes add column if not exists lu_le timestamptz;
alter table public.national_comptes add column if not exists lu_par uuid;

create or replace function public.cap_national_compte_lire(p_anim uuid) returns jsonb
language plpgsql security definer set search_path = public, vault as $$
declare v jsonb;
begin
  -- La vraie personne connectée (auth.uid()), jamais l'identité d'un aperçu « voir comme ».
  if auth.uid() is null or not exists (select 1 from profiles where id = auth.uid() and role = 'superadmin') then
    raise exception 'Réservé au super admin';
  end if;
  select jsonb_build_object('identifiant', c.identifiant, 'mdp', s.decrypted_secret, 'maj_le', c.maj_le, 'ok_le', c.ok_le)
    into v
    from national_comptes c join vault.decrypted_secrets s on s.id = c.secret_id
   where c.animateur_id = p_anim and c.actif and c.identifiant <> '';
  if v is null then raise exception 'Aucun compte national branché pour cette personne'; end if;
  update national_comptes set lu_le = now(), lu_par = auth.uid() where animateur_id = p_anim;
  return v;
end $$;
