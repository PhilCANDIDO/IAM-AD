param (
    [Parameter(Mandatory)]
    [string[]]$AdminEmails,  # Liste des adresses e-mail des administrateurs

    [Parameter(Mandatory)]
    [string]$SmtpServer,  # Adresse du serveur SMTP

    [Parameter(Mandatory)]
    [string]$EmailFrom,  # Adresse de l'expéditeur

    [int]$InactiveMonths = 3,  # Période en mois pour les comptes désactivés (par défaut : 3 mois)

    [string]$TemplatesPath = "",  # Chemin vers les modèles HTML

    [string]$ExcelOutputPath = "$PSScriptRoot\DisabledAccountsSummary.csv",  # Chemin du fichier Excel de sortie

    [int]$SmtpPort = 587,  # Port SMTP (par défaut : 587)

    [string]$Username = "",  # Nom d'utilisateur SMTP (si nécessaire)

    [string]$Password = "",  # Mot de passe SMTP (si nécessaire)

    [switch]$SmtpSSL = $true,  # Activer SSL pour SMTP

    [switch]$EnableLog,  # Activer la journalisation

    [switch]$DebugMode  # Activer le mode débogage
)

Add-Type -AssemblyName System.Web

# Logging function
function Write-Log {
    param ([string]$Message)
    $timestamp = (Get-Date).ToString("yyyyMMdd-HH:mm:ss")
    if ($DebugMode) {
        Write-Host "[DEBUG][$timestamp] $Message"
    } elseif ($EnableLog) {
        Write-Host "[$timestamp] $Message"
        Add-Content -Path "$PSScriptRoot\DisabledAccountsSummary.log" -Value "[$timestamp] $Message"
    }
}

# Initialisation de la journalisation
$scriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path

# Check if file smtp_credential.xml exists
$credentialFilePath = Join-Path -Path $PSScriptRoot -ChildPath "smtp_credential.xml"
if (Test-Path -Path $credentialFilePath) {
    Write-Log "Chargement des informations d'identification SMTP depuis $credentialFilePath"
    $credential = Import-Clixml -Path $credentialFilePath
} else {
    Write-Log "Aucun fichier smtp_credential.xml trouvé. Utilisation des informations d'identification fournies via les paramètres."
    $credential = $null
}

# Template rendering function
function Render-Template {
    param (
        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [hashtable]$Variables
    )

    if (-not (Test-Path $TemplatePath)) {
        throw "Template file not found: $TemplatePath"
    }

    # Load the template
    $TemplateContent = Get-Content -Path $TemplatePath -Raw -Encoding UTF8

    # Replace variables in the template
    foreach ($Key in $Variables.Keys) {
        $TemplateContent = $TemplateContent -replace "{{\s*$Key\s*}}", $Variables[$Key]
    }

    return $TemplateContent
}

