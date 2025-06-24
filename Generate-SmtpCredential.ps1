# Script pour générer un fichier d'informations d'identification SMTP sécurisé

# Demander le chemin où enregistrer le fichier
$outputPath = Read-Host "Entrez le chemin complet où enregistrer le fichier smtp_credential.xml (par défaut : .\smtp_credential.xml)"
if (-not $outputPath) {
    $outputPath = ".\smtp_credential.xml"
}

# Demander les informations d'identification SMTP
Write-Host "Veuillez entrer les informations d'identification SMTP :"
$credential = Get-Credential -Message "Entrez le nom d'utilisateur et le mot de passe SMTP"

# Vérifier si l'utilisateur a saisi des informations
if (-not $credential) {
    Write-Host "Aucune information d'identification n'a été saisie. Le script s'arrête."
    exit
}

# Exporter les informations d'identification dans un fichier sécurisé
try {
    $credential | Export-Clixml -Path $outputPath
    Write-Host "Les informations d'identification ont été enregistrées avec succès dans le fichier : $outputPath"
} catch {
    Write-Host "Une erreur s'est produite lors de l'enregistrement des informations d'identification : $_"
}