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

- Palette **crimson & bleu ardoise** (charte Protéine ; l'or `#C8A24C` remplacé par le bleu ardoise `#5B7FA3` en v0.44.2, à la demande de JB) : crimson `#B0122E` (deep `#5C0A18`, darker `#3E0710`, tint `#F8E9EC`). Encre `#1B1416`, papier `#FAF6F4`.
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

**✦ Constellation + Synthèse en chapitres (v0.29.0, 30/10/2026)** — JB a rejeté deux refontes de la Synthèse (« pas original ») puis tranché : « on garde l'affichage actuel et on l'améliore », la constellation sert à PRÉSENTER le réseau, avec des animations au survol des nœuds.
- Synthèse : `dashSec(ton,ico,titre,sous,html)` encadre quatre chapitres (chiffres crimson, à traiter ocre, croissance vert, équipe bleu ; bloc CSS `/*v029*/`). `dashBlock(st,sc,"chiffres")` ne rend que tuiles + objectif + activité + recos, `dashCroissance` = courbe + membres par région. Les petits titres sont en `.dash-h`. Grand écran : interrupteur National/Régional en pleine largeur, puis `.dash-cols` (gauche chiffres + croissance, droite à traiter + équipe ; `#dash-todo` reste dans la 2e colonne).
- `openConstellation()` (bouton « ✦ Le réseau » des outils) : plein écran `#cst-o`, régions `regionsDe`, groupes `todoClub` + nb de membres, état `cstEtat` (sans animateur, bilans, ok, a des membres, sans membre). Animations : tracé des liens, astres qui partent du centre de leur région, flottement, comètes vers le centre (une par membre, 6 max par région), survol = astre grossi + onde + lien allumé + reste effacé + fiche qui suit ; toucher = panneau du groupe → `openClub`. Échap ferme ; bouton Diaporama → `openPresentation`.
- ⚠ Piège corrigé : `var(--deep)`, `--darker`, `--or`, `--tint` n'existent pas (tokens réels : `--crimson-deep`, `--crimson-darker`, `--gold`, `--crimson-tint`) → la carte des recos était blanche sur blanc depuis la v0.26.
- Bancs `cst.mjs` 18/18 (téléphone + bureau), tous les anciens verts.

**🔔 Notifications en bas à droite + visite guidée à jour (v0.29.1, 30/10/2026)** — `notifPile()` crée `#notifs` (fixe, bas droite ; sur téléphone pleine largeur au-dessus de la barre). `annonce()` et `celebrer()` y empilent leurs cartes (plus de voile plein écran pour la célébration, les confettis restent). Le toast passe aussi en bas à droite à partir de 900 px. Visite guidée : étapes « Quatre chapitres », « Le réseau en constellation », « Les notifications » ; la visite fait défiler vers le haut si la cible est au-dessus (`top<60`). Bancs `notifs.mjs` 14/14, `tuto.mjs` 28/28.

**📍 Localisation Google Maps / Waze (v0.30.0, 30/10/2026)** — JB a collé un lien Google dans le champ Adresse d'un lieu.
- Colonne `lieux.lien_carte` (migration `20261030170000_lieux_lien_carte.sql`, appliquée). Champ « Localisation Google Maps ou Waze » (`#l-lien`) : `carteCoords(url)` lit `!3d…!4d…`, `q=/ll=/destination=`, `ll.` (Waze live-map), `@lat,lng`, le geohash des liens `waze.com/ul/h…` et « lat, lng » nu. Lien collé dans Adresse → déplacé (`lieuAdresseLien`).
- Liens courts (maps.app.goo.gl…) et pages Google sans coordonnées → fonction serveur **`lien-carte`** (verify_jwt:true, v1 déployée) qui suit les redirections (consentement Google compris) sur une liste d'hôtes de cartes, et renvoie l'adresse finale + lat/lng (`approx:true` si lu dans l'état initial de la carte : à vérifier). Non testée en réel d'ici (supabase.co bloqué).
- `lieuItineraire(l)` : boutons Google Maps (`/maps/dir/?api=1&destination=`) et Waze (`waze.com/ul?ll=…&navigate=yes`, sinon recherche par adresse) dans la fiche lieu et la fiche réunion. Banc `lieu.mjs` 18/18.

**📥 Onglet Demandes + menu animé (v0.31.0, 30/10/2026)** — JB : « les demandes de postulations dans un nouveau menu, rends l'interface smart », « animation au passage et au clic inventive ».
- Onglet `demandes` (`viewDemandes`, entre Membres et Lieux, masqué pour `visiteur` dans `demBadge`, masqué sous 900 px : le bouton `#dem-btn` du haut y mène). `dmCols()` : à intégrer (`adhEtape`=1), à saisir au national (2), terminées (3, 12 dernières) ; `dmProchaine()` = la plus ancienne en retard sinon la plus ancienne ; recherche `window._dmQ` (`dmChercher` ne rerend que `#dm-pipe`) ; filtre `window._dmF==="retard"` ; colonne active au téléphone `window._dmCol`. Clic carte = `dmOuvrir` (onde + enfoncement puis `adhDetail`).
- `openAdhesions(f)` mène désormais à l'onglet (l'ancienne fenêtre reste sous `openAdhesionsFiche`, utilisée pour « Rejetées ») ; `adhCharger()` relit la table ; `adhDetail` ouvre lui-même la fiche (avant, il comptait sur la fenêtre déjà ouverte).
- Menu : animations CSS par icône au survol (`icDash`, `icFeuille`, `icEnveloppe` sur `.i-env`…), trait or au survol (≥ 900 px), clic = `.clic` + `.nav-anneau` + 7 `.nav-gerbe` (écouteur en capture). Pastille de l'onglet qui saute quand le nombre change (`.nav-badge.pop`). Banc `dmd.mjs` 22/22.

**✨ Synthèse vivante, affichage au choix (v0.32.0, 30/10/2026)** — maquette validée par JB (https://claude.ai/artifact/AaoDzhXutkYQg3ENBtnjcX, « intègre-le comme un affichage optionnel »). Après deux refus (« standard », « plat ») et un rejet du fond sombre.
- Réglage Paramètres → Apparence « Affichage de la Synthèse » (`synthMode()`, localStorage `cap-synth`, défaut classique, `choisirSynth`). En vivante, `dashBlock` remplace les 6 tuiles par `dashBento(s,sc)` (classes `vb-*` : grande carte rouge membres sur 3 rangs avec courbe 6 mois + bille, gris clubs avec pastilles, alerte encadrée si 0 réunion, or paiement avec anneau, pointillés si 0 invité, rose sans animateur avec noms / vert si aucun). Chaque carte ouvre `dashDrill`.
- `vbBrancher(v)` (appelé dans `render` sur la Synthèse) : compteurs mécaniques `vbOdo`/`vbRouler` (rejoués au survol souris), encre `.vb-encre` partie du point d'entrée de la souris (`--ex/--ey`), bandeau `.hello.vivant` (lumière mobile via `@property --hax/--hbx`, message du jour `vbMessages()` tapé par `vbEcrire`). Banc `vive.mjs` 19/19.

**📆 Planifier en série, bilans express, embarquer l'équipe (v0.33.0, 30/10/2026)** — JB a coché ces trois priorités après l'état des lieux du 30/10 : 0 réunion à venir (dernière le 31/07), 13 bilans en retard, 0 invité, 0/9 membres dans l'espace membre, 0/9 payés, 10/12 comptes jamais connectés, 7 animateurs encore sur `cap2026`, aucun mobile d'animateur en base.
- `openPlanSerie()` (bouton dans Mes réunions, appel « Aucune réunion à venir », carte alerte de la Synthèse vivante) : `psDeviner(c)` reprend le rythme du club ou le devine (jour de la dernière réunion, rang = semaine du mois ou « dernier », hebdo si écart ≤ 10 j, heure, lieu, type) ; `psDates(c,o,mois)` part du lendemain de la dernière réunion ; dates retirables (`psBasc`) ; `psCreer` enregistre le rythme sur le club puis insère les réunions en lot (statut planifiée, animateur du club).
- 🐛 `nthJour` ne normalisait pas un mois > 11 (`getMonth()===m` faux en janvier) : corrigé, ça touchait aussi `prochaineDate`.
- Bilans : `_bilSerie` (total, faits, passés), barre `.bil-prog`, `bilPasser`, champs `.bil-in` saisissables (`bilSaisie`), célébration au-delà de 2 bilans.
- Migration `20261030200000_embarquement_equipe.sql` (appliquée) : `profiles.mdp_provisoire`, `invite_le` ; `cap_mdp_a_changer` vrai aussi si provisoire ; `cap_mdp_change_fait()` (appelée après `changePassword`) ; `cap_marquer_invite(id)` et `cap_equipe_etat()` réservées au superadmin (testé : un animateur est refusé). `openEmbarquer()` : `mdpProvisoire()` (deux mots marocains + 2 chiffres, aléatoire crypto), `adminCall set_password` (edge `admin-users`, vérifie le superadmin), message `embMessage`, mobile enregistré sur `animateurs.tel`. Le mot de passe ne s'affiche qu'une fois. `DB.aEmbarquer` → ligne dans « À traiter ».
- Bancs `ps.mjs` 22/22, `bil.mjs` 10/10, `emb.mjs` 18/18.

**🗓 Agenda en calendrier (v0.34.0, 30/10/2026)** — JB (capture de l'agenda en liste) : « un grand calendrier mensuel ou hebdomadaire, comme pour Atelier Design, semaine ou mois suivant téléphone ou PC, flèches droite-gauche avec une micro-animation ».
- `calVue()` (localStorage `cap-agvue` : liste|semaine|mois ; défaut semaine < 900 px, mois au-delà), `calModes()`, `calendrier(list)` (section `#cal.cal-v-<vue>`, ⚠ pas `cal-mois` : c'est la classe de la grille du mois), `calAller(sens,btn)` (période ±1, 0 = aujourd'hui ; flèche `.pousse` + glissade `slide-g/d/z`), `calMaj()` ne remplace que `.cal-t` et `.cal-corps` (sinon la flèche animée est détruite), `calTouch` (balayage > 60 px), `calJour` (détail d'un jour au téléphone), `calNouvelle(iso)` (meetingForm prérempli). Mois : 7 colonnes, puces `calPuce` sur PC (3 par jour + « +N »), points colorés au téléphone. Semaine : 7 colonnes sur PC, une ligne par jour au téléphone, + pour planifier.
- Banc `cal.mjs` 25/25.

**👥 Espace « Mon groupe » (v0.35.0, 30/10/2026)** — JB : « un panel de gestion de son groupe complet : membres, métiers représentés et recherchés, comptes rendus, calendrier, réunions faites, stats, chiffres d'affaires échangés ».
- L'onglet `reunions` (libellé « Groupe ») rend `viewGroupe()` ; `viewReunions` reste dans le code, plus appelé. Groupe affiché = `grpClub()` (`window._grpId` parmi `reuClubs()`), sous-onglet `window._grpOng` (`GRP_ONGLETS` : bord, cal, membres, cr, affaires), `grpAller(id,ong)` y mène (bouton « Espace du groupe » de `openClub`). Chiffres calculés par `grpDonnees(c)` (réunions, présences moyennes des bilans, invités, adhésions obtenues, recos et CA signé).
- Migration `20261030230000_espace_groupe.sql` (appliquée) : `clubs.metiers_recherches` jsonb (liste officielle `METIERS_OFF`, copiée d'`adhesion.html`) ; policy `recos_equipe_ajouter` : l'équipe d'un club peut noter une recommandation (`grpRecoForm`, `grpRecoSauver`), le déclencheur de notification au receveur s'applique.
- ⚠ La classe `.gp` existait déjà (avatars empilés) : le pipeline utilise `.gpi`. Banc `grp.mjs` 40/40.

**🗄 Candidatures archivées avec motif + panneau de droite refermable (v0.36.0, 09/11/2026)** — JB : « supprimer une candidature avec motif stocké en archives » et « pouvoir fermer la side bar de droite ».
- Rien n'est effacé : `adhArchiverForm(id)` (bouton 🗄 sur la carte Demandes, « Retirer et archiver » dans `adhDetail`) → `adhArchiver` passe en `statut='rejetee'` (affiché « Archivée ») + `archivee_le`, `archive_motif` (`ADH_MOTIFS` + précision), `archive_par` ; option « supprimer aussi la fiche membre » si la candidature était intégrée. `openArchivesAdh()` (chip « 🗄 Archives »), `adhRestaurer` (retour en `integree` si la fiche membre existe, sinon `recue`). Migration `20261109120000_adhesions_archive_motif.sql` (appliquée).
- Panneau de droite (≥ 1500 px) : croix `#sheet-x` sur chaque fiche (+ Échap, sauf mot de passe forcé, plein écran, visite guidée) ; ✕ `.rail-x` dans l'en-tête de l'aperçu → `railBasculer(false)` (localStorage `cap-rail=off`, `isRail()` le respecte, `railGrand()` = écran assez large) ; onglet `#rail-tab` « ‹ Aperçu » au bord droit pour rouvrir.
- Bancs `arch.mjs` 11/11, `rail2.mjs` 17/17 ; `adh.mjs` recalé (libellé Archives).
- Nettoyage du 09/11 : essais TEST ALIX et Nawar (adhésion + fiche) supprimés ; JB a supprimé à la main Reda-Allah Sibari, Tarek Amar et Abderazak DINIA (fausses données). Essai de Ghita archivé et PDF d'essai effacés le même jour (voir v0.37.0). Le contrat d'essai n° 119 existe encore au CRM national.

**⇄ Groupe de destination d'une candidature (v0.37.0, 09/11/2026)** — JB : « préciser le groupe de la postulation en attente de validation au national, et pouvoir changer quelqu'un de groupe s'il y a un raté ».
- `adhGroupeBloc(a,mb,peut)` en tête de `adhDetail` : groupe (= club de la fiche membre si intégrée, sinon `ref`), ville, animateur, origine (lien du groupe / intégration / aucun). `adhChangerGroupe(id)` (aussi « ⇄ changer » sur la carte Demandes, `.dm-grp-ch`) : groupes par ville (ceux que l'on peut modifier), raison facultative ; `adhGrpEnregistrer` met à jour `adhesions.ref`, déplace la fiche membre (`club_id` + numéro en fin de liste) et ajoute une ligne datée dans `adhesions.notes`. Le tampon du PDF et la saisie au national suivent (`adhGroupe`). Aucune migration.
- Ménage du 09/11 (suite) : essai de Ghita archivé (motif) et fiche membre supprimée ; 3 PDF d'essai effacés du stockage par une fonction serveur à usage unique `nettoyage-essais`, neutralisée ensuite (v2 : répond 410). Surveillance horaire de l'arrivée de la demande de Nawar : scheduled task `trig_01PUq9r12MMjDvmMm7EkLMoo` (à désactiver une fois la demande arrivée).
- Banc `chgrp.mjs` 18/18 ; `nat.mjs` recalé (libellé Archives).

**🌍📍 Deux vues : nationale et régionale (v0.38.0, 09/11/2026)** — JB : « deux modes de vue avec des vues complètement dédiées et des choix marqués » ; maquettes https://claude.ai/artifact/ATrmpSiT1tXwv5dXtZbPor (deux vues) et https://claude.ai/artifact/3P3nsu2v7eiQq9SeSvsiuj (trois pistes régionales) ; clics JB : bouton en haut seulement, tout filtré + accueil groupes + identité visuelle + menu adapté, bascule réservée à la direction nationale, « le cockpit en haut et le planning en dessous ».
- `vueMode()` ('nat'|'reg', localStorage `cap-vue`) ; `vuePeutBasculer()` = superadmin, directeur_national ; les autres rôles (sauf visiteur) sont forcés en 'reg'. Région = `vueRegion()` (zone de `SESSION.zoneId`, sinon `REGION_RSK`). Bascule `#vue-bascule` dans la barre du haut (`vueChoisir`, `vueAppliquer` pose `body.vue-nat`/`vue-reg`, libellé du menu « Ma région »/« Synthèse », `#tb-region`).
- Filtrage : `avecVue(fn)` rend avec une copie filtrée de DB (`vuePortee` : clubs de la région, leurs réunions, membres, demandes — sans groupe comprises —, recos, présences, lieux, animateurs, zones). Appliqué dans `render` (vue, badges, panneau de droite) et à `mbFiltrer`, `dmChercher`, `dashDrill`, `kBasculer`, `calMaj`. Les écritures restent sur le vrai DB. ⚠ Une nouvelle fonction qui redessine une partie de page à partir de DB doit passer par `avecVue`.
- Accueil régional `viewRegion()` (classes `vr-*`) : bandeau + 4 chiffres, « À faire dans la région », tableau des groupes trié (sans réunion à venir, puis bilans, puis à faire, puis à jour ; ligne → `grpAller`), planning `vrMois()` (−6 à +3 mois) avec cases réalisée/prévue/bilan/annulée/« + ». Accueil national = Synthèse avec bandeau `.vn-band` (plus d'interrupteur `.seg-sc` pour ceux qui ont la bascule).
- ⚠ Au téléphone la bascule n'affiche que ses icônes (≤ 600 px) : en texte elle faisait déborder la barre du haut et toute la page. Bancs `vues.mjs` 38/38 ; `v09` et `demandes` recalés ; 20 bancs verts.

**✍ Spécialité libre dans le formulaire d'adhésion (v0.39.0, 10/11/2026)** — JB : « plein de gens ne trouvent pas leur métier dans la liste » (ex. Abderrazak, construction, n'a trouvé que « Constructeur Maisons individuelles » ; il veut « tous corps d'état, TCE »).
- `adhesion.html` : champ `metier_precis` sous le métier (120 car.), facultatif, obligatoire si le métier choisi est « - Autre - » (`majPrecis`, contrôle dans `validate(1)`). Le métier officiel reste exigé (le national en a besoin) et c'est lui seul qui part au CRM national.
- PDF : `metierLigne(d)` = « métier · spécialité » (la spécialité seule si « - Autre - »). Le champ Métier du PDF fait toute la largeur : même 120 caractères tiennent. Repli si la ligne ne tenait pas à 7 pt : métier officiel sur la ligne, « Spécialité : … » en tête des commentaires.
- CRM : `adhMetier(d)` (spécialité, sinon métier, sinon l'activité si « - Autre - ») pour les cartes Demandes, la spécialité du membre à l'intégration et `mbMetier` ; champ dans la fiche de demande, l'export et la recherche. Banc `precis.mjs` 12/12.

**📱 Icône Protéine sur l'écran d'accueil (v0.39.1, 10/11/2026)** — `icone-180/192/512.png` = globe + « PROTEINE » en crimson sur fond blanc (tirés de `logo-proteine.png`), liens en `?v=2` (manifestes, apple-touch-icon, `sw.js`) ; `adhesion.html` a aussi son apple-touch-icon. L'ancien globe rouge sur blanc sert toujours DANS l'appli sous `logo-globe-512.png` / `logo-globe-192.png` (connexion, constellation, présentation, PDF). Un téléphone qui a déjà l'icône garde l'ancienne : retirer puis réajouter.

**🔐 Déconnexion locale (v0.39.2, 10/11/2026)** — JB : « Session invalide » à l'envoi au national. Cause lue dans les journaux Auth : `signOut()` (portée globale par défaut) sur l'iPhone à 15:36 UTC a fermé AUSSI la session du PC ; le PC gardait un jeton dont la session n'existait plus (`session_not_found`). Tous les `signOut` (index.html, membre.html) passent en `{scope:"local"}`. `natSessionOk` vérifie la session côté serveur (`getUser`) avant l'aperçu national ; `natErr` traduit « Session invalide » + bouton « Se reconnecter ».

**🚀 Envoi au national (v0.40.0, 10/11/2026)** — JB : « une zone où je retrouve facilement toutes les demandes à envoyer au CRM national une fois traitées au niveau régional » ; clics : onglet dans Demandes, bouton « Signé » à la main.
- Demandes : bascule `dmVueSeg()` (`window._dmVue` 'pipe'|'nat'). En 'nat', `dmPipeHTML` rend `natPipeHTML()` : `natEtat(a)` (seulement `statut='integree'`) = envoyer (pas de `national.contrat_id` ni `saisie_proteine_le`) / attente / signe (`national.signe_le`). `natCols()`, `natCarte` (reçue, envoyée, n° de contrat, signé le ; PDF du contrat `national.contrat_pdf`), `natResume()` (+ rappel des demandes pas encore intégrées), colonne active au téléphone `window._natCol`.
- `natEnvoyer(id)` = `adhDetail` + `adhNational` (superadmin seulement ; les autres voient la demande). `natSigne(id,oui)` écrit `national.signe_le/signe_par` (jsonb fusionné, sans migration) et pose `saisie_proteine_le` s'il manquait. Banc `envnat.mjs` 30/30.

**🔄 Suivi au national : annuaire + signatures (v0.41.0, 10/11/2026)** — JB : « savoir quand les contrats sont signés côté national », « créer dans le carnet d'adresses du national les gens qui remplissent le formulaire », « les numéros de contrat » et « un bouton vers l'état des signatures » ; clic : chaque matin + bouton (mis en place chaque heure 8h-21h).
- ⚠ Les secrets `CAP_NATIONAL_IDENTIFIANT` / `CAP_NATIONAL_MOT_DE_PASSE` n'existaient PAS avant le 10/11 (liste vide vue par JB) : il les a posés lui-même dans le dashboard. Le contrat n° 119 du 29/10 n'est donc pas passé par cette fonction.
- Fonction **`national-suivi`** (verify_jwt:false ; accès = session superadmin, ou en-tête `x-suivi-jeton` vérifié par `cap_national_jeton_ok`, jeton dans le coffre `national_suivi_jeton`). ① Annuaire : demandes non archivées sans `national.prospect_id` → recherche par e-mail (`/personneProspectMembre/listerAll`) sinon création (`/personne/enregistrer` profil 10 + `/entreprise/enregistrer`), 10 par passage, notées `prospect_id/entreprise_id/annuaire/annuaire_le`. ② Signatures : lit `/prospectMembre/lister` (après GET `/prospectMembre/indexAttenteSignature`, colonnes DataTables nommées, sinon 500 côté national et e-mail à leur support) et `/membre/lister` ; contrat `isSigne` ou sorti de l'attente avec l'entreprise membre → `signe_le` + push aux superadmins ; sinon `etat_signature`, `verifie_le`. pg_cron `national-suivi` `5 7-20 * * *` → `cap_national_suivi_lancer()`.
- Front : `natVerifier` (bouton « 🔄 Vérifier au national »), `natDerniereVerif`, `natLienNational` / `NAT_CHEMINS` (le national charge ses écrans dans son accueil : lien vers `/connexion/extranet` + chemin écrit), n° de contrat national, état et fiche annuaire sur `natCarte` et `adhNationalBloc`.
- Au national le 10/11 : en attente 121 (Abderrazak), 122 (Reda), 119 (Nawar, essai) ; Chrystel retrouvée dans l'annuaire (n° 624) ; aucun membre dans le réseau 20.

**✍️ Miroir du national (v0.41.1, 10/11/2026)** — JB : « le bouton mène à la page d'accueil, il faudrait la bonne page ». Le national n'a PAS d'adresse par écran (menu `#btProspectsMembres` → `$.ajax('/prospectMembre')` dans `#corpsIndex`) : aucun lien direct possible. Action `miroir` de `national-suivi` (attente + membres, lecture seule ; PDF `contratPapier-<nomFichier>.pdf`), `natMiroir(contratId)` dans le CRM (superadmin ; contrat visé surligné, lien vers notre demande, n° 119 = essai). Action `regarder` (lecture seule d'une page du national) gardée pour les relevés futurs. Banc `envnat.mjs` 36/36.

**🏢 Plus de doublon d'entreprise à l'envoi (national-adhesion v4, 10/11/2026)** — JB : « dans Sans contrat il n'y a que Reda ». Normal pour Dinia et Nawar (avec un contrat, la fiche passe dans « En attente de signature ») ; Reda y figurait parce que l'envoi n'avait pas reconnu son entreprise existante « DIGISELL TECHNOLOGIES » (nom saisi : « DIGISELL ») et en avait créé une seconde (n° 635). L'envoi réutilise désormais l'entreprise du prospect : même nom, nom légal, nom qui contient l'autre, ou la seule rattachée. Le doublon de Reda est à supprimer au national par JB.

**🔎 Recherche prédictive, vues des membres, région = national, formulaire dans Demandes (v0.42.0, 12/11/2026)** — JB : « plusieurs modes d'affichage et une recherche prédictive sur les premières lettres partout », « le panneau régional trop pauvre », « le formulaire dans Demandes ».
- Recherche prédictive : tout champ `data-pred="<source>"` (`PRED_SRC` : membres, clubs, lieux, equipe, demandes, tout) ouvre `#pred` dès la première lettre ; un résultat sort si chaque mot tapé est le DÉBUT d'un mot de la fiche (`predMots`, `predCalc`), lettres surlignées, ↑ ↓ Entrée Échap. Recherche globale (`#ds-q`, source `tout`) en tête de la Synthèse et de Ma région. `render()` garde le focus du champ actif (avant : la recherche Clubs / Lieux perdait le focus à chaque lettre).
- Membres : 4 vues (`MB_MODES` cartes, liste, par groupe, par métier ; localStorage `cap-mbvue`) ; la liste filtre aussi par début de mot.
- Ma région = `viewDashboard({band,lieu,apres})` (mêmes chapitres que le national, filtrés par `avecVue`) + chapitres « Les groupes de la région » et « Planning de la région ».
- Demandes → onglet 📝 Formulaire (`dmFormHTML`, `window._dmVue='form'`) : `adhesion.html` intégré, « Remplir » (vraie demande, `?ref=` du groupe choisi) ou « Consulter » (`#demo`), PDF vierge, plein écran.
- Banc `scratchpad/tools/v042.mjs` 56/56.

**📆 Quinzaine, glisser-déposer, heure du matin (v0.43.0, 12/11/2026)** — JB : « une réunion tous les 15 jours », « drag and drop des réunions », « les réunions sont le matin, 11 h par défaut, plus de molettes ».
- Migration `20261112180000_clubs_rythme_quinzaine.sql` (appliquée) : `clubs.rythme_pas` (1|2) + `rythme_depart` (date). Quinzaine = `rythme_rang 0` + `rythme_pas 2`, ancrée sur `rythme_depart` (sinon la dernière réunion). `rythmeQuinz`, `quinzDates` (pas de 14 jours), `prochaineDate`, `psDates` (`rang "q"`, champ « 1re réunion » dans Planifier en série), `openRythme` (« Tous les 15 jours » par défaut + date d'une réunion de la série). `psDeviner` reconnaît un écart de 11 à 20 jours.
- Calendrier (Agenda et Groupe, mois et semaine) : une réunion à venir, modifiable, non réalisée ni annulée se glisse sur un autre jour (`calBougeable`, `reuDeplacer`, cases `data-cal-iso`) ; toast cliquable pour annuler. Glisser HTML5 : ordinateur ; au téléphone « Changer le jour » reste.
- Heure : `heureChamp(id,val,onch,compact)` remplace tous les `input type=time` (créneaux 8h–13h + listes heure/minutes, champ caché au même id) ; défaut `HEURE_DEF` = 11:00 (ou l'heure habituelle du club).
- Banc `scratchpad/tools/v043.mjs` 29/29.

**🌐 Invitation du CRM national sur chaque réunion (v0.44.0, 16/11/2026)** — JB : « générer le lien de mon CRM à travers le CRM national, que ça enrichisse le national comme si on l'avait fait là-bas, en restant chez nous ».
- Au national, une réunion = une **invitation** (Communication → Invitations, `/invitation`). Lien public d'inscription : `https://animateur.ma.caproteine.com/invitation/inscription?ref=<n°>` (s'ouvre sans connexion). Le QR du national (`/invitation/qrCode?id=`) exige une session chez eux : on dessine le nôtre à partir du lien (`natInvQr`, `qrLib`).
- Écriture = rejouer « Rédiger une nouvelle invitation à partir de celle-ci » : GET `/invitation/formulaireNew?id=<modèle>&forcerCreation=true` puis POST `/invitation/enregistrer` (champs du `#formApercu` : programme, template, metadata, refTemplate recopiés). ⚠ Sans `forcerCreation=true`, le national répond 500 et envoie un e-mail à son support. Mise à jour = même chose sans `forcerCreation`, avec `id`. Types : 7 Réunion d'information (SI), 16 Réunion de lancement (RL), 3 Réunion des membres. Lieux du national (« hôtes ») : seulement « Le limonadier » (40) au 16/11 ; un lieu absent du national est refusé avec la liste des lieux connus.
- `national-suivi` v15 : actions `invitation_reunion` (reunion_id, essai) → `reunions.national` = { invitation_id, lien, qr, date, heure, lieu, modele, cree_le, maj_le } ; `invitation_copier` ; lectures `lister`, `champs`, `regarder`. Migration `20261116140355_reunions_invitation_nationale.sql` (appliquée).
- Fiche réunion : `natInvBloc(m)` (création réservée au superadmin, réunion à venir non annulée ; lien visible pour tous) ; `natInvPerime(m)` signale date / heure / lieu changés depuis l'envoi → « Mettre à jour au national ». WhatsApp (`natInvWa`), Copier (`natInvCopier`). Banc `natinv.mjs` 33/33.
- Cartes des Demandes (`.dm-card`) : l'inclinaison du survol se joue à l'arrivée (classes `survol` + `incline` 450 ms) puis la carte se redresse pour la lecture ; `_horsCarte` garde la carte soulevée au ras de son bord (elle tremblait : soulevée de 3 px, elle sortait de sous la souris). Banc `survol.mjs` 5/5.
- 16/11 : invitation **n° 108** créée au national pour jeudi 19/11 11h au Limonadier (copie de la n° 97), rattachée à la SI du 19/11 de CAP Rabat Prévilège. Chrystel marquée « membre, acté au national » (pas une demande en cours).

**🎨 Thèmes revus (v0.44.1, 16/11/2026)** — JB : « le clair trop blanc, on voit mal les menus ; le sombre trop rosé, plutôt gris anthracite ». Bloc CSS `/*v045 thèmes*/` en fin de styles (il l'emporte sur les définitions d'avant) : clair = fond `#ECEAE9`, cartes blanches, filets et texte secondaire plus marqués, menu latéral sur `--side` `#E1DEDD`, onglet actif en carte blanche ; sombre = anthracite neutre (`#17181A` fond, `#222326` cartes, `#36383C` filets, plus aucune teinte rose sauf les accents crimson). Banc `theme.mjs` (captures clair / sombre / sombre téléphone).
- **v0.44.2 : le jaune doré remplacé par le bleu ardoise** (clic JB sur la maquette https://claude.ai/artifact/KqbEcFyKWXNcepS9k7eaRo, piste A) : alertes, bandeau « Vue nationale », pastilles « En création » / RL, compteur « À faire », carte paiement de la Synthèse vivante, constellation, toasts d'avertissement. Clair : accent `#5B7FA3`, foncé `#3B5B7A`/`#36556F`, fond `#E3EAF2`/`#E8EEF4` ; sombre : `#8FB0D1`/`#9DB7D1` sur `#1C2530`/`#223042`. `--gold` vaut désormais ce bleu (le nom du jeton reste). Restent volontairement dorées : les couleurs de ville (Salé), des groupes, des rôles et des confettis.

**🔑 Accès par rôle depuis Équipe (v0.45.0, 16/11/2026)** — JB : « donner ses identifiants à Chrystel », « gérable d'ici, que je puisse donner les accès directement ».
- Migration `20261116150117_acces_par_role.sql` (appliquée) : `profiles.tel`, RPC `cap_acces_equipe()` (superadmin : compte, rôle, e-mail, animateur, mobile, dernière connexion, `cap2026` encore actif, provisoire, invité le) et `cap_profil_tel`.
- Équipe (superadmin) : colonne « Accès CRM » (`accCellule` : état + bouton « 🔑 Donner l'accès » / « Renvoyer »), même bouton dans la ligne mobile. `accDonner(animId)` : rôle, ce que le rôle permet (`ROLE_DROITS`), mobile (`accTel`), `accCreer` = mot de passe provisoire (`mdpProvisoire`) par `admin-users set_password` (ou `create` si l'animateur n'a pas de compte, identifiant = prénom sans accents), `cap_marquer_invite`, puis WhatsApp vers son mobile (`accMessage`, avec ses droits) et Copier. Confirmation avant de remplacer le mot de passe d'un compte déjà utilisé. Le mot de passe n'est affiché qu'une fois.
- Au 16/11 : les 8 animateurs ont un compte, seule Chrystel a un mobile en base. Banc `acces.mjs` 21/21.

**👥 Accès espace membre + animateurs membres (v0.45.1 / v0.46.0, 16/11/2026)** — JB : « les accès pour les membres de la région aussi », les animateurs « sont des vrais membres, mais tu les étiquettes comme animateurs, que je puisse les voir à part ».
- v0.45.1 : anneaux de santé plus grands, pastilles « À faire » lisibles en sombre.
- Migration `20261116152703_membres_animateur.sql` (appliquée) : `membres.animateur_id` (unique : la fiche qui porte l'espace membre de l'animateur). `mbAnim(m)` = ce lien, ou une fiche au même nom que l'animateur du groupe (JB a 3 fiches, une par groupe). Étiquette `.mb-anim`, filtre « Animateurs » dans Membres, mention dans la fiche.
- Membres (vue liste) : colonne « Espace membre » (`mbEspCell`) → `mbAccesFiche(id)` (mobile modifiable `mbAccTel`, puis le code par `mbCodeAcces` et WhatsApp).
- Équipe → fiche d'accès : bloc « Espace membre » (`accMembreBloc`) : fiche trouvée → `accMembreOuvrir` (lie `animateur_id`, reprend le mobile) ; sinon `accMembreCreer` l'ajoute comme vrai membre de son groupe (compte dans les stats). Banc `mbacc.mjs` 36/36.

**✉ Message d'invitation par type de réunion (v0.46.1 / v0.47.0, 16/11/2026)** — JB : « c'est pas Protéine Maroc, c'est Protéine Rabat et Région » et, sur le message d'invitation WhatsApp, « le message d'accueil s'il te plaît, ça c'est nul ».
- v0.46.1 : messages d'accès (`accMessage`, `embMessage`) = « Club d'Affaires Protéine Rabat et Région », sans émoji (👋 sortait en « � » dans WhatsApp). Ailleurs (connexion, espace membre, formulaire d'adhésion et son pied légal) « Protéine Maroc » reste.
- v0.47.0 : `INV_MODELES` (SI, RL, autre) avec repères {jour} {heure} {lieu} {adresse} {groupe} {lien} {prenom}, remplis par `invRemplir`. « Envoyer par WhatsApp » de la fiche réunion ouvre `natInvWa(id)` : texte modifiable, WhatsApp / Copier, « Garder comme modèle » (`invGarder` remet les repères, localStorage `cap-invtpl-<type>`), « Revenir au texte d'origine ». Sans émoji. ⏳ JB veut plus tard préciser le type (information, lancement, traditionnelle, thématique…) : `TYPES` n'a que SI et RL. Banc `natinv.mjs` 39/39.

**🗓 Inscrits du lien national dans les invités (v0.48.0, 16/11/2026)** — JB : « qu'on puisse traquer les gens qui sont inscrits », « la liste des présents », « un bouton d'actualisation ».
- Au national, les inscrits d'une invitation = « Afficher les statistiques de l'invitation » : GET `/invitation/statistique?id=N` puis POST DataTables `/destinataireInvitation/lister?id=N` (JSON : id, prenom, nom, email, tel1, nomEntreprise, activite, dateReponse, etatInvitation 1 = accepté, etatPresence). Totaux : `/destinataireInvitation/listerStatistiquesGlobale?id=N`.
- Migration `invites_inscrits_national` (appliquée, version prod à relever) : `invites.email`, `invites.national_id` (unique par réunion). `national-suivi` v17 : `inscritsLire` / `inscritsSync` (insère les nouveaux en « Intéressé », invite_par « Lien du national », note avec la date d'inscription ; rapproche par id national, e-mail ou nom), `reunions.national.inscrits/inscrits_le`, push aux superadmins à chaque nouvel inscrit (`pousser`). Action `inscrits` (reunion_id facultatif) + étape 2 bis du passage horaire (cron 8h-21h).
- v0.48.1 : invités en « Détaillé » ou « Liste » (`guestVue`, localStorage `cap-gvue`, `.gl-r` : nom, téléphone cliquable + entreprise, statut).
- Fiche réunion : ligne « N inscrits par le lien · vérifié … » et bouton « 🔄 Récupérer les inscrits » (`natInscrits`, superadmin). 16/11 : 4 inscrits rapatriés pour le 19/11 (Benyahya, El Meliani, Chrystel, Koita). Banc `natinv.mjs` 43/43.

**✍️ Signature Yousign automatique (v0.49.0, 16/11/2026)** — JB : « que ça déclenche la procédure pour la signature numérique, sinon ça n'a aucun intérêt » (Hassan, au national : le lien bascule normalement sur Yousign).
- Au national, le bouton « Lancer la procédure de signature » appelle `POST /signatureNumerique/creerProcedure {idContrat}`. La réponse porte `referenceProcedure`, `referenceSignataire`, `referenceSignatairePrincipal`, `logYousign`, `type` et `messageLog`. Le national crée lui-même la procédure Yousign et envoie les e-mails (membre, Faïçal, animateur, délégué). Aucun autre appel n'est nécessaire.
- `national-adhesion` v6 : `signature: 'electronique'` par défaut dans `envoyer`. Nouvelle action `yousign`, ouverte aussi avec le jeton `x-suivi-jeton` : elle lance Yousign sur un contrat déjà créé, sans le réécrire. Garde-fous : `reference_procedure` déjà posé → refus (pas de 2e e-mail) ; contrat déjà signé → refus. Statut `yousign_envoye`.
- 16/11 : Yousign lancé sur les contrats 121 (Dinia), 122 (Reda), 123 (Ibtissam El Hammoumi) et 124 (Nawar), qui étaient en papier. Le national a accepté les 4. Le contrat d'essai 119 et Chrystel n'ont pas été touchés.

**🌗 Thème sombre et constellation (v0.49.1 → v0.51.0, 16/11/2026)** :
- Sombre = une seule palette, bloc CSS `/*v050*/` en fin de styles (anthracite `#26282C` / cartes `#303237`, rouge du logo `#A81E3C`, `--crimson-txt` `#EE5A64` pour les textes rouges ; `color:var(--crimson)` est devenu `color:var(--crimson-txt,var(--crimson))` partout). Sombre = thème par défaut (`cap-theme` absent). Maquette « design clean » écartée par JB (https://claude.ai/artifact/A8LuRTqo51ZMqs87kYHBFw), à reprendre plus tard.
- Constellation (`cstRender`) : cadre (viewBox) ajusté au contenu ; région à plusieurs villes = sous-régions (`.cst-sub`) ; groupes sur orbites inclinées animées par `requestAnimationFrame` (`_cst.raf`, `_cst.pause` au survol / volet ouvert) ; clic = volet `#cst-fiche` (`cstFiche`, `cstFicheFermer`, Échap ferme d'abord le volet). Banc `cst.mjs` 18/18.
- Fiches Équipe créées pour Hassan Bahjoub (directeur national, compte `hassan`) et Ghita (bureau national), liées à leurs comptes, sans ville ni mobile.

**🎉 v1.0.0 (16/11/2026)** : JB déclare le CRM opérationnel (connecté au CRM national). Constellation : survol = l'orbite amène le groupe devant puis il grandit (`ob.off`/`ob.offT`, relâche 650 ms après la sortie) ; volet `#cst-fiche` en bas d'écran sous 900 px. Banc `cst.mjs` 20/20.
- **Cloisonnement de la vue régionale** (JB : « des barrières étanches entre le régional et le national ») : en fin de script, une liste de fonctions (`reunionsSansBilan`, `predCalc`, `openRenouvellements`, `openCarte`, `openZones`, `openLancements`, `openRapport`, `cstDonnees`, `showRender`, `openPlanSerie`, `psRendu`, `psDates`, `openRecos`, `openRendement`, `openArchivesAdh`, `exportCSV`, `exportMembres`, `dmCols`, `natCols`, `adhASaisir`, `adhAIntegrer`) est enveloppée par `avecVue`. ⚠ Une nouvelle fonction qui ouvre une liste depuis un bouton doit y être ajoutée, et ne doit rien écrire dans DB avant son premier `await`. `vuePortee` filtre aussi `acces` et `aEmbarquer` ; `embRendu` ne liste que l'équipe de la région. C'est un filtre d'affichage pour le superadmin : les directeurs et animateurs sont déjà cloisonnés par la RLS. Banc `cloison.mjs` 5/5.

**🪪 Module membres : fiche, invités du groupe, fil du groupe (v1.1.0, 16/11/2026)** — JB : fiche signalétique avec photo et logo, remplie par le membre lui-même et pré-remplie avec la postulation ; invités du groupe « tout, coordonnées comprises », jamais visibles d'un autre groupe ; « un fil par groupe, avec l'animateur ».
- Migration `20261116210000_espace_membre_fiche_groupe.sql` (appliquée) : `membres.photo_url/logo_url/presentation/site/linkedin/reseaux` ; bucket **public** `profils` (5 Mo, images ; écriture : l'équipe du club ou le membre lui-même, chemin `<membre_id>/…`) ; RPC `cap_annuaire_fiche()` (présentation repliée sur `infos.ent_activite`, site sur `infos.ent_web`), `cap_membre_fiche_maj(...)`, `cap_membre_invites_groupe()` (club du membre seulement) ; table `messages_groupe` (lecture : `cap_groupe_acces(club)` = équipe qui peut modifier le club ou membre du club ; écriture par RPC `cap_groupe_ecrire`), dans la publication realtime.
- `membre.html` : annuaire et fiche avec photo, logo, présentation et liens (`liensHTML`) ; Mon profil → « Ma fiche » (`ficheForm`, images réduites à 640/500 px dans le navigateur) ; Messages → fil du groupe épinglé (`vueGroupe`, non-lus dans `localStorage cap-grp-vu`) ; Inviter → invités du groupe (`invGroupeHTML`) ; Recos → CA apporté / reçu.
- CRM : section « Fiche signalétique » dans la fiche membre (`mbFicheHTML`, `mbFicheForm`, `mbFicheSauver`) ; onglet « 💬 Discussion » de l'espace Groupe (`grpFil`, realtime).
- Bancs `v110.mjs` 26/26 (espace membre, démo), `v110crm.mjs` 20/20, `membre.mjs` 63/63.
- ⏳ Notifications push pour les messages du groupe : pas encore. Calquer l'app membre du national : JB doit dire comment y accéder.

**📊 Tableau de bord chiffré + constellation (v1.2.0, 16/11/2026)** — JB : chiffres de la région et de son propre groupe pour les membres, jamais ceux des autres groupes ; mise à jour à chaque saisie ; « un tableau de bord propre pour les données chiffrées du groupe, CA reçu, transmis ».
- Migration `20261117090000_tableau_membre_groupe_region.sql` (appliquée) : `unaccent_simple(t)` ; RPC `cap_membre_tableau()` (membre connecté) → `moi` (recos données/reçues, CA transmis = signées grâce à ses recos, CA reçu = affaires qu'il a signées, mois), `groupe` et `region` (nom, membres, groupes, recos mois/année, affaires, CA mois/année, en cours, série 12 mois). Région = zone dont `villes` contient la ville du club (sans accents), sinon la ville. Calcul à la volée sur `recommandations` : jamais de table de cumul à tenir.
- `membre.html` : onglet Recos devient « Recos et chiffres » ; `tableauHTML()` (segment `S.tbVue` moi|groupe|region, barres 12 mois `barres`), recalcul quand une reco change (realtime) et toutes les 60 s sur l'onglet (les saisies des autres groupes de la région ne sont pas diffusées).
- CRM `grpAffaires` : CA du mois, barres 12 mois (`.ga-bars`), tableau par membre (`.ga-tab` : recos données/reçues, CA transmis, CA reçu).
- Constellation : la cible du survol est verrouillée (`pos[i].oi` = orbite) ; un voisin qui passe sous la souris immobile pendant la rotation ne vole plus la cible (avant : la cible changeait ~10 fois en 2 s) ; on change de cible sur un vrai mouvement de souris, on lâche quand la souris sort de la zone de l'orbite (ellipse élargie, 350 ms) ou du ciel. Rotation animée même en mouvement réduit.
- Bancs `v110.mjs` 32/32, `grp.mjs` 40/40, `cst.mjs` 20/20, `v110crm.mjs` 20/20, `cloison.mjs` 5/5 ; sonde `cstprobe.mjs` (position d'un nœud du fond pendant le survol).
- ⏳ Visite guidée à refaire avec la fiche membre, les invités du groupe, le fil et le tableau de bord, une fois validés par JB.

**🏠 Accueil « Groupe » de l'espace membre + vue membre pour la direction (v1.3.0, 17/11/2026)** — JB : « un tableau de bord intermédiaire pour les membres quand ils accèdent à leur groupe » (constat : tout était éparpillé sur 4 onglets) ; clics : onglet « Mon groupe » + « Voir comme un membre » ET écrire dans le fil.
- Migrations `20261117110000_vue_groupe_membre_direction.sql` + `groupe_vue_metier_specialite` (appliquées). `cap_peut_voir_groupe(club)` = membre du club OU équipe avec `cap_can_edit_club` (animateur, directeur de zone, direction nationale, superadmin). `cap_tableau_club(club, mb)` = calcul des chiffres groupe/région (+ moi), vérifie l'accès lui-même ; `cap_membre_tableau()` passe par lui. `cap_groupe_vue(p_club)` (vide = groupe du membre) : club (animateur, rythme, lieu, métiers recherchés), prochaine réunion, réunions, membres, invités de la prochaine réunion avec coordonnées, 8 dernières recos, 4 derniers messages, chiffres, `vue_equipe`. `cap_metier_membre(infos, specialite)` : spécialité, puis métier sauf « - Autre - » (aussi dans `cap_annuaire_fiche`).
- `membre.html` : onglet `accueil` (« Groupe », premier, onglet par défaut ; `vueAccueil`, `chargerGv`, `rythmeTxt`, `demoGv`) ; barre à 6 onglets (« Profil »). `#equipe=<club>` = vue membre pour l'équipe : client Supabase à la clé de stockage par défaut (la session du CRM, même site), `demarrerEquipe`, bandeau `.eq-band`, pas de barre du bas, fiches et fil (écriture permise par `cap_groupe_acces`). `clubId()` = club de la vue.
- CRM : bouton « 👁 Vue membre » dans l'en-tête de l'espace Groupe (`membre.html#equipe=<id>`, nouvel onglet).
- Bancs `v110.mjs` 36/36, `v130eq.mjs` 14/14, `membre.mjs` 65/65 (recalé : l'accueil est le groupe), `grp.mjs` 40/40, `v110crm.mjs` 20/20, `cst.mjs` 20/20, `cloison.mjs` 5/5.

**🔔 Notifications du fil de groupe (v1.4.0, 17/11/2026)** — JB : « fais les notifications du fil de groupe ».
- Migration `20261117140000_notif_fil_groupe.sql` (appliquée) : `messages_groupe.notifie_le` + déclencheur `messages_groupe_notifier` → `membres_notifier('groupe')`.
- Edge `notif-membre` **v4** (verify_jwt:false, source dans `supabase/functions/notif-membre/index.ts` = déployée) : type `groupe`, réservation atomique de `notifie_le` (< 15 min) ; destinataires = membres du club avec `user_id` + profils dont `animateur_id` = animateur du club, sauf l'auteur ; étiquette `grp-<club>` (la dernière remplace la précédente) ; lien `/membre.html#g` (membres) ou `/?groupe=<club>` (équipe). Essai à blanc : 200 `deja_notifie_ou_ancien`.
- `membre.html` : `#g` ouvre le fil (`lienHash`, message du service worker) ; texte de la carte Notifications. CRM : `ouvrirLienGroupe()` (`?groupe=` → `grpAller(id,'fil')`), sous-titre de la fenêtre Notifications.
- Banc `v140.mjs` 6/6 (⚠ ne pas rappeler `bootIntoApp()` après `goto` : l'appli démarre déjà seule quand une session existe, le second démarrage remet la Synthèse) ; `membre` 65/65, `v110` 36/36, `v130eq` 14/14, `grp` 40/40, `v110crm` 20/20.

**⚠️ À traiter** :
1. **Tester le front câblé dans un navigateur** (login réel + CRUD) — non testable depuis les sessions Claude Code : l'hôte `*.supabase.co` est bloqué par l'egress policy.
2. **Purger le mot de passe `cap2026`** : outil prêt en v0.33.0 (« Embarquer l'équipe »), reste à l'utiliser pour les 7 animateurs concernés.
3. Confirmer données réelles vs. seed (`invites` encore vide → aucune saisie terrain à ce jour).
4. Redéployer sur Vercel depuis le repo (après GO explicite de JB). **Photos lieux** : stockées en base64 dans `lieux.photo_url` pour l'instant — migrer vers le bucket Storage `lieux` si le poids des lignes gêne.
