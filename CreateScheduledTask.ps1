<#
.SYNOPSIS
  Script d'exemple pour créer ou mettre à jour une tâche planifiée.
  - Gère un compte normal (avec mot de passe) ou un gMSA (sans mot de passe).
  - Retire le paramètre -RunAsAdministrator pour éviter l'erreur.
#>

$ErrorActionPreference = "Stop"

# Chemin absolu du répertoire courant
$scriptDirectory = $PSScriptRoot

# Liste des scripts disponibles
$scripts = @(
    @{ Name = "DisabledAccountsSummary.ps1"; TaskName = "DisabledAccountsSummaryTask" },
    @{ Name = "InactiveAccountsManager.ps1"; TaskName = "InactiveAccountsManagerTask" },
    @{ Name = "PasswordExpirationNotifier.ps1"; TaskName = "PasswordExpirationNotifierTask" }
)

Write-Host "Choisissez le script à planifier :"
for ($i = 0; $i -lt $scripts.Count; $i++) {
    Write-Host "$($i + 1). $($scripts[$i].Name)"
}

$choice = Read-Host "Entrez le numéro du script (1 à $($scripts.Count))"
if ($choice -lt 1 -or $choice -gt $scripts.Count) {
    Write-Host "Choix invalide. Veuillez réessayer."
    exit 1
}

# Récupérer le script et le nom de la tâche
$selectedScript = $scripts[$choice - 1]
$scriptPath = Join-Path -Path $scriptDirectory -ChildPath $selectedScript.Name
$taskName = $selectedScript.TaskName

if (-not (Test-Path -Path $scriptPath)) {
    Write-Host "Le script '$($selectedScript.Name)' n'existe pas dans le répertoire courant."
    exit 1
}

# Paramètres du script
$adminEmails = Read-Host "Entrez les adresses e-mail des administrateurs (séparées par des virgules)"
$smtpServer = Read-Host "Entrez l'adresse du serveur SMTP"
$emailFrom = Read-Host "Entrez l'adresse e-mail de l'expéditeur"

# Type de compte (gMSA ou non)
$accountType = Read-Host "Le compte est-il un gMSA ? (O/N)"
$isGMSA = ($accountType -eq "O" -or $accountType -eq "o")

# Domaine
$domainName = Read-Host "Entrez le nom du domaine (ex: MON_DOMAINE)"

if ($isGMSA) {
    $taskUsername = Read-Host "Entrez le nom du compte gMSA (ex: gMSA-SVC-IAM-USERS)"
    $taskUser = "$domainName\$taskUsername`$"
    $securePassword = $null
} else {
    $taskUsername = Read-Host "Entrez le nom d'utilisateur du domaine (ex: Administrator)"
    $taskUser = "$domainName\$taskUsername"

    # Lire le mot de passe en SecureString
    $securePassword = Read-Host "Entrez le mot de passe pour l'utilisateur '$taskUser'" -AsSecureString
    $securePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
}

# Construire les arguments pour le script
$scriptArguments = "-AdminEmails `"$adminEmails`" -SmtpServer `"$smtpServer`" -EmailFrom `"$emailFrom`""

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $scriptArguments" `
    -WorkingDirectory $scriptDirectory

# Déclencheur quotidien à 01h00
$trigger = New-ScheduledTaskTrigger -Daily -At 1:00am

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

# Vérifier si la tâche existe
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "La tâche '$taskName' existe déjà. Elle sera mise à jour."

    try {
        if ($isGMSA) {
            # Mise à jour via Principal gMSA
            $principal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType ServiceAccount -RunLevel Highest

            Set-ScheduledTask -TaskName $taskName `
                -Trigger $trigger `
                -Action $action `
                -Settings $settings `
                -Principal $principal `
                -ErrorAction Stop
        } else {
            # Mise à jour compte normal => -User et -Password
            Set-ScheduledTask -TaskName $taskName `
                -Trigger $trigger `
                -Action $action `
                -Settings $settings `
                -User $taskUser `
                -Password $securePassword `
                -ErrorAction Stop
        }
        Write-Host "`nLa tâche '$taskName' a été mise à jour avec succès."
    }
    catch {
        Write-Host "ERREUR : La mise à jour de la tâche '$taskName' a échoué : $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-Host "Création de la tâche '$taskName'."

    try {
        if ($isGMSA) {
            # Création via Principal gMSA
            Write-Host "Préparation de la tache planifiée avec execution par le compte gMSA $taskUser"
            $principal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $taskName `
                -Description "Exécute le script $($selectedScript.Name) tous les jours à 01h00." `
                -Trigger $trigger `
                -Action $action `
                -Settings $settings `
                -Principal $principal `
                -ErrorAction Stop
        } else {
            # Création compte normal => -User et -Password
            Write-Host "Préparation de la tache planifiée avec execution par le compte de service $taskUser"
            Register-ScheduledTask -TaskName $taskName `
                -Description "Exécute le script $($selectedScript.Name) tous les jours à 01h00." `
                -Trigger $trigger `
                -Action $action `
                -Settings $settings `
                -User $taskUser `
                -Password $securePassword `
                -ErrorAction Stop
        }
        Write-Host "`nLa tâche '$taskName' a été créée avec succès."
    }
    catch {
        Write-Host "ERREUR : La création de la tâche '$taskName' a échoué : $($_.Exception.Message)"
        exit 1
    }
}

# Informations sur la tâche
Write-Host "`nInformations sur la tâche :"
Write-Host "  Nom de la tâche       : $taskName"
Write-Host "  Script               : $scriptPath"
Write-Host "  Répertoire de travail: $scriptDirectory"
Write-Host "  Arguments            : $scriptArguments"
Write-Host "  Utilisateur          : $taskUser"
if ($isGMSA) {
    Write-Host "  Type de compte       : gMSA"
} else {
    Write-Host "  Type de compte       : Compte de service normal"
}
Write-Host "  Planification        : Tous les jours à 01h00"
