# InactiveAccountsManager

**InactiveAccountsManager** est un script PowerShell conçu pour gérer automatiquement les comptes Active Directory inactifs. Il permet d'identifier les utilisateurs inactifs, de leur envoyer des notifications avant désactivation, et de désactiver automatiquement les comptes selon une politique définie. Le script supporte également la gestion avancée des comptes avec dates d'expiration.

## Fonctionnalités

### 🔧 **Fonctionnalités principales**
- **Identification des comptes inactifs** : Détecte les utilisateurs qui ne se sont pas connectés depuis un certain nombre de jours.
- **Notifications utilisateurs et administrateurs** :
  - Notifications préventives envoyées aux utilisateurs avant désactivation de leur compte.
  - Rapports détaillés envoyés aux administrateurs listant les comptes concernés.
- **Désactivation automatique des comptes inactifs** : 
  - Les comptes inactifs sont désactivés après une période définie.
  - Mise à jour du champ `description` des comptes désactivés avec la date de désactivation.
- **Rapport HTML dynamique** : Rapports clairs et professionnels pour les administrateurs.
- **Journalisation avancée** : Suivi des actions du script avec niveaux de logs (INFO, WARNING, ERROR, DEBUG).
- **Exclusion des comptes protégés** : Les comptes contenant la chaîne de caractères `//ACCOUNT_PROTECTED//` dans leur champ `description` sont automatiquement exclus du processus de désactivation.

### 🆕 **Fonctionnalités avancées (v2.3.0+)**
- **Gestion des comptes avec expiration** : Support optionnel des comptes ayant une date d'expiration définie via le paramètre `-IncludeExpiringAccounts`.
- **Détection d'anomalies** : Identification des comptes expirés mais encore actifs dans Active Directory.
- **Rapports enrichis** : Sections dédiées pour les différents types de comptes avec codes couleur.
- **Monitoring proactif** : Alertes sur les comptes approchant de leur date d'expiration.

## Modes de fonctionnement

### 📋 **Mode Standard (par défaut)**
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com"
```

**Comportement :**
- Traite uniquement les comptes **sans date d'expiration** (`accountExpires = 0` ou valeur maximale)
- Exclut automatiquement les comptes avec une date d'expiration définie
- Processus de désactivation basé sur l'inactivité uniquement
- Compatible avec les versions antérieures du script

**Cas d'usage :** Gestion standard des comptes utilisateurs permanents.

### 🔍 **Mode Étendu** (`-IncludeExpiringAccounts`)
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -IncludeExpiringAccounts
```

**Comportement :**
- Traite **tous les comptes** (avec et sans date d'expiration)
- Catégorise automatiquement les comptes selon leur statut d'expiration
- Génère des rapports enrichis avec sections dédiées
- Détecte les anomalies (comptes expirés encore actifs)

**Cas d'usage :** Audit complet et gestion avancée incluant les comptes temporaires/contractors.

## Catégorisation des comptes (Mode Étendu)

### 1. **Comptes inactifs (traitement standard)**
- Comptes sans date d'expiration
- Soumis au processus normal de notification et désactivation
- **Action** : Notification → Désactivation après délai

### 2. **Comptes avec expiration future**
- Comptes ayant une `accountExpires` dans le futur
- Monitored mais non désactivés pour inactivité
- **Action** : Surveillance jusqu'à expiration naturelle
- **Alertes** : Code couleur selon proximité de l'expiration

### 3. **Comptes expirés encore actifs** ⚠️
- Comptes ayant dépassé leur `accountExpires` mais toujours activés
- **Anomalie détectée** : Nécessite intervention manuelle
- **Action** : Rapport d'alerte pour vérification administrative

## Structure du Projet

### Script

- **`InactiveAccountsManager.ps1`** : Script principal pour la gestion des comptes inactifs.

### Modèles HTML

- **`Templates/InactiveAccountsReport.html`** : Rapport des comptes inactifs envoyé aux administrateurs.
- **`Templates/UserDesactivationNotification.html`** : Notification préventive envoyée aux utilisateurs avant désactivation.
- **`Templates/UserDesactivatedNotification.html`** : Notification envoyée après désactivation.

## Configuration

### 1. **Paramètres requis**
   - **`$AdminEmails`** : Liste des adresses e-mail des administrateurs.
   - **`$SmtpServer`** : Adresse du serveur SMTP.
   - **`$EmailFrom`** : Adresse de l'expéditeur des notifications.
   - **`$Username`**, **`$Password`** : Identifiants SMTP (si requis).

### 2. **Paramètres de gestion de l'inactivité**
   - **`$InactivityDays`** : Nombre de jours d'inactivité avant désactivation (par défaut : 45).
   - **`$NotificationDays`** : Nombre de jours avant désactivation pour envoyer les notifications préventives (par défaut : 15).

### 3. **Nouveaux paramètres (v2.3.0+)**
   - **`$IncludeExpiringAccounts`** : Active le mode étendu incluant les comptes avec expiration.
   - **`$ExpirationWarningDays`** : Nombre de jours avant expiration pour afficher un avertissement (par défaut : 30).

### 4. **Personnalisation des modèles HTML**
   - Les modèles utilisent des variables dynamiques telles que :
     - `{{DisplayName}}`, `{{LastLogon}}`, `{{DaysInactive}}` : Informations sur l'utilisateur.
     - `{{InactivityDays}}`, `{{DaysRemaining}}` : Paramètres de politique d'inactivité.
     - `{{emailSupport}}`, `{{phoneSupport}}`, `{{urlSupport}}` : Coordonnées du support technique.

### 5. **Personnalisation via `config.ps1`**
   - Le fichier `config.ps1` doit être situé dans le même répertoire que le script principal.
   - Exemple de configuration :
     ```powershell
     $emailSupport = "support@example.com"
     $phoneSupport = "01 23 45 67 89" # Ne pas utiliser les points comme séparateurs
     $urlSupport = "https://support.example.com"
     ```

### 6. **Changer le logo dans les e-mails**
   - Placez un fichier nommé `logo.png` (au format PNG) dans le dossier contenant les modèles HTML. Ce fichier sera utilisé comme logo dans les e-mails.

### 7. **Chemin des modèles HTML**
   - Le dossier `Templates` doit contenir les fichiers HTML nécessaires. Vous pouvez ajuster le chemin via le paramètre `TemplatesPath`.

> [!NOTE]
> **IMPORTANT** : Les comptes Active Directory dont le champ `description` contient la chaîne de caractères **`//ACCOUNT_PROTECTED//`** sont automatiquement exclus du processus de désactivation, même s'ils répondent aux critères d'inactivité.

## Exécution

### Pré-requis

- **PowerShell** : Version 5.1 ou supérieure.
- **Module Active Directory** : Requis pour interagir avec les comptes.
- **Accès SMTP** : Nécessaire pour l'envoi des notifications par e-mail.

### Commandes principales

#### Détection et rapport des comptes inactifs (Mode Standard)
Génère un rapport listant les comptes inactifs et envoie-le aux administrateurs.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -InactivityDays 45
```

#### Audit complet avec comptes expirants (Mode Étendu)
Inclut tous les types de comptes dans l'analyse et la génération de rapports.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -IncludeExpiringAccounts -InactivityDays 45
```

#### Notifications préventives aux utilisateurs
Envoie des e-mails aux utilisateurs avant la désactivation de leurs comptes.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -InactivityDays 45 -NotificationDays 15
```

#### Désactivation des comptes inactifs avec journalisation
Désactive automatiquement les comptes inactifs et met à jour leur description.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -InactivityDays 45 -EnableLog
```

#### Mode simulation (DryRun)
Exécute le script en mode simulation pour valider les actions sans les appliquer.
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -InactivityDays 45 -DryRun
```

#### Configuration avancée avec paramètres personnalisés
```powershell
.\InactiveAccountsManager.ps1 -AdminEmails "admin1@example.com","admin2@example.com" `
                              -SmtpServer "smtp.example.com" `
                              -EmailFrom "no-reply@example.com" `
                              -IncludeExpiringAccounts `
                              -InactivityDays 60 `
                              -NotificationDays 21 `
                              -ExpirationWarningDays 15 `
                              -EnableLog `
                              -DebugMode
```

## Rapports générés

### 📊 **Rapport Standard**
- Tableau des comptes inactifs traités
- Actions effectuées (notification, désactivation, protection)
- Statistiques de traitement

### 📈 **Rapport Étendu** (avec `-IncludeExpiringAccounts`)
- **Section 1** : Comptes inactifs (traitement standard)
- **Section 2** : Comptes avec expiration programmée
  - Code couleur : Rouge (≤7 jours), Orange (≤30 jours), Normal (>30 jours)
- **Section 3** : Comptes expirés encore actifs (⚠️ Attention requise)
- Statistiques complètes par catégorie

### 🎨 **Codes couleur du rapport étendu**
- **🔴 Rouge** : Comptes expirés ou actions critiques
- **🟠 Orange** : Comptes expirant bientôt (≤30 jours)
- **🔵 Bleu** : Comptes protégés
- **⚪ Normal** : Comptes en fonctionnement normal

## Journalisation

Si l'option `-EnableLog` est activée, un fichier journal `InactiveAccountsManager.log` est généré. Chaque entrée contient un horodatage et un niveau de log structuré :

- **INFO** : Opérations normales
- **WARNING** : Situations nécessitant attention
- **ERROR** : Erreurs critiques
- **DEBUG** : Informations détaillées (avec `-DebugMode`)

## Gestion des erreurs et sécurité

### 🛡️ **Mécanismes de protection**
- Validation des comptes AD avant modification
- Gestion des exceptions sur toutes les opérations critiques
- Validation des formats d'e-mail
- Nettoyage automatique des ressources

### 🔒 **Comptes protégés**
Les comptes suivants sont automatiquement exclus :
- Comptes avec `//ACCOUNT_PROTECTED//` dans la description
- Comptes système (selon configuration AD)

### ⚙️ **Bonnes pratiques**
1. **Toujours tester en mode `-DryRun`** avant la première exécution
2. **Surveiller les logs** pour détecter les anomalies
3. **Backup Active Directory** avant déploiement en production
4. **Valider les seuils** selon la politique de l'entreprise

## Cas d'usage recommandés

### 🏢 **Environnement d'entreprise standard**
```powershell
# Exécution quotidienne en mode standard
.\InactiveAccountsManager.ps1 -AdminEmails "admin@company.com" -SmtpServer "smtp.company.com" -EmailFrom "noreply@company.com" -EnableLog
```

### 🏗️ **Environnement avec contractors/temporaires**
```powershell
# Exécution hebdomadaire en mode étendu pour audit complet
.\InactiveAccountsManager.ps1 -AdminEmails "admin@company.com" -SmtpServer "smtp.company.com" -EmailFrom "noreply@company.com" -IncludeExpiringAccounts -EnableLog
```

### 🔍 **Audit de conformité**
```powershell
# Rapport détaillé sans modification (audit seul)
.\InactiveAccountsManager.ps1 -AdminEmails "audit@company.com" -SmtpServer "smtp.company.com" -EmailFrom "noreply@company.com" -IncludeExpiringAccounts -DryRun -DebugMode
```

## Auteur

Ce script a été créé par **Philippe CANDIDO** pour automatiser la gestion des comptes inactifs dans les environnements Active Directory.  
Pour toute question ou suggestion, contactez-moi :  
📧 **philippe.candido@cpf-informatique.fr**

## Contribution

Les contributions sont les bienvenues. Créez une *issue* ou soumettez une *pull request* sur le dépôt GitHub.

## License

Ce projet est sous licence MIT. Consultez le fichier `LICENSE` pour plus de détails.

---

## Changelog

### v2.3.0 (Dernière version)
- ✅ Ajout du paramètre `-IncludeExpiringAccounts` pour le mode étendu
- ✅ Gestion des comptes avec dates d'expiration
- ✅ Détection des comptes expirés encore actifs
- ✅ Rapports enrichis avec sections dédiées
- ✅ Codes couleur pour la lisibilité
- ✅ Paramètre `-ExpirationWarningDays` configurable

### v2.2.0
- 🔧 Correction des calculs de dates critiques
- 🔧 Amélioration de la gestion d'erreurs
- 🔧 Optimisation des requêtes Active Directory
- 🔧 Validation des emails avant envoi

### v2.1.1
- 📁 Ajout du chemin par défaut pour les templates
- 📁 Vérification et chargement du fichier de configuration