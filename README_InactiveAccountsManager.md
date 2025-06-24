# InactiveAccountsManager

**InactiveAccountsManager** est un script PowerShell conçu pour gérer automatiquement les comptes Active Directory inactifs. Il permet d’identifier les utilisateurs inactifs, de leur envoyer des notifications avant désactivation, et de désactiver automatiquement les comptes selon une politique définie.

## Fonctionnalités

- **Identification des comptes inactifs** : Détecte les utilisateurs qui ne se sont pas connectés depuis un certain nombre de jours.
- **Notifications utilisateurs et administrateurs** :
  - Notifications préventives envoyées aux utilisateurs avant désactivation de leur compte.
  - Rapports détaillés envoyés aux administrateurs listant les comptes concernés.
- **Désactivation automatique des comptes inactifs** : 
  - Les comptes inactifs sont désactivés après une période définie.
  - Mise à jour du champ `description` des comptes désactivés avec la date de désactivation.
- **Rapport HTML dynamique** : Rapports clairs et professionnels pour les administrateurs.
- **Journalisation** : Suivi des actions du script pour audit ou dépannage.
- **Exclusion des comptes protégés** : Les comptes contenant la chaîne de caractères `//ACCOUNT_PROTECTED//` dans leur champ `description` sont automatiquement exclus du processus de désactivation.

## Structure du Projet

### Script

- **`InactiveAccountsManager.ps1`** : Script principal pour la gestion des comptes inactifs.

### Modèles HTML

- **`Templates/InactiveAccountsReport.html`** : Rapport des comptes inactifs envoyé aux administrateurs.
- **`Templates/UserDesactivationNotification.html`** : Notification préventive envoyée aux utilisateurs avant désactivation.
- **`Templates/UserDesactivatedNotification.html`** : Notification envoyée après désactivation.

## Configuration

1. **Paramètres requis**
   - **`$AdminEmails`** : Liste des adresses e-mail des administrateurs.
   - **`$SmtpServer`** : Adresse du serveur SMTP.
   - **`$EmailFrom`** : Adresse de l’expéditeur des notifications.
   - **`$Username`**, **`$Password`** : Identifiants SMTP (si requis).
   - **`$InactivityDays`** : Nombre de jours d’inactivité avant désactivation (par défaut : 45).
   - **`$NotificationDays`** : Nombre de jours avant désactivation pour envoyer les notifications préventives (par défaut : 15).

2. **Personnalisation des modèles HTML**
   - Les modèles utilisent des variables dynamiques telles que :
     - `{{DisplayName}}`, `{{LastLogon}}`, `{{DaysInactive}}` : Informations sur l’utilisateur.
     - `{{InactivityDays}}`, `{{DaysRemaining}}` : Paramètres de politique d’inactivité.
     - `{{emailSupport}}`, `{{phoneSupport}}`, `{{urlSupport}}` : Coordonnées du support technique.

3. **Personnalisation via `config.ps1`**
   - Le fichier `config.ps1` doit être situé dans le même répertoire que le script principal.
   - Exemple de configuration :
     ```powershell
     $emailSupport = "support@example.com"
     $phoneSupport = "01 23 45 67 89" # Ne pas utiliser les points comme séparateurs
     $urlSupport = "https://support.example.com"
     ```

4. **Changer le logo dans les e-mails**
   - Placez un fichier nommé `logo.png` (au format PNG) dans le dossier contenant les modèles HTML. Ce fichier sera utilisé comme logo dans les e-mails.

5. **Chemin des modèles HTML**
   - Le dossier `Templates` doit contenir les fichiers HTML nécessaires. Vous pouvez ajuster le chemin via le paramètre `TemplatesPath`.

> [!NOTE]
> IMPORTANT : Les comptes Active Directory dont le champ `description` contient la chaîne de caractères **`//ACCOUNT_PROTECTED//`** sont automatiquement exclus du processus de désactivation, même s'ils répondent aux critères d'inactivité.

## Exécution

### Pré-requis

- **PowerShell** : Version 5.1 ou supérieure.
- **Module Active Directory** : Requis pour interagir avec les comptes.
- **Accès SMTP** : Nécessaire pour l’envoi des notifications par e-mail.

### Commandes principales

#### Détection et rapport des comptes inactifs
Génère un rapport listant les comptes inactifs et envoie-le aux administrateurs.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -InactivityDays 45
```

#### Notifications préventives aux utilisateurs
Envoie des e-mails aux utilisateurs avant la désactivation de leurs comptes.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -InactivityDays 45 -NotificationDays 15
```

#### Désactivation des comptes inactifs
Désactive automatiquement les comptes inactifs et met à jour leur description.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -InactivityDays 45 -enable-log
```

#### Mode simulation
Exécute le script en mode simulation pour valider les actions sans les appliquer.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -InactivityDays 45 -dryrun
```

## Journalisation

Si l'option `-enable-log` est activée, un fichier journal `InactiveAccountsManager.log` est généré. Chaque entrée contient un horodatage et un résumé des actions effectuées.

## Auteur

Ce script a été créé par **Philippe CANDIDO** pour automatiser la gestion des comptes inactifs dans les environnements Active Directory.  
Pour toute question ou suggestion, contactez-moi :  
📧 **philippe.candido@cpf-informatique.fr**

## Contribution

Les contributions sont les bienvenues. Créez une *issue* ou soumettez une *pull request* sur le dépôt GitHub.

## License

Ce projet est sous licence MIT. Consultez le fichier `LICENSE` pour plus de détails.