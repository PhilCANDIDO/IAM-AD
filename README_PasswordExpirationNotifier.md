# PasswordExpirationNotifier

**PasswordExpirationNotifier** est un script PowerShell conçu pour notifier les utilisateurs et les administrateurs de l'expiration imminente ou passée des mots de passe Active Directory. Ce projet inclut un script et des modèles HTML pour envoyer des e-mails professionnels et dynamiques.

## Fonctionnalités

- **Notifications aux utilisateurs** : Les utilisateurs reçoivent un e-mail personnalisé lorsqu’un mot de passe est sur le point d’expirer ou a expiré.
- **Rapports pour les administrateurs** : Génération et envoi de rapports listant les utilisateurs dont les mots de passe expirent prochainement.
- **Journalisation** : Option pour enregistrer toutes les actions effectuées par le script.
- **Support des modèles HTML** : Emails professionnels avec des informations dynamiques.
- **Options de débogage et de simulation** : Modes pour tester et ajuster le comportement du script sans envoyer d’e-mails.

## Structure du Projet

### Scripts

- **`PasswordExpirationNotifier.ps1`** : Le script principal, permettant la détection des comptes et l’envoi des notifications.

### Modèles HTML

- **`UserPasswordNotification.html`** : Notification aux utilisateurs pour les mots de passe sur le point d'expirer.
- **`UserPasswordExpired.html`** : Notification pour les mots de passe déjà expirés.
- **`AdminPasswordSummary.html`** : Rapport résumé pour les administrateurs.

## Configuration

1. **Paramètres requis**
   - **`$AdminEmails`** : Liste des adresses e-mail des administrateurs.
   - **`$SmtpServer`** : Adresse du serveur SMTP.
   - **`$EmailFrom`** : Adresse de l'expéditeur des notifications.
   - **`$Username`**, **`$Password`** : Identifiants pour le serveur SMTP (si requis).
   - **`$TemplatesPath`** : Chemin des modèles HTML (optionnel, sinon, utilise les modèles par défaut).

2. **Personnalisation des modèles HTML**
   Les modèles utilisent des variables dynamiques, telles que :
   - `{{UserPrincipalName}}` : Adresse e-mail de l'utilisateur.
   - `{{ExpirationDate}}` : Date d’expiration.
   - `{{DaysLeftText}}` : Délai avant expiration.
   - `{{emailSupport}}`, `{{phoneSupport}}`, `{{urlSupport}}` : Coordonnées du support.

3. **Paramètres optionnels**
   - **`-EnableLog`** : Active la journalisation dans un fichier `.log`.
   - **`-DebugMode`** : Affiche des informations supplémentaires pour le débogage.
   - **`-dryrun`** : Mode simulation sans envoi réel d'e-mails.

## Personnalisation du script

1. **Changer le logo dans les e-mails**
   - Placez un fichier nommé `logo.png` (au format PNG) dans le dossier contenant les modèles HTML. Ce fichier sera utilisé comme logo dans les e-mails.

2. **Configurer les informations de contact et les liens**
   - Le fichier `config.ps1` doit se trouver dans le même dossier que le script `PasswordExpirationNotifier.ps1`.
   - Modifiez les variables dans `config.ps1` selon vos besoins :
     ```powershell
     $emailSupport = "support@example.com"
     $phoneSupport = "01 23 45 67 89" # Ne pas utiliser les points en séparateur
     $urlSupport = "https://support.example.com"
     $PortalSupport = "https://password-reset.example.com"
     ```
   - Ces variables seront utilisées pour les coordonnées du support technique et le portail de réinitialisation des mots de passe dans les e-mails.

## Exécution

### Pré-requis

- **PowerShell** : Version 5.1 ou supérieure.
- **Module Active Directory** : Nécessaire pour interagir avec les comptes.
- **Accès SMTP** : Configuré pour envoyer des e-mails.

### Commandes principales

#### Notifications aux utilisateurs
Envoyez un e-mail aux utilisateurs dont les mots de passe expirent dans un délai défini.
```powershell
.\PasswordExpirationNotifier.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -ExpirationDate 7
```

#### Rapport pour les administrateurs
Générez un rapport contenant la liste des utilisateurs dont les mots de passe expirent prochainement et envoyez-le aux administrateurs spécifiés.
```powershell
.\PasswordExpirationNotifier.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -ExpirationDate 7
```

#### Notifications avec journalisation activée
Activez la journalisation pour suivre les actions effectuées par le script.
```powershell
.\PasswordExpirationNotifier.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -ExpirationDate 7 -EnableLog
```

#### Notifications pour un environnement de test (mode simulation)
Exécutez le script en mode simulation pour vérifier les actions sans envoyer d’e-mails.
```powershell
.\PasswordExpirationNotifier.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -ExpirationDate 7 -dryrun
```

## Journalisation

Si l'option `-EnableLog` est activée, le script génère un fichier journal nommé `PasswordExpirationNotifier.log` dans le répertoire du script. Chaque entrée inclut un horodatage détaillé.

## Auteur

Ce script a été créé par **Philippe CANDIDO** pour simplifier la gestion des notifications d’expiration de mots de passe dans les environnements Active Directory.  
Pour toute question ou suggestion, contactez-moi à :  
📧 **philippe.candido@cpf-informatique.fr**

## Contribution

Les contributions sont les bienvenues. Merci de créer une *issue* ou de soumettre une *pull request* via GitHub.

## License

Ce projet est sous licence MIT. Consultez le fichier `LICENSE` pour plus de détails.