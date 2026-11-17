-- v1.25.0 : points sur activité (PSA). Appliquée en prod le 17/11/2026 (psa_creneaux + psa_lien_visio).
-- Le directeur ouvre des créneaux, les animateurs de sa zone réservent par cap_psa_reserver (notifie le directeur via notif-leads).
-- Voir la base pour le corps exact des fonctions cap_psa_gere / cap_psa_reserver / cap_psa_annuler et des policies.
alter table public.psa_creneaux add column if not exists lien_visio text;
