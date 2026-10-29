# Saisie en série dans le CRM national Protéine

> But : ne plus ressaisir à la main, une par une, les adhésions reçues dans le CRM CAP
> vers le CRM national Protéine, qui n'a pas d'API et ne s'ouvre qu'avec un identifiant
> et un mot de passe.

## Le principe

Un « robot de saisie » remplit les écrans du CRM national **comme le ferait JB**, dans
**son** navigateur, avec **sa** session déjà ouverte. Il ne connaît pas le mot de passe :
JB se connecte lui-même, le robot prend la main ensuite.

```
CRM CAP                          poste de JB                         CRM national
Adhésions → « Exporter pour  →  fichier adhesions-a-saisir.json  →  robot de saisie remplit
saisie » (CSV + JSON)            + correspondance des champs          chaque fiche, JB valide
        ↑                                                                       │
        └──────────── « Marquer saisie » (fiche par fiche, ou tout le lot) ←────┘
```

## Le parcours réel dans le CRM national (guide « Création de contrat Membre », reçu le 29/10/2026)

Adresse : `https://animateur.ma.caproteine.com/connexion/extranet` (espace animateur, une
session par club : « Protéine Rabat Privilège »…). Cinq temps, dans cet ordre :

| # | Écran | Ce qu'on y fait | Qui |
|---|---|---|---|
| 1 | **Annuaire** (« Gestion des contacts ») | Vérifier que le contact existe (il arrive par les liens ou e-mails d'invitation, ou est ajouté à la main par l'animateur). **Sinon, le créer** : c'est obligatoire pour la suite. | robot |
| 2 | **Membres et Prospects → Gestion Prospects**, onglet **« Sans contrat »** → « Ajouter un prospect membre » | Taper le nom de l'entreprise puis **cliquer la proposition** de l'annuaire (« 552 - PURPLE BIRDGE ») : le reste se remplit tout seul. Compléter civilité, nom, prénom, fonction, e-mail, téléphones → « Enregistrer ». | robot |
| 3 | Ligne du prospect → icône clé → **« Envoyer le contrat membre pour signature »** | Assistant en 5 étapes : **1. Préparation** (choisir l'entreprise existante ou en créer une), **2. Entreprise**, **3. Personne membre** — ces trois étapes reprennent le formulaire d'adhésion et **tous les champs y sont obligatoires**. L'étape 3 affiche les **identifiants CRM et application du futur membre** : à relever pour les lui remettre à la fin. | robot (relève les identifiants dans le CRM CAP, fiche de l'adhésion) |
| 4 | **4. Contrat** | L'animateur doit **lire le contrat** avant de pouvoir l'envoyer. | **JB** |
| 5 | **5. Signature** | Envoi pour signature en ligne : le siège, le futur membre, l'animateur en copie. Le dossier passe dans l'onglet **« En attente de signature »**, puis, une fois signé, dans **Gestion Membres**. | **JB** clique |

**Conséquences pour l'automatisation**
- Le robot s'arrête **à l'étape 4** : la lecture du contrat et l'envoi en signature restent un geste de JB.
- Les étapes 1 à 3 sont du remplissage pur : c'est là que le gain est réel (deux formulaires et un assistant, par adhésion).
- **Écart à combler** : le CRM national exige *tous* les champs des étapes 2 et 3, alors que notre formulaire
  d'adhésion n'en rend obligatoires que six (métier, entreprise, prénom, nom, e-mail, téléphone). Pendant la séance,
  relever la liste exacte des champs des étapes 2 et 3, puis rendre les mêmes champs obligatoires dans `adhesion.html`
  — sinon le robot bloquera sur un trou.
- L'annuaire a des boutons Copier / CSV / Excel, et un second bouton à côté de « ajouter un contact » qui ressemble à
  un **import** : à vérifier en séance. Un import en lot dans l'annuaire réglerait l'étape 1 d'un coup.
- Doublons : l'annuaire contient déjà deux « PURPLE BIRDGE » (552 et 608). Le robot doit **choisir par identifiant**
  ou s'arrêter et demander, jamais prendre la première ligne venue.
- Suivi de bout en bout dans le CRM CAP : « saisie faite » quand le contrat part en signature, puis « intégrée »
  quand le membre apparaît dans Gestion Membres.

## Deux façons de faire tourner le robot

| | **A. Claude pilote votre navigateur** | **B. Script sur votre PC** (`outils/saisie-proteine/`) |
|---|---|---|
| Installation | Aucune (Claude dans Chrome, ou le navigateur intégré de l'app Claude) | Node.js + Playwright, une fois |
| Identifiants | Vous vous connectez vous-même, Claude ne voit pas le mot de passe | Vous vous connectez dans la fenêtre ouverte par le script |
| Contrôle | Vous regardez Claude remplir, vous validez chaque fiche | Le script remplit, s'arrête avant « Enregistrer » ; vous validez |
| Volume adapté | Quelques fiches par semaine | Des lots de dizaines de fiches |
| Quand | Tout de suite, dès la séance où vous me montrez les écrans | Une fois la correspondance des champs validée en A |

**Recommandation** : commencer par A pendant la séance où vous me montrez les écrans
(on remplit ensemble les 2-3 premières fiches, ce qui fixe la correspondance), puis
passer à B si le volume le justifie.

## Ce que vous devez me montrer (une séance d'environ 20 minutes)

1. **L'adresse de connexion** du CRM national et le chemin jusqu'au formulaire de
   création d'un membre (menus, onglets, boutons).
2. **Chaque champ du formulaire** : on remplit ensemble le tableau de correspondance
   `outils/saisie-proteine/correspondance.json` (colonne de l'export → champ du CRM national).
3. **Les listes déroulantes** : valeurs exactes acceptées (métier, club, catégorie
   juridique, mode de règlement…). Si le CRM national a sa propre liste de métiers, il faut
   une table de passage.
4. **Les pièces jointes** : faut-il joindre le PDF du formulaire d'adhésion ? (il est
   dans le CRM CAP, fiche par fiche).
5. **Après « Enregistrer »** : le CRM national donne-t-il un numéro de membre à reporter ?
   Comment détecte-t-il un doublon ?
6. **Les obstacles** : double authentification, captcha, déconnexion automatique, limite
   de saisies. Un captcha à chaque fiche rend l'automatisation inutile : à vérifier d'abord.

## Règles de sécurité (non négociables)

- Aucun identifiant ni mot de passe dans le dépôt, dans le CRM CAP, ni dans un message.
- Le script B n'enregistre jamais la session sur disque en dehors de votre PC
  (`outils/saisie-proteine/.session/` est ignoré par git).
- Mode prudent par défaut : le robot **remplit** mais ne **valide pas** ; c'est vous qui
  cliquez « Enregistrer ». Le mode automatique ne s'active qu'après un lot validé sans erreur.
- Chaque fiche saisie est marquée dans le CRM CAP (« Marquer saisie ») : rien n'est saisi
  deux fois.

## Ce qui est déjà prêt

- **Dans le CRM CAP** (Synthèse → 📝 Adhésions) : bouton « Exporter pour saisie », qui
  télécharge les adhésions pas encore saisies (CSV pour lire, JSON pour le robot), colonnes
  dans l'ordre du formulaire officiel ; état « Saisie faite / pas encore » sur chaque fiche.
- **`outils/saisie-proteine/saisir.mjs`** : le robot B, générique. Il ouvre un navigateur,
  attend que vous soyez connecté et sur le formulaire, remplit chaque fiche selon
  `correspondance.json`, puis attend votre validation avant de passer à la suivante.
  Il manque seulement la correspondance réelle, que l'on fixe pendant la séance.
