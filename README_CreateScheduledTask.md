# CreateScheduledTask.ps1

## Description
Ce script PowerShell permet de créer ou de mettre à jour des tâches planifiées sur un serveur Windows pour exécuter des scripts liés à la gestion des comptes Active Directory. Il prend en charge les comptes gMSA (Group Managed Service Accounts) ou les comptes classiques avec mot de passe.

---

## Fonctionnalités
- **Choix des scripts** : Permet de planifier l'exécution des scripts suivants :
  - `DisabledAccountsSummary.ps1`
  - `InactiveAccountsManager.ps1`
  - `PasswordExpirationNotifier.ps1`
- **Support des comptes gMSA** : Configure les tâches avec des comptes gMSA ou des comptes utilisateur classiques.
- **Arguments dynamiques** : Configure les paramètres pour chaque script, comme les e-mails d'administration, le serveur SMTP et l'adresse e-mail de l'expéditeur.
- **Mise à jour ou création** : Identifie si une tâche existe déjà et décide de la mettre à jour ou de la créer.
- **Journalisation** : Fournit des messages explicatifs et des logs pendant l'exécution.

---

## Prérequis
- **Système d'exploitation** : Windows Server ou équivalent avec PowerShell 5.1 ou supérieur.
- **Modules requis** : Aucun module externe n'est nécessaire.

---

## Paramètres principaux

### Saisie utilisateur lors de l'exécution
- **Script à planifier** : L'utilisateur sélectionne parmi une liste de scripts prédéfinis.
- **Informations SMTP** :
  - Adresses e-mail des administrateurs (`AdminEmails`).
  - Adresse du serveur SMTP (`SmtpServer`).
  - Adresse e-mail de l'expéditeur (`EmailFrom`).
- **Type de compte** :
  - gMSA ou compte utilisateur classique.
  - Si un compte gMSA est choisi, le script demande uniquement le nom de compte.
  - Pour un compte classique, le script demande le mot de passe.
- **Nom de domaine** : Utilisé pour définir le compte exécutant la tâche.

### Déclencheur de tâche
- Horaire : Tous les jours à 01h00.

---

## Exemple d'utilisation

### 1. Planification d’un script avec un compte gMSA
- Script choisi : `InactiveAccountsManager.ps1`
- Commandes exécutées dans le script :
  ```powershell
  Le compte est-il un gMSA ? (O/N) : O
  Entrez le nom du compte gMSA : gMSA-SVC-IAM-USERS
  Entrez le nom du domaine : MON_DOMAINE
  ```
  Résultat : Une tâche planifiée est créée pour exécuter `InactiveAccountsManager.ps1` sous le compte gMSA `MON_DOMAINE\gMSA-SVC-IAM-USERS$`.

### 2. Mise à jour d’une tâche avec un compte utilisateur
- Script choisi : `PasswordExpirationNotifier.ps1`
- Commandes exécutées dans le script :
  ```powershell
  Le compte est-il un gMSA ? (O/N) : N
  Entrez le nom d'utilisateur : Administrator
  Entrez le mot de passe pour l'utilisateur 'MON_DOMAINE\Administrator' :
  ```
  Résultat : La tâche planifiée pour `PasswordExpirationNotifier.ps1` est mise à jour avec les nouvelles informations d'identification.

---

## Gestion des erreurs
- **Vérification des scripts** : Le script vérifie que le fichier du script sélectionné existe dans le répertoire courant.
- **Validation des entrées** : Contrôle si les choix et les paramètres utilisateur sont valides.
- **Retour d’erreurs détaillées** : Fournit des messages explicites en cas d’échec (par exemple, si la tâche ne peut pas être créée ou mise à jour).

---

## Journaux
Le script utilise des messages affichés à l'écran pour informer l'utilisateur. Aucun fichier de log spécifique n'est généré par ce script.