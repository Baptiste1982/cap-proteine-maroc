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

**✅ Fait** : schéma complet, 8 comptes Auth, rôles + RLS, design crimson/or mobile-first. HTML rapatrié dans le repo (`index.html`) et **câblé sur Supabase** (auth réelle `signInWithPassword`, CRUD via les tables, RLS natif). `SEED` en dur + mots de passe `cap2026` en clair **supprimés** du front. RLS animateur audité (helpers `SECURITY DEFINER search_path=public`, cloisonnement `animateur_id = cap_animateur_id()`) : conforme.

**📝 Adhésions en ligne (v0.5.0, 28/10/2026)** :
- `adhesion.html` (page publique, lien envoyé aux futurs membres) : formulaire mobile en 5 étapes qui remplit **dans le téléphone** le PDF officiel `formulaire-adhesion-membre.pdf` (pdf-lib, texte posé aux coordonnées des 34 champs puis champs retirés — l'aplatissement natif de pdf-lib perdait les cases cochées et abîmait le fichier). Envoi : PDF dans le bucket **privé** `adhesions` (anon = dépôt seul) + fiche par la RPC `soumettre_adhesion` (anon n'a aucun accès direct à la table). Échec d'envoi → le membre télécharge/partage son PDF. `?ref=<club_id>` présélectionne le club ; `#demo` = mode démonstration (rien n'est envoyé).
- Maquette publiée (même page en mode démo) : https://claude.ai/artifact/4sy13VXfaZaRq6RWFjC8Ax
- CRM : Synthèse → **📝 Adhésions** (liste, PDF par lien signé, envoi du lien WhatsApp, intégration dans `membres` au format « Prénom Nom » avec `formulaire=true`, suivi « saisie faite dans le CRM national », export CSV / JSON).
- Migration `supabase/migrations/20261028120000_adhesions_formulaire_membre.sql` (table `adhesions`, RPC, bucket). Accès : tous les rôles sauf `visiteur` (`cap_role()`). **✅ Appliquée le 28/10/2026** ; essai réel depuis la page en ligne réussi (fiche « TEST ALIX », passée en `rejetee`).
- ⚠️ **Piège** : le serveur MCP Supabase demande une confirmation pour tout SQL « destructif » (DROP, DELETE, REVOKE…) et elle n'apparaît pas chez JB → l'appel expire. Écrire des migrations sans DROP quand c'est possible ; un vrai DELETE passe par l'éditeur SQL du dashboard.
- **📁 Classeur des PDF (v0.6.0)** : Adhésions → Classeur. Rangement par mois de réception puis par groupe (club du membre intégré, sinon club du lien `?ref=`, sinon « Sans groupe »), adhésions rejetées exclues. Fichiers nommés `NOM Prénom - JJ-MM-AAAA - Groupe.pdf` **au téléchargement** (le stockage garde l'id : le groupe n'est souvent connu qu'à l'intégration). ZIP d'un mois = un dossier par groupe (JSZip 3.10.1 chargé à la demande).
- **Saisie en série dans le CRM national Protéine** (pas d'API, login/mot de passe) : `docs/saisie-en-serie-crm-proteine.md` + robot `outils/saisie-proteine/saisir.mjs` (Playwright sur le PC de JB, JB se connecte lui-même, mode prudent par défaut). La correspondance des champs `correspondance.json` est **vide** : à remplir pendant la séance où JB montre les écrans.
- Supabase : l'organisation est en offre **Pro** (vérifié le 29/10) → pas de mise en pause automatique. (Une note disait l'inverse : fausse. La pause vue le 28/10 date d'avant le passage en Pro.)

**🖱 Synthèse cliquable + micro-animations (v0.7.0, 28/10/2026)** : chaque chiffre de la Synthèse (`dashTile` → `dashDrill(kind, périmètre)`, périmètre `nat`/`reg` mémorisé dans `_dashScope`) ouvre la liste qu'il compte, chaque ligne ouvre la fiche (club, membre, réunion, animateur). Lien d'adhésion propre à chaque club dans sa fiche. Animations : compteurs (`dashCountUp`), barres, cascade, survol, toucher — coupées sous `prefers-reduced-motion`.

**🃏 Cartes Clubs (v0.8.0, 29/10/2026)** : `clubTile(c,i)` (classes `ck-*`, les cartes Équipe gardent `cc-*`) — liseré couleur de ville, statut en pastille, animateur sous le nom, anneau de santé animé (`animateRings`), 2 repères (membres/objectif, prochaine réunion), barre d'objectif, et UNE action cliquable = `clubNextAction` (même règle que la fiche club, exécutée par `clubCardAction`).

**📱 Lignes compactes sur mobile (v0.9.0, 29/10/2026)** — maquette validée par JB (https://claude.ai/artifact/SK8AXrtPxuKnKkvoCHUwQR) :
- Sous 900 px, Clubs, Agenda, Lieux et Équipe s'affichent en lignes compactes (`.rl` / `.rl-row`) : une ligne par élément avec une jauge (`miniG`), un anneau de santé (`ringSm`) et un point d'alerte (`clubTone` : urgent = sans animateur ou sans réunion). Le détail se déplie au toucher (`rowToggle`). À 900 px et plus, les cartes riches restent (`clubTile`, `meetingCard`, `lieu-card`, `animTile`). La bascule se fait dans le JS par `isWide()`, avec un nouveau rendu quand on franchit le seuil.
- Synthèse : un interrupteur National / Régional (`window._dashSc`) au lieu de deux blocs, un encart « À traiter » (`dashATraiter`) et un entonnoir en colonnes (`.funnel`).
- Filtres en pastilles avec leur compte (`fchip`, `lieuVilleChip`) au lieu des menus déroulants. Pastille rouge sur l'onglet Clubs (`navBadges`).
- Banc Playwright `scratchpad/tools/v09.mjs` : 42/42 en taille téléphone et en taille ordinateur.
- Règle de ton : Alix **tutoie** JB, toujours.

**🔗 Connexion au CRM national (v0.16.1 → v0.18.0, 29/10/2026)** :
- Espace Animateur national = `animateur.ma.caproteine.com` (PHP + jQuery, session PHPSESSID, pas d'API). Connexion : POST `/connexion/extranet` (login, password, autoConnect). Les champs de l'assistant de contrat portent un `id` brouillé ; l'identifiant d'origine est dans l'attribut `oldid`.
- **Fonction serveur `national-adhesion`** (Supabase, superadmin) : rejoue en HTTP les requêtes de l'assistant « Envoyer le contrat membre pour signature » : `/personne/enregistrer` + `/entreprise/enregistrer` (nouveau prospect), `/entrepriseProspectMembre/enregistrer`, `/personneProspectMembre/enregistrer`, `/contrat/enregistrer`, `/abonnement/enregistrer`, `/contrat/genererPdf`, puis `/contrat/enregistrer` type=1 pour le papier. Payloads relevés le 29/10 en capturant le vrai navigateur, écritures simulées. Résultat dans `adhesions.national` (jsonb). Bouton dans la fiche d'adhésion du CRM.
- Secrets `CAP_NATIONAL_IDENTIFIANT` / `CAP_NATIONAL_MOT_DE_PASSE` à poser dans Supabase (Edge Functions → Secrets). L'outil MCP `create_edge_function_secret` demande la valeur à JB par une fenêtre qui n'apparaît pas chez lui (même souci que les confirmations SQL).
- Pièges : le champ « Num. RC » du national est la **patente** ; patente, ville RC et capital sont facultatifs pour « Entrepreneur individuel » (1000) et « Profession libérale » (1001) ; listes officielles = 13 catégories, 402 métiers (embarquées dans `adhesion.html`) ; formule standard 9 000 MAD HT (idFormule 14), début d'abonnement au plus à J+14.
- Les PDF de contrat du national sont publics (`app.ma.caproteine.com/uploads/contratMembre/…`) : ne pas faire circuler les liens.
- Essai réel du 29/10 : adhésion fictive de Nawar Mounchit (PURPLE BIRDGE, prospect 629, entreprise 552) → contrat papier n° 119, « En attente de signature » au national. Données fictives dans le national et dans notre base (adhésion `c056ad2a…`, note « ESSAI ») : à nettoyer avec JB.
- Robot Playwright de secours : `outils/saisie-proteine/saisir.mjs` (`--essai` = répétition à blanc).

**🗂 Dossier membre + visite guidée (v0.19.0, 29/10/2026)** :
- `membres.infos` (jsonb, mêmes clés que `adhesions.data`) + table `membre_documents` (membre_id et/ou adhesion_id, type formulaire|contrat|contrat_signe|autre, chemin unique) + bucket privé `membres` (20 Mo, PDF/images). Droits = ceux des membres (`cap_peut_voir_document` / `cap_peut_ecrire_document`). Migration `20261029140000_dossier_membre.sql`.
- Fiche membre (`memberSheet`) : sections Informations (`mbInfosForm`) et Documents (`mbDocsCharger`, `mbDocAjouter`, `mbDocRetirer`) ; le formulaire PDF de l'adhésion liée apparaît d'office. Intégration d'une adhésion : copie `data` dans `infos` et rattache ses documents.
- Fonction `national-adhesion` v2 : action `contrat` (et fin d'`envoyer`) copie le PDF du contrat national dans `membres/adh-<id>/contrat-<n>.pdf`. Le contrat de Nawar (n° 119) n'est pas encore rangé : JB doit cliquer « Ranger le contrat dans le dossier » sur son adhésion (il faut sa session de superadmin).
- Visite guidée (`tutoLancer`, `TUTO_PARTIES`, `tutoEtapes(partie)`) : lancée une fois par compte (`profiles.tuto_vu_le`, RPC `cap_tuto_vu`, migration `20261029150000_profiles_tuto.sql`), après le changement du mot de passe initial ; rejouable dans Paramètres → Aide (`openAide`). Bancs `scratchpad/tools/tuto.mjs` 28/28, `nat.mjs`.
- Nawar Mounchit intégrée le 29/10 comme membre n° 4 de Rabat Prévilège (données fictives d'essai, note « ESSAI ») : compte dans les statistiques tant qu'elle n'est pas retirée.

**🖥 Panneau d'aperçu grand écran (v0.20.0, 29/10/2026)** — demande JB (« beaucoup de vide sur PC », capture de la carte ouverte à droite) :
- Dès 1500 px de large et une fois connecté, `html.rail-on` (`railSync`) : la page s'arrête à `--rail` (`clamp(380px,26vw,520px)`) et `#rail` reste ouvert à droite. Contenu par onglet (`railHTML`) : Synthèse = carte + prochaines réunions + dernières adhésions ; Agenda = 7 jours / ensuite / bilans à faire ; Clubs = à traiter + carte + dossiers incomplets ; Lieux = réunions sans lieu ; Équipe = prochaines réunions + clubs sans animateur. Rendu à chaque `render()`.
- Les fiches gardent le même `#sheet` : en grand écran la CSS le loge dans le panneau, sans voile (`.sheet-bg` masqué), la page reste cliquable. Le changement de mot de passe forcé garde la surimpression (classe `force` posée par `openSheet` quand `_mdpForce`). Sous 1500 px, rien ne change.
- Banc `scratchpad/tools/rail.mjs` 23/23 (2000 px et 1440 px).

**👥 Annuaire des membres + qui est connecté (v0.21.0, 29/10/2026)** :
- Onglet **Membres** (`viewMembres`, entre Clubs et Lieux) : annuaire de tout le réseau, recherche multi-mots insensible aux accents (`mbIndex` : nom, spécialité, `infos.metier/ent_nom/ent_activite/m_fonction/ent_ville`, club, ville), filtre ville, carte → `memberSheet`, bouton appeler si `infos.m_tel`. La frappe ne rerend que `#mb-res` (le champ garde le focus).
- **Présence** : migration `20261029190000_presence_comptes.sql` (prod `20261029122311`) — `profiles.vu_le`, RPC `cap_ping()` (appelée au démarrage puis chaque minute, appli visible) et `cap_qui_connecte()` (superadmin + directeur_national, sinon erreur). Voyant `#online-pill` « N en ligne » (en ligne = vu < 3 min), feuille `openQuiConnecte`. Pas de REVOKE dans la migration (l'outil MCP bloque les ordres « destructifs »).
- Compte **Ghita** (bureau national, bras droit du directeur national) créé le 29/10 : identifiant `ghita`, rôle `directeur`, zone Rabat · Salé · Kénitra → voit tout le réseau, modifie et voit les adhésions sur RSK. Mot de passe transmis par JB, jamais écrit ici.
- Banc `scratchpad/tools/membres.mjs` 37/37 (2000 px et iPhone).
- **Fil d'Ariane** (fin du script principal) : fiches = `_fil`, les ouvreurs de `FIL_FICHES` sont enveloppés (`filNoter`) ; une fiche ouverte depuis une fiche (clic capturé dans `#sheet`) s'empile, sinon fil neuf ; rouvrir une fiche du fil y remonte. Rendu dans `#fil-fiche` par `openSheet`, vidé par `closeSheet`. Pages = `_filPage` (via `go`) : le menu (`#nav`) remet à zéro, un lien s'empile ; rendu en tête de `.page`. ⚠ Une nouvelle fonction qui ouvre une fiche doit être ajoutée à `FIL_FICHES`, sinon elle n'apparaît pas dans le fil. Banc `fil.mjs` 28/28.
- **Date et heure** : grande horloge dans le bandeau d'accueil (`dashBonjour`, éléments `[data-hor]` tenus par `horlogeMaj`) ; `#tb-clock` en haut des autres pages (masqué sur la Synthèse). Format unique `horlogeTxt()`.
- **Demandes à traiter** (JB : « notification reçue au téléphone, je ne la vois pas sur le PC ») : la cause était que `DB.adhesions` n'était lu qu'à la connexion. `adhRafraichir()` relit la table chaque minute (avec la présence) et au retour sur l'appli, toast si nouvelle. Bouton `#dem-btn`, bloc `dashDemandes()` en tête de Synthèse, `railDemandes()` en tête du panneau.
- **PDF tamponné** : `adhTamponner(blob,a)` (pdf-lib chargé à la demande) écrit « Groupe » et « Responsable du groupe » à droite de « Informations contrat », page 1, à chaque ouverture/téléchargement/ZIP (`adhBlob`, `adhPdf`). Le fichier stocké n'est pas modifié. Banc `demandes.mjs` 22/22.
- Micro-animations (bloc CSS `/*v024*/`) : cascade d'entrée `.page>*`, `#sheet-content>*`, `.rail>*`, survols. JB trouve encore le CRM « trop classique, plat, y compris les dispositions » : piste suivante = maquette de directions à cliquer.
- **À terme (demande JB)** : un chat entre membres, en messages directs seulement, sans groupes. Les membres n'ont pas encore de compte : à cadrer le jour où ils en auront un.

**⚠️ À traiter** :
1. **Tester le front câblé dans un navigateur** (login réel + CRUD) — non testable depuis les sessions Claude Code : l'hôte `*.supabase.co` est bloqué par l'egress policy.
2. **Purger le mot de passe `cap2026`** (reset forcé à la première connexion) — priorité sécurité.
3. Confirmer données réelles vs. seed (`invites` encore vide → aucune saisie terrain à ce jour).
4. Redéployer sur Vercel depuis le repo (après GO explicite de JB). **Photos lieux** : stockées en base64 dans `lieux.photo_url` pour l'instant — migrer vers le bucket Storage `lieux` si le poids des lignes gêne.
