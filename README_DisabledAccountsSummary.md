# DisabledAccountsSummary.ps1

## Description
Ce script PowerShell génère un résumé des comptes désactivés dans un environnement Microsoft Active Directory. Il compile les données dans un fichier CSV et les envoie par e-mail aux administrateurs spécifiés. Il inclut des options pour la personnalisation des modèles HTML, la configuration SMTP et la journalisation.

---

## Fonctionnalités
- **Récupération des comptes désactivés :** Analyse Active Directory pour identifier les comptes désactivés depuis une période spécifiée.
- **Exportation des résultats :** Génère un rapport au format CSV contenant les détails des comptes désactivés.
- **Envoi d’e-mails sécurisés :** Envoie le rapport par e-mail avec des modèles HTML personnalisables.
- **Journalisation :** Enregistre les actions et les erreurs dans un fichier log pour faciliter le débogage.
- **Support des informations d’identification sécurisées :** Charge les informations SMTP depuis un fichier XML crypté ou utilise les paramètres fournis.

---

## Prérequis
- **Système d'exploitation :** Serveur Windows avec PowerShell 5.1 ou supérieur.
- **Active Directory Module :** Requis pour interagir avec les objets AD.
- **Accès SMTP :** Nécessaire pour envoyer les rapports par e-mail.

---

## Paramètres

| Paramètre              | Description                                                                                         | Valeur par défaut                     |
|------------------------|-----------------------------------------------------------------------------------------------------|---------------------------------------|
| `AdminEmails`          | Liste des adresses e-mail des administrateurs.                                                     | Obligatoire                           |
| `SmtpServer`           | Adresse du serveur SMTP.                                                                           | Obligatoire                           |
| `EmailFrom`            | Adresse e-mail de l'expéditeur.                                                                    | Obligatoire                           |
| `InactiveMonths`       | Période en mois pour inclure les comptes désactivés.                                               | `3`                                   |
| `TemplatesPath`        | Chemin vers les modèles HTML pour les e-mails.                                                     | Vide                                  |
| `ExcelOutputPath`      | Chemin du fichier CSV généré contenant les résultats.                                              | `$PSScriptRoot\DisabledAccountsSummary.csv` |
| `SmtpPort`             | Port SMTP.                                                                                        | `587`                                 |
| `Username`             | Nom d'utilisateur SMTP (si nécessaire).                                                           | Vide                                  |
| `Password`             | Mot de passe SMTP (si nécessaire).                                                                | Vide                                  |
| `SmtpSSL`              | Activer ou désactiver SSL pour SMTP.                                                               | `$true`                               |
| `EnableLog`            | Activer la journalisation.                                                                         | Désactivé                             |
| `DebugMode`            | Activer le mode débogage.                                                                          | Désactivé                             |

---

## Exemple d'utilisation

### Commande de base
```powershell
.\DisabledAccountsSummary.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "noreply@example.com"
```

### Commande avec options avancées
```powershell
.\DisabledAccountsSummary.ps1 -AdminEmails "admin1@example.com","admin2@example.com" `
                              -SmtpServer "smtp.example.com" `
                              -EmailFrom "noreply@example.com" `
                              -InactiveMonths 6 `
                              -TemplatesPath "C:\Templates" `
                              -EnableLog -DebugMode
```

---

## Journalisation
Le script génère un fichier log nommé `DisabledAccountsSummary.log` dans le répertoire du script si l’option `-EnableLog` est activée. Chaque ligne est préfixée d’un horodatage.

---

## Gestion des erreurs
- **Fichier d’identification SMTP :** Vérifie si un fichier `smtp_credential.xml` existe. Si ce n’est pas le cas, utilise les paramètres d’identification fournis.
- **Modèles HTML :** En cas d'absence du fichier modèle, une exception est levée.
- **Problèmes SMTP :** Capture les erreurs liées à la configuration ou à l’envoi des e-mails.