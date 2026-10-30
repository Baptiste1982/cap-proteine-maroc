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

**📅 Mes réunions (v0.22.0, 29/10/2026)** — demande JB (« un espace pour la gestion des réunions et des comptes rendus, changer le jour, lieux à garder en mémoire ») :
- Onglet `reunions` (`viewReunions`, après Agenda ; masqué en lecture seule). Périmètre = clubs dont l'animateur est `SESSION.animId` ; les directeurs basculent sur « Tous mes périmètres » (`window._reuTous`, clubs `canEditClubId`).
- Migration `20261029200000_reunions_rythme_compte_rendu.sql` (appliquée) : `clubs.lieu_habituel_id`, `rythme_jour` (1 = lundi … 7), `rythme_rang` (0 = chaque semaine, 1..4 = Nième du mois, -1 = dernier), `heure_habituelle` ; `reunions.compte_rendu` (jsonb), `cr_le`, `cr_par`. Droits inchangés (`cap_can_edit_club`).
- `changerJour(id)` (décalages rapides, case « retenir ce lieu et cette heure » → club), `openRythme(clubId)`, `prochaineDate(c)` (après la dernière réunion non annulée et pas avant aujourd'hui), `planifierSuivante(clubId)` (pré-remplit `meetingForm`), `openCR(id)` / `crEnregistrer` (passe la réunion en réalisée), `crBloc` dans la fiche réunion.
- Le canevas du compte rendu (`CR_CHAMPS` : déroulé, décisions, suivi) est PROVISOIRE : JB doit fournir celui du national. Le jsonb évite une migration le jour où il change.
- Barre du bas : 7 onglets (54 px chacun sur iPhone 13). Banc `scratchpad/tools/reunions.mjs` 53/53.

**💬 Espace membre (v0.23.0, 29/10/2026)** — maquette https://claude.ai/artifact/7MmSB7EDmLcqC1npF8z6GQ, clic JB « téléphone + code WhatsApp » :
- Page `membre.html` (à part du CRM, session sous la clé `cap-membre-auth` : se connecter ici ne déconnecte pas le CRM). Connexion `signInWithOtp({phone:'+212…', options:{channel:'whatsapp'}})` puis `verifyOtp({type:'sms'})`, puis RPC `cap_membre_lier()` qui rattache le compte à la fiche dont le mobile correspond (`infos.m_tel`, ou celui de la demande d'adhésion rattachée). Statuts : ok, inconnu, ambigu, en_cours (demande d'adhésion pas encore intégrée). `#demo` = démonstration, code 123456.
- Écrans : annuaire (RPC `cap_annuaire`, champs choisis seulement), fiche, messages, conversation (temps réel), mon profil (RPC `cap_membre_profil` : ce qu'il cherche, téléphone visible, présence dans l'annuaire).
- Migrations `20261029220000_espace_membre.sql` + `espace_membre_lier_adhesion` (appliquées) : `membres.user_id/tel_visible/annuaire_visible/cherche`, `cap_tel_norm`, `cap_membre_id`, table `messages_membres` (RLS : lecture par l'expéditeur et le destinataire, écriture par l'expéditeur vers un membre inscrit ; l'équipe du CRM ne les lit pas), `cap_messages_lus`, publication realtime.
- ⚠ **Sécurité** : `cap_est_equipe()` (une ligne dans profiles) remplace « authentifié » pour lire clubs, réunions, invités, membres, animateurs, lieux, zones et écrire le bucket lieux. Un compte membre ne voit rien du CRM (vérifié en base). Toute nouvelle table du CRM doit exiger `cap_est_equipe()` ou un rôle, jamais `auth.uid() is not null`.
- CRM : section « Espace membre » dans la fiche membre et dans la demande d'adhésion (connecté ou non, bouton « Inviter » = message WhatsApp avec le lien).
- ~~Connexion par code WhatsApp (Twilio)~~ : remplacée en v0.24.0 par le code d'accès donné par l'animateur.
- Bancs `membre.mjs` 51/51, `crm-espace.mjs` 6/6.

**🔑 Accès membre par code (v0.24.0, 30/10/2026)** — JB : « on peut pas faire une messagerie interne ? » (la messagerie l'était déjà ; c'est la connexion par WhatsApp qui demandait Twilio). Clic JB : « code donné par l'animateur ». **Remplace la connexion WhatsApp de la v0.23 : plus besoin de Twilio.**
- Fonction serveur `membre-acces` (verify_jwt, droit = `cap_can_edit_club` du club du membre, appelé avec la session de l'appelant) : crée ou met à jour un compte Supabase Auth dont l'e-mail est fabriqué à partir du mobile (`212661234567@membres.cap-proteine.ma`, jamais d'e-mail envoyé), mot de passe = code à 6 chiffres tiré au hasard, pose `membres.user_id`. Le code n'est stocké nulle part en clair : il s'affiche une fois dans la fiche (`mbCodeAcces`), avec « Envoyer par WhatsApp » (lien, mobile, code) et « Copier le message ». Oubli = « Nouveau code ». Un mobile déjà pris par un autre membre est refusé.
- `membre.html` : mobile + code → `signInWithPassword`. Le membre change son code dans « Mon profil » (`updateUser`, 6 caractères minimum).
- Aucun profil d'équipe n'est créé : le compte ne voit rien du CRM. Pas de trigger sur `auth.users` (vérifié).
- Bancs `membre.mjs` 53/53, `crm-espace.mjs` 8/8.

**🔔 Notifications des messages + invités proposés par les membres (v0.25.0, 30/10/2026)** — clic JB sur ces deux pistes :
- Migration `20261030090000_membres_notifs_invites.sql` (appliquée) : `messages_membres.notifie_le` ; `invites.entreprise/metier/note/propose_par/notifie_le` ; déclencheurs `messages_membres_notifier` et `invites_proposes_notifier` (seulement si `propose_par`) → `membres_notifier(type)` → pg_net vers l'edge **`notif-membre`** (verify_jwt:false, même patron que `notif-adhesion` : ligne < 15 min, réservation atomique de `notifie_le`). RPC `cap_membre_prochaine_reunion`, `cap_membre_proposer_invite` (prochaine réunion non annulée du club, statut « À confirmer », 20 par jour max), `cap_membre_mes_invites`. Vérifié en base dans une transaction annulée.
- `membre.html` : onglet **Inviter** (prochaine réunion, formulaire, « Mes invités » avec statut traduit `STATUT_INV`) ; notifications (carte dans Mon profil, bandeau dans Mes messages, mêmes `sw.js` et clé VAPID que le CRM, abonnement dans `push_abonnements`) ; manifeste `membre.webmanifest` pour l'installer sur l'iPhone (obligatoire pour les notifications iOS). Lien `#c=<membre>` ouvre la conversation.
- `sw.js` : au clic sur une notification, une fenêtre déjà ouverte sur la même page (CRM ou espace membre) est réutilisée ; une notification du CRM ne détourne jamais l'onglet de l'espace membre.
- CRM : invité marqué « espace membre » dans la réunion (entreprise, métier, mot du membre) ; notification à l'animateur du club + superadmin + directeur national, qui ouvre la réunion (`?reunion=<id>`, `ouvrirLienReunion`).
- ⚠ Aucune réunion à venir en base (la dernière date du 31/07) : tant qu'aucune n'est planifiée, l'onglet Inviter dit « pas de réunion planifiée ».
- Ajouts dans la même version (JB : « pas mal de choses qu'on a oubliées ») : RPC `cap_membres_connexions()` (migration `20261030100000`, équipe seulement, lit `auth.users.last_sign_in_at`) chargée par `loadDB` dans un try (jamais bloquante) → `m.vuLe` : fiche « Connecté, dernière fois le … » / « Code créé, jamais connecté », repère `.mb-acc` dans l'annuaire du CRM ; texte de la fenêtre Notifications (adhésions + invités proposés) ; étape « L'espace membre » dans la visite guidée (partie Clubs : 5 étapes).
- Bancs `membre.mjs` 63/63, `crm-espace.mjs` 9/9, `tuto.mjs` 28/28.

**🤝 Recos, présences, renouvellements, relances (v0.26.0, 30/10/2026)** — 4 choix cliqués par JB :
- Migration `20261030120000_recos_presences_renouvellements.sql` (appliquée). Table `recommandations` (de, a, club_id = club du donneur, contact, besoin, statut envoyee|contact|devis|signee|sans_suite, montant ; lecture : les deux membres + l'équipe ; écriture membre par RPC `cap_membre_reco_donner`, `cap_membre_reco_avancer` réservée au receveur ; `cap_membre_recos_club` = total collectif du club, montant compté à la signature). Notifications `reco` (au receveur) et `reco_suivi` (au donneur) par l'edge `notif-membre` (réservation `notifie_le` / `suivi_notifie`).
- Présences : `reunions.presence_code` (RPC `cap_reunion_code`, équipe), table `presences` (unique réunion × membre, mode qr|animateur), `cap_membre_pointer(reunion, code)` ouvert à ±1 jour de la date. QR = `membre.html#p=<reunion>.<code>` dessiné par qrcode-generator 1.4.4 (cdnjs, chargé à la demande, repli : le lien en clair). Bilan pré-rempli avec le nombre de présences.
- Renouvellements : `membres.abonnement_debut` (vide = date d'intégration `created_at`), échéance + 1 an, `relance_renouv_le`. `openRenouvellements()`, section Abonnement de la fiche, ligne dans « À traiter » (≤ 30 jours ou dépassée).
- Relances : `invites.rappel_le` / `suivi_le`. Rappel si réunion aujourd'hui/demain (À confirmer, Intéressé), suivi dans les 7 jours après (Intéressé, À intégrer) avec `adhLink(club)`. Il faut un téléphone sur l'invité.
- Espace membre : onglet **Recos** (5 onglets), liens `#r=recues|donnees` et `#p=…`. Bancs `v026.mjs` 28/28 (+ tous les anciens verts).

**✨ Animations + « À traiter » et membres par région (v0.27.0, 30/10/2026)** — maquette https://claude.ai/artifact/HU7uuQYTw81YM62nhr7QWA (lettres A à K), JB : « code le tout ».
- Régions = `DB.zones` (villes) + « Autres villes » (`regionsDe`). J : `todoRegions(sc)` / `todoClub(c)` remplace la liste des clubs dans `dashATraiter` (filtre `window._todoF`, régions repliées dans `window._todoFerme`). K : `membresRegions(sc)` remplace « Membres par groupe » (état ouvert `window._kOuv`, `kBasculer`) ; billes et fil en pointillés en CSS (`.km-*`), centrées sur l'axe du fil (banc).
- Pop-ups cliquables : `toast(m, kind, act)` (3e argument = fonction, pop-up cliquable 4,8 s) ; `annonce(ico,titre,sous,act)` (descend du haut) pour les nouvelles demandes et recos dans `adhRafraichir` ; `celebrer(ico,titre,gros,lien,act)` + `pluieConfettis()` pour adhésion intégrée, objectif atteint (`dashFete`), affaire signée.
- `navPill()` (pastille `#nav-pill`, recalée par ResizeObserver), `morphOuvrir(w)` dans `openSheet` (clip-path depuis l'élément touché, mémorisé au `pointerdown` ; pas en panneau grand écran), relief des `.ck` au survol souris, `skLignes(n)` à la place de « Chargement… ».
- Bancs `v027.mjs` 33/33 (téléphone + bureau) ; `v09` et `demandes` recalés sur le nouveau dessin.

**↕ Repli auto + plein écran (v0.28.0, 30/10/2026)** — demandes JB :
- `repliArmer(el, fermer)` : une région J (`details.tj-reg`, repliées par défaut, ouvertes dans `window._todoOuv`) ou K (`.km-reg`, `.km-grp`) se referme après `repliDelai()` secondes (localStorage `cap-repli`, défaut 3, 0 = jamais) ; le minuteur s'arrête tant que la souris est dessus (pointerenter/move), repart au toucher ; `repliRearmer(v)` après chaque `render()`. Réglage dans Paramètres → Apparence (`REPLI_CHOIX`, `choisirRepli`).
- `sheetPlein()` : bouton `#sheet-max` (≥ 900 px) passe `#sheet` en `.plein` (de 216 px à droite, contenu centré 1040 px) ; mémorisé pour la session (`sessionStorage cap-plein`), Échap revient au panneau sans fermer.
- Banc `v028.mjs` 21/21 ; `v027` recalé (régions repliées par défaut).

**⚠️ À traiter** :
1. **Tester le front câblé dans un navigateur** (login réel + CRUD) — non testable depuis les sessions Claude Code : l'hôte `*.supabase.co` est bloqué par l'egress policy.
2. **Purger le mot de passe `cap2026`** (reset forcé à la première connexion) — priorité sécurité.
3. Confirmer données réelles vs. seed (`invites` encore vide → aucune saisie terrain à ce jour).
4. Redéployer sur Vercel depuis le repo (après GO explicite de JB). **Photos lieux** : stockées en base64 dans `lieux.photo_url` pour l'instant — migrer vers le bucket Storage `lieux` si le poids des lignes gêne.