# Secure email sending function
function Send-SecureMail {
    param (
        [Parameter(Mandatory)]
        [string[]]$To,

        [Parameter(Mandatory)]
        [string]$From,

        [Parameter(Mandatory)]
        [string]$Subject,

        [Parameter(Mandatory)]
        [string]$Body,

        [Parameter(Mandatory)]
        [string]$SmtpServer,

        [Parameter(Mandatory)]
        [string]$Logo,

        [int]$SmtpPort = 587,

        [string]$Username = "",

        [string]$Password = "",

        [switch]$SmtpSSL = $true,

        [switch]$DryRun,

        [switch]$DebugMode,

        [string]$CsvFilePath
    )

    if ($DryRun) {
        Write-Host "[DRY-RUN] Email to $($To -join ', '): Subject='$Subject'"
        Write-Log "Dry-run mode: Email to $($To -join ', ') simulated."
        return
    }

    try {
        $SMTP = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        $SMTP.EnableSsl = $SmtpSSL

        # Use credentials xml file if available, else use provided credentials
        if ($SmtpAuth) {
            if ($credential) {
                $SMTP.Credentials = $credential.GetNetworkCredential()
            } elseif ($Username -and $Password) {
                $SMTP.Credentials = New-Object System.Net.NetworkCredential($Username, $Password)
            } else {
                throw "Aucune information d'identification SMTP n'a été fournie."
            }
        }
        
        $MailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8
        $mailMessage.BodyEncoding = [System.Text.Encoding]::UTF8
        $MailMessage.From = $From
        foreach ($Recipient in $To) {
            $MailMessage.To.Add($Recipient)
        }
        $MailMessage.Subject = $Subject
        $MailMessage.Body = $Body
        $MailMessage.IsBodyHtml = $true

        # Create a logo attachment
        if ($embeddedImages) {
            $logoAttachment = New-Object Net.Mail.Attachment($LogoPath)
            $logoAttachment.ContentId = "logo-image"
            $mailMessage.Attachments.Add($logoAttachment)
        }

        $CsvFileAttachement = New-Object Net.Mail.Attachment($CsvFilePath)
        $mailMessage.Attachments.Add($CsvFileAttachement)

        if ($DebugMode) {
            Write-Host "[DEBUG] Preparing to send email: Subject='$Subject', To='$($To -join ', ')'"
        }

        $SMTP.Send($MailMessage)

        Write-Log "Email sent to: $($To -join ', ')"
        if ($DebugMode) {
            Write-Host "[DEBUG] Email successfully sent to: $($To -join ', ')"
        }

    } catch {
        Write-Log "Failed to send email. Error: $_"
        if ($DebugMode) {
            Write-Host "[DEBUG] Error encountered during email sending:"
            Write-Host $_
        }
        throw $_
    }
}

## Main script logic
Write-Log "Script started."
# Get configuration file
$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "config.ps1"
if (-not (Test-Path -Path $ConfigFile)) {
    Write-Error "Configuration file not found. Script aborted."
    exit 1
}

try {
    . $ConfigFile
    $phoneSupportHref = $phoneSupport.Replace(" ", "")
    Write-Host "Configuration file loaded successfully."
} catch {
    Write-Error "Configuration cannot be loaded. Error : $_"
    exit 1
}

if (-not $emailSupport -or -not $phoneSupport -or -not $urlSupport) {
    Write-Error "Mandatories variables emailSupport, phoneSupport, urlSupport are missing in $ConfigFile. Please check file."
    exit 1
}

# HTML templates
if (-not $TemplatesPath) {
    $TemplatesPath = Join-Path -Path $PSScriptRoot -ChildPath "Templates"
}
$templatePaths = @(
    "$TemplatesPath\DisabledAccountsSummary.html",
    "$TemplatesPath\logo.png"
)

# Check if templates exists
foreach ($templatePath in $templatePaths) {
    if (-not (Test-Path -Path $templatePath)) {
        Write-Error "File $templatePath not found. Script aborted."
        exit 1
    }
    $LogoPath = Join-Path -Path $TemplatesPath -ChildPath "logo.png"
}

# Get the current date
$CurrentDate = Get-Date -Format "dd-MM-yyyy HH:mm:ss"

# Définir la date limite pour les comptes désactivés
$DateLimit = (Get-Date).AddMonths(-$InactiveMonths)

# DebugMode: Display script parameters
if ($DebugMode) {
    Write-Host "[DEBUG] Debug mode activated. Displaying script parameters:"
    Write-Host "[DEBUG]   - AdminEmails      : $($AdminEmails -join ', ')"
    Write-Host "[DEBUG]   - SmtpServer       : $SmtpServer"
    Write-Host "[DEBUG]   - SmtpPort         : $SmtpPort"
    Write-Host "[DEBUG]   - EmailFrom        : $EmailFrom"
    Write-Host "[DEBUG]   - Username         : $Username"
    Write-Host "[DEBUG]   - SmtpSSL          : $SmtpSSL"
    Write-Host "[DEBUG]   - TemplatesPath    : $TemplatesPath"
    Write-Host "[DEBUG]   - EnableLog        : $EnableLog"
    Write-Host "[DEBUG]   - InactiveMonths   : $InactiveMonths"
    Write-Host "[DEBUG]   - DebugMode        : $DebugMode"
    Write-Host "[DEBUG] "
    Write-Host "[DEBUG] Calculated thresholds:"
    Write-Host "[DEBUG]   - DateLimit        : "$DateLimit.toString("MM/dd/yyyy-HH:mm:ss")
    Write-Host "[DEBUG] "
}

# Récupération des comptes désactivés dans Active Directory
Write-Log "Querying Active Directory for disabled accounts."
$DisabledAccounts = Get-ADUser -Filter {Enabled -eq $false -and LastLogonTimestamp -lt $DateLimit} `
    -Properties GivenName, Surname, DisplayName, SamAccountName, EmailAddress, LastLogonTimestamp, Description | `
    Select-Object GivenName, Surname, DisplayName, SamAccountName, EmailAddress, `
        @{Name="LastLogonDate";Expression={[datetime]::FromFileTime($_.LastLogonTimestamp)}}, Description | `
    Sort-Object -Property LastLogonDate -Descending

if ($DebugMode) {
    Write-Host "[DEBUG] DisabledAccounts details:"
    $DisabledAccounts | Format-Table -AutoSize
}

if ($DisabledAccounts.Count -eq 0) {
    Write-Log "No disabled accounts found from the last $InactiveMonths months."
    $AdminBody = Render-Template -TemplatePath "$HtmlTemplatePath" -Variables @{
        CurrentDate    = $CurrentDate
        InactiveMonths = $InactiveMonths
        ScriptName     = $ScriptName
        HtmlTableRows  = "<tr><td colspan='5'>No disabled accounts found from the last $InactiveMonths months.</td></tr>"
    }
    Send-SecureMail -To $AdminEmails -From $EmailFrom `
    -Subject "Disabled Accounts Report" -Body $AdminBody `
    -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password -SmtpSSL:$SmtpSSL -DryRun:$DryRun `
    -CsvFilePath $ExcelOutputPath -logo $LogoPath
    return
}

# Préparation des données pour l'e-mail et l'export Excel
$AccountsData = @()
$HtmlTableRows = ""

foreach ($Account in $DisabledAccounts) {
    $DaysInactive = (New-TimeSpan -Start $Account.LastLogonDate -End (Get-Date)).Days
    $Row = @{
        DisplayName = $Account.DisplayName
        SamAccountName = $Account.SamAccountName
        LastLogon = $Account.LastLogonDate.ToString("dd-MM-yyyy HH:mm")
        DaysInactive = $DaysInactive
        Description = $Account.Description
    }
    $AccountsData += $Row

    # Génération des lignes HTML
    $HtmlTableRows += @"
        <tr>
            <td>$($Row.DisplayName)</td>
            <td>$($Row.SamAccountName)</td>
            <td>$($Row.LastLogon)</td>
            <td>$($Row.DaysInactive)</td>
            <td>$($Row.Description)</td>
        </tr>
"@
}

Write-Log "Preparing HTML and CSV output."

# Génération du tableau HTML
$HtmlTemplatePath = Join-Path $TemplatesPath "DisabledAccountsSummary.html"

# Génération du fichier CSV (Excel compatible BOM Windows)

$CsvContent = @"
`"DisplayName`";`"SamAccountName`";`"LastLogon`";`"DaysInactive`";`"Description`"`n
"@
$AccountsData | ForEach-Object {
    $CsvContent += "`"$($_.DisplayName)`";`"$($_.SamAccountName)`";`"$($_.LastLogon)`";`"$($_.DaysInactive)`";`"$($_.Description)`"`n"
}
Set-Content -Path $ExcelOutputPath -Value $CsvContent -Encoding UTF8


$AdminBody = Render-Template -TemplatePath "$HtmlTemplatePath" -Variables @{
    CurrentDate    = $CurrentDate
    InactiveMonths = $InactiveMonths
    ScriptName     = $ScriptName
    HtmlTableRows  = $HtmlTableRows
}

# Envoi de l'e-mail
Write-Log "Sending email with HTML and CSV attachment."
Send-SecureMail -To $AdminEmails -From $EmailFrom `
    -Subject "Disabled Accounts Report" -Body $AdminBody `
    -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password -SmtpSSL:$SmtpSSL -DryRun:$DryRun `
    -CsvFilePath $ExcelOutputPath -logo $LogoPath
Write-Log "Script completed."