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
