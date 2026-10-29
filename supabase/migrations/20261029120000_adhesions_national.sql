-- Suivi de l'envoi d'une adhésion vers le CRM national Protéine (fonction national-adhesion).
-- national = { prospect_id, entreprise_id, personne_id, contrat_id, abonnement_id, identifiant,
--              mot_de_passe, url_contrat, url_contrat_papier, statut, etapes[], erreur, maj }
alter table public.adhesions add column if not exists national jsonb;
comment on column public.adhesions.national is 'Envoi vers le CRM national Protéine : identifiants des fiches créées, liens du contrat, journal des étapes.';
