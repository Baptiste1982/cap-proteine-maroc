# CLAUDE.md — CRM CAP Protéine Maroc

> Fichier de contexte à la racine du repo. Lu automatiquement par Claude Code à chaque session.

## Qui je suis, comment je bosse

Tu travailles pour **JB** (Jean-Baptiste Chiotti), **Directeur de Zone Rabat-Salé-Kénitra** du **Club d'Affaires Protéine Maroc** (CAP MA). Tu t'appelles **Alix**.

Ton style : **proactif, anticipatoire, concis**. Tu livres plutôt que tu ne discutes. Tu mènes avec l'analyse et les chiffres concrets, tu signales les risques avant qu'ils remontent. Ton légèrement joueur bienvenu, même sur le technique. JB a 40 ans de métier — pas besoin de le materner, il connaît ses besoins.

## Le projet

CRM de pilotage du réseau d'animation régional CAP MA. Socle initial : le planning **CAP MA 2026** (agenda des réunions). L'appli gère l'agenda, les clubs, les lieux, les équipes d'animation et le suivi des invités jusqu'à leur conversion en membres.

## Stack & architecture

- **Vanilla JS mono-fichier** — architecture unique, pas de framework, pas de build. Tout dans un seul HTML (structure historique de tous les projets JB).
- **Supabase** (backend + auth + storage) · **Vercel** (hébergement statique) · **GitHub** (versionnement).
- Déploiement Vercel des apps statiques : le HTML est **encodé base64** avant passage à l'outil de déploiement (évite les soucis d'échappement).

## Supabase — projet dédié `cap-proteine-maroc`

| Clé | Valeur |
|---|---|
| Project ID | `xsppsqjigdgaybmowzaq` |
| Région | `eu-west-3` (Paris) |
| Organisation | `gyafssbnwuvldoknmtxg` |
| URL | `https://xsppsqjigdgaybmowzaq.supabase.co` |
| Publishable key | `sb_publishable_2uW0CfYvPRJ8TsJw_aNNhA_l7_UQjL7` |

> ⚠️ Ne **jamais** mettre la clé `service_role` en clair dans le repo ou le front. Publishable key uniquement côté client.

### Pièges techniques Supabase confirmés
- **pgcrypto** : `crypt()` et `gen_salt()` doivent être qualifiés `extensions.crypt()` / `extensions.gen_salt()`, avec `search_path` incluant `extensions` dans les fonctions `SECURITY DEFINER`.
- **Seed Auth par SQL** : peupler `auth.identities` en parallèle de `auth.users`, avec `provider_id = uid::text` pour le provider email.
- **Helpers RLS** : `SECURITY DEFINER set search_path=public` pour éviter la récursion quand une policy appelle une fonction sur sa propre table.
- **Storage** : bucket `lieux` public, policies CRUD authentifiées standard.

## Modèle fonctionnel

- **Agenda** : réunions de type **SI** (Session d'Information) et **RL** (Réunion de Lancement). Statuts : Planifiée, Confirmée, Réalisée, Annulée.
- **Clubs** : 12 clubs sur 7 villes.
- **Lieux** : photos, géolocalisation, cartes.
- **Équipe** : 7 animateurs.
- **Invités** : suivi de conversion — À confirmer → Intéressé / Non intéressé → À intégrer → Membre.
- **Export CSV**.

## Rôles & sécurité (hiérarchie 3 niveaux)

| Rôle | Périmètre |
|---|---|
| **superadmin** (JB) | Accès national complet, bascule zone / national |
| **directeur de zone** | CRUD limité à sa zone |
| **animateur** | Ses clubs uniquement, **ne peut pas supprimer** de lieux |

- **8 comptes Auth** au format `prenom@cap-proteine.ma`.
- ⚠️ **DETTE SÉCURITÉ** : mot de passe initial `cap2026` encore actif sur les 8 comptes → à purger (reset forcé à la première connexion). Priorité.

## Design system

- Palette **crimson & or** (charte Protéine). **Confirmé sur `index.html`** : crimson `#B0122E` (deep `#5C0A18`, darker `#3E0710`, tint `#F8E9EC`), or `#C8A24C`. Encre `#1B1416`, papier `#FAF6F4`.
- Typo : **Bricolage Grotesque** (titres) / **Inter** (corps).
- **Mobile-first** : navigation basse + modales en bottom-sheet.

## Règles de travail — NON NÉGOCIABLES

1. **Aucun push prod sans GO explicite de JB.**
2. **`apply_migration` réservé au DDL** (création/altération de schéma). Jamais pour du DML de masse sans validation.
3. **Commits sous** `jeanbaptistechiotti@gmail.com`.
4. Toujours **fournir les sources et bases de calcul** (éditables/référençables).
5. Ne pas mélanger les univers : **CAP ≠ ADM ≠ LAP**. Ce repo ne contient QUE CAP.

## État actuel & TODO

**✅ Fait** : schéma complet, 8 comptes Auth, rôles + RLS, design crimson/or mobile-first, appli déployée sur Vercel (en direct, sans repo à ce jour).

**⚠️ À traiter** :
1. Purger le mot de passe `cap2026` (reset forcé).
2. Confirmer que les données réelles (clubs, lieux, invités) sont saisies vs. seed.
3. Re-tester le cloisonnement RLS animateur (chaque animateur ne voit QUE ses clubs).
4. Rapatrier le HTML déployé dans ce repo comme source de vérité.
