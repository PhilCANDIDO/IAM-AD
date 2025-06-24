# Generate-SmtpCredential.ps1

## Description
Ce script PowerShell permet de générer un fichier contenant des informations d’identification SMTP (nom d’utilisateur et mot de passe) de manière sécurisée. Les informations sont exportées dans un fichier XML crypté qui peut être utilisé par d’autres scripts PowerShell.

---

## Fonctionnalités
- **Saisie sécurisée des informations d’identification SMTP** : Utilise la commande `Get-Credential` pour capturer le nom d’utilisateur et le mot de passe.
- **Export sécurisé** : Enregistre les informations dans un fichier XML crypté en utilisant `Export-Clixml`.
- **Validation de saisie** : Vérifie que des informations ont été saisies avant de procéder à l’enregistrement.
- **Personnalisation du chemin de sortie** : Permet de spécifier l’emplacement du fichier généré.

---

## Prérequis
- **Système d’exploitation** : Windows Server ou équivalent avec PowerShell 5.1 ou supérieur.
- **Permissions** : L’utilisateur doit disposer des droits nécessaires pour écrire dans le répertoire spécifié.

---

## Paramètres interactifs
Le script utilise des invites utilisateur pour recueillir les informations suivantes :
1. **Chemin de sortie** : Chemin complet pour enregistrer le fichier XML. Si aucun chemin n’est fourni, le fichier sera enregistré dans le répertoire courant sous le nom `smtp_credential.xml`.
2. **Nom d’utilisateur et mot de passe SMTP** : Saisie sécurisée via la commande `Get-Credential`.

---

## Exemple d'utilisation
### Commande de base
Exécutez simplement le script pour générer un fichier d’informations d’identification :
```powershell
.\Generate-SmtpCredential.ps1
```
- Entrez le chemin du fichier de sortie ou laissez vide pour utiliser le chemin par défaut.
- Fournissez les informations d’identification SMTP lorsque le système le demande.

### Résultat attendu
- Un fichier `smtp_credential.xml` est créé dans le répertoire spécifié ou par défaut.
- Exemple de message de succès :
  ```
  Les informations d'identification ont été enregistrées avec succès dans le fichier : .\smtp_credential.xml
  ```

---

## Gestion des erreurs
- **Aucune information saisie** : Si l’utilisateur ne fournit pas d’informations d’identification, le script arrête son exécution avec un message explicite.
  ```
  Aucune information d'identification n'a été saisie. Le script s'arrête.
  ```
- **Erreur lors de l’enregistrement** : Si une erreur survient pendant l’écriture du fichier, un message d’erreur est affiché avec les détails de l’exception.

---

## Sécurité
- Le fichier XML généré est crypté et ne peut être utilisé que sur la machine et par l’utilisateur qui l’a créé, garantissant ainsi une sécurité renforcée.