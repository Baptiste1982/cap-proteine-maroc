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

**Ce que le robot fait (relevé le 29/10/2026 sur l'Espace Animateur, sans rien y écrire)**
- Il retrouve le prospect par son e-mail (onglet « Sans contrat ») ou le crée, et s'arrête si le dossier est déjà
  « En attente de signature ».
- Étape 1 : il choisit l'entreprise déjà rattachée si son nom correspond, sinon « Créer une nouvelle entreprise ».
- Étape 2 : il lance la recherche par ICE, puis remplit les cases restées vides. Ce que le national connaît déjà est
  gardé, et les différences sont signalées. La catégorie juridique et le métier sont choisis dans les listes du
  national : le formulaire d'adhésion propose exactement les mêmes listes (13 catégories, 402 métiers).
- Étape 3 : civilité, dirigeant, nom, prénom, fonction, e-mail, mobile, date de naissance, adresse recopiée de
  l'entreprise. Il répond « non » à « ajouter d'autres personnes ? ».
- Étape 4 : signataire (le membre, ou un avertissement s'il s'agit d'une autre personne), offre « Aucune », mode de
  règlement, facturation. **Il s'arrête là** : il n'enregistre pas le contrat et ne lance jamais la signature.

**Correspondances à connaître**
- Le champ affiché « Num. RC » au national est la **patente** : son libellé devient « Patente » dès qu'on choisit la
  catégorie, et le contrat l'imprime sous ce nom. Il n'y a pas de numéro de RC à saisir.
- Pour « Entrepreneur individuel » et « Profession libérale », patente, ville RC et capital sont facultatifs,
  au national comme dans notre formulaire.
- Mode de règlement : virement 1 fois → « Virement bancaire en 1 fois » ; virement 2 fois → « … en 2 fois
  consécutives » ; chèque 1 ou 2 fois → idem. Le prélèvement n'est pas proposé dans notre formulaire.
- Doublons : l'annuaire contient déjà deux « PURPLE BIRDGE » (552 et 608). Quand le national propose plusieurs
  entreprises, c'est vous qui choisissez.

## Lancer le robot (sur votre PC)

```
cd outils/saisie-proteine
npm i playwright && npx playwright install chromium
node saisir.mjs adhesions-a-saisir-AAAA-MM-JJ.json --essai   # répétition à blanc : rien n'est écrit
node saisir.mjs adhesions-a-saisir-AAAA-MM-JJ.json           # pour de vrai, pause à chaque étape
```

- Le fichier vient du CRM CAP : Synthèse → 📝 Adhésions → « Exporter pour saisie » (JSON).
- **`--essai`** : seules les lectures partent au national. Les enregistrements reçoivent une fausse réponse et
  rien n'est créé. À faire avant le premier vrai lot.
- **Mode normal** : le robot remplit une étape, vous relisez, Entrée enregistre et passe à l'étape suivante.
  Si le national refuse, il affiche les champs en erreur et vous laisse corriger.
- **`--auto`** : enchaîne les étapes 1 à 3 sans pause. Il s'arrête toujours à l'étape Contrat.
- **Connexion** : vous vous connectez dans la fenêtre, ou vous posez `CAP_NATIONAL_IDENTIFIANT` et
  `CAP_NATIONAL_MOT_DE_PASSE` dans les variables d'environnement de votre PC (jamais dans un fichier du dépôt).
- **Correspondance des champs** : `outils/saisie-proteine/correspondance.json`. Si le national renomme un champ,
  c'est là qu'on corrige.
- Un journal CSV est écrit à côté du fichier d'export. Ensuite : « Marquer saisie » dans le CRM CAP.

## Règles de sécurité (non négociables)

- Aucun identifiant ni mot de passe dans le dépôt, dans le CRM CAP, ni dans un message.
- La session du navigateur reste sur votre PC (`outils/saisie-proteine/.session/`, ignoré par git).
- Le robot n'enregistre jamais le contrat et ne lance jamais la signature : ces deux gestes restent les vôtres.
- Chaque fiche saisie est marquée dans le CRM CAP (« Marquer saisie ») : rien n'est saisi deux fois.
