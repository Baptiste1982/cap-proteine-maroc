-- v1.97 : pointage de tout le monde. cap_reunion_reponses rend aussi l'id du membre,
-- pour pointer (table presences) un membre d'un autre groupe qui a répondu « je viens ».
-- Appliquée le 19/11/2026 par remplacement dans la définition existante (pas de DROP).
do $do$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p where proname = 'cap_reunion_reponses';
  if position('''id'', mb.id' in d) = 0 then
    execute replace(d, 'jsonb_build_object(''nom'', mb.nom,', 'jsonb_build_object(''id'', mb.id, ''nom'', mb.nom,');
  end if;
end $do$;
