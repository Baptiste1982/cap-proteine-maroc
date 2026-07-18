# CRM CAP Protéine Maroc

CRM de pilotage du réseau d'animation régional du **Club d'Affaires Protéine Maroc** (CAP MA).
Socle : planning **CAP MA 2026**. Gestion de l'agenda, des clubs, des lieux, des équipes d'animation
et du suivi des invités jusqu'à leur conversion en membres.

## Stack

- **Front** : Vanilla JS mono-fichier (un seul `index.html`, pas de framework, pas de build).
- **Backend** : Supabase (base de données, auth, storage).
- **Hébergement** : Vercel (statique).
- **Versionnement** : GitHub.

## Structure

| Fichier | Rôle |
|---|---|
| `index.html` | Application complète (à rapatrier depuis la prod Vercel). |
| `CLAUDE.md` | Contexte projet — lu automatiquement par Claude Code. |
| `.env.example` | Modèle de configuration Supabase (URL + publishable key). |

## Configuration

1. Copier `.env.example` en `.env`.
2. Renseigner `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY`.
3. Ne **jamais** committer le `.env` ni la clé `service_role`.

## Déploiement

Déploiement statique sur Vercel. Le HTML est encodé en base64 avant passage à l'outil de déploiement.
**Aucun push prod sans validation explicite.**

## Rôles

| Rôle | Périmètre |
|---|---|
| superadmin | Accès national complet. |
| directeur de zone | CRUD limité à sa zone. |
| animateur | Ses clubs uniquement, sans suppression de lieux. |
