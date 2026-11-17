-- v1.21.0 : remontée automatique des leads du Google Sheet (appliquée le 17/11/2026 : leads_recevoir_sheet + leads_recevoir_notif_leads).
-- Le script Apps Script du classeur (docs/leads-apps-script.gs, fonction envoyerLeads, toutes les 15 min) appelle la RPC
-- cap_leads_recevoir(p_jeton, p_feuille, p_lignes) avec le jeton de reglages.leads_sheet_jeton. Nouveaux leads : insérés
-- « à contacter » (origine 'sheet') + notification aux superadmins par l'edge notif-leads ; leads connus (même nom ou même
-- mobile sur 9 chiffres) : complétés, jamais doublés. Définition complète : pg_get_functiondef en base.
alter table public.leads add column if not exists sheet_vu_le timestamptz;
