param (
    [Parameter(Mandatory)]
    [string[]]$AdminEmails,

    [Parameter(Mandatory)]
    [string]$SmtpServer,

    [Parameter(Mandatory)]
    [string]$EmailFrom,

    [string]$TemplatesPath = "",

    [int]$SmtpPort = 587,

    [string]$Username = "",

    [string]$Password = "",

    [switch]$SmtpSSL = $true,

    [switch]$EnableLog,

    [int]$ExpirationDate = 15,

    [switch]$DebugMode,

    [switch]$DryRun
)

# Version du script
$scriptVersion = "1.7.1"
Add-Type -AssemblyName System.Web

# Changelog
# v1.7.1 - Added Default value for $ExpirationDate and CID logo usage in HTML templates.

<#
.SYNOPSIS
    Notify users and administrators about password expiration in Active Directory.

.DESCRIPTION
    This script identifies Active Directory accounts with passwords expiring within a custom date range and sends email notifications.
    Email messages are rendered using templates that support placeholders for dynamic content.

.PARAMETER AdminEmails
    Email addresses of administrators to receive the summary report.

.PARAMETER SmtpServer
    SMTP server address for sending emails.

.PARAMETER EmailFrom
    The email address to use as the sender.

.PARAMETER TemplatesPath
    The directory containing the HTML templates for email bodies.

.PARAMETER SmtpPort
    SMTP server port. Default is 587.

.PARAMETER Username
    Username for SMTP authentication. Leave empty for anonymous.

.PARAMETER Password
    Password for SMTP authentication. Leave empty for anonymous.

.PARAMETER SmtpSSL
    Enable or disable SSL for SMTP. Default is true.

.PARAMETER EnableLog
    Enable logging of actions to a log file.

.PARAMETER ExpirationDate
    Define a custom date range for password expiration. Default is 15 days from today.

.PARAMETER DebugMode
    Enable debug mode. Outputs logs to the console instead of a log file.

.PARAMETER DryRun
    Execute the script without sending emails. Only simulates email actions.

.EXAMPLE
    .\PasswordExpirationNotifier.ps1 -AdminEmails "admin@example.com" -SmtpServer "smtp.example.com" -EmailFrom "no-reply@example.com" -TemplatesPath "C:\templates" --enable-log

.NOTES
    Script version: 1.7.0
    Author: Philippe Candido (philippe.candido@emerging-it.fr)
#>

# Helpline
if ($args -contains '-h' -or $args -contains '--help') {
    Get-Help -Full $MyInvocation.MyCommand.Path
    exit
}

# Logging function
function Write-Log {
    param ([string]$Message)
    $timestamp = (Get-Date).ToString("yyyyMMdd-HH:mm:ss")
    if ($DebugMode) {
        Write-Host "[DEBUG][$timestamp] $Message"
    } elseif ($EnableLog) {
        Write-Host "[$timestamp] $Message"
        Add-Content -Path "$PSScriptRoot\PasswordExpirationNotifier.log" -Value "[$timestamp] $Message"
    }
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

        [switch]$DebugMode
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
            $Attachment = New-Object Net.Mail.Attachment($LogoPath)
            $Attachment.ContentId = "logo-image"
            $mailMessage.Attachments.Add($Attachment)
        }
        
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
# Get script name
$ScriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path
# Get the current date
$CurrentDate = Get-Date -Format "dd-MM-yyyy HH:mm:ss"

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
    "$TemplatesPath\UserPasswordNotification.html",
    "$TemplatesPath\logo.png",
    "$TemplatesPath\AdminPasswordSummary.html"
)

# Check if templates exist
foreach ($templatePath in $templatePaths) {
    if (-not (Test-Path -Path $templatePath)) {
        Write-Error "File $templatePath not found. Script aborted."
        exit 1
    }
    $LogoPath = Join-Path -Path $TemplatesPath -ChildPath "logo.png"
}

# Check if file smtp_credential.xml exists
$credentialFilePath = Join-Path -Path $PSScriptRoot -ChildPath "smtp_credential.xml"
if (Test-Path -Path $credentialFilePath) {
    Write-Log "Chargement des informations d'identification SMTP depuis $credentialFilePath"
    $credential = Import-Clixml -Path $credentialFilePath
} else {
    Write-Log "Aucun fichier smtp_credential.xml trouvé. Utilisation des informations d'identification fournies via les paramètres."
    $credential = $null
}

# DebugMode: Display script argument values
if ($DebugMode) {
    Write-Host "[DEBUG] Debug mode activated. Displaying script parameters:"
    Write-Host "[DEBUG]   - AdminEmails      : $($AdminEmails -join ', ')"
    Write-Host "[DEBUG]   - SmtpServer       : $SmtpServer"
    Write-Host "[DEBUG]   - SmtpPort         : $SmtpPort"
    Write-Host "[DEBUG]   - EmailFrom        : $EmailFrom"
    Write-Host "[DEBUG]   - TemplatesPath    : $TemplatesPath"
    Write-Host "[DEBUG]   - Username         : $Username"
    Write-Host "[DEBUG]   - SmtpSSL          : $SmtpSSL"
    Write-Host "[DEBUG]   - EnableLog        : $EnableLog"
    Write-Host "[DEBUG]   - ExpirationDate   : $ExpirationDate"
    Write-Host "[DEBUG]   - DebugMode        : $DebugMode"
    Write-Host "[DEBUG]   - DryRun           : $DryRun"
    Write-Host "[DEBUG]   - LogoPath         : $LogoPath"
    Write-Host "[DEBUG]"
}

# Validate AD Module
if (-not (Get-Module -Name ActiveDirectory)) {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "Active Directory module loaded successfully."
}

# Date range for password expiration
$Today = Get-Date
$ExpiryThreshold = $Today.AddDays($ExpirationDate)

Write-Log "Script started. Checking for passwords expiring between $Today and $ExpiryThreshold."
Write-Log "Expiration range set to $ExpirationDate days."
if ($DebugMode) {
    Write-Host "[DEBUG]   - ExpiryThreshold         : $LogoPath"
    Write-Host "[DEBUG]   - ExpirationDate         : $ExpirationDate"
}

# Fetch all active users and compute their password expiration dates
$AllUsers = Get-ADUser -Filter {Enabled -eq $True -and PasswordNeverExpires -eq $False} `
    -Properties DisplayName, GivenName, Surname, SamAccountName, UserPrincipalName, EmailAddress, msDS-UserPasswordExpiryTimeComputed | Select-Object `
    -Property DisplayName, GivenName, Surname, SamAccountName, UserPrincipalName, EmailAddress, `
              @{Name="ExpirationDate";Expression={[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")}}

if ($DebugMode) {
    Write-Host "[DEBUG] AllUsers details:"
    $AllUsers | Format-Table -AutoSize
}

# Filter users whose password will expire within the specified range
$ExpiringUsers = $AllUsers | Where-Object {
    $_.ExpirationDate -le $ExpiryThreshold -and $_.ExpirationDate -ge $Today
} | Sort-Object "ExpirationDate"

if ($ExpiringUsers.Count -eq 0) {
    Write-Log "No users found with expiring passwords."
    # Render the summary email for administrators
    $UserTableHtml = "<tr><td colspan='5' style='padding: 10px; border: 1px solid #ddd;'>No users found with expiring passwords.</td></tr>"
    $AdminBody = Render-Template -TemplatePath "$TemplatesPath\AdminPasswordSummary.html" -Variables @{
    ExpirationRange = $ExpirationDate
    UserTable = $UserTableHtml
    ScriptName = $ScriptName
    CurrentDate = $CurrentDate
    }

    Send-SecureMail -To $AdminEmails -From $EmailFrom `
        -Subject "Password Expiration Summary" -Body $AdminBody -Logo $LogoPath `
        -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password -SmtpSSL:$SmtpSSL -DryRun:$DryRun -DebugMode:$DebugMode

    return
}


if ($DebugMode) {
    Write-Host "[DEBUG] ExpiringUsers details:"
    $ExpiringUsers | Format-Table -AutoSize
}

Write-Log "Found $($ExpiringUsers.Count) users with expiring passwords."

# Notify users
$UsersWithoutEmail = @()
foreach ($User in $ExpiringUsers) {
    if ($User.EmailAddress) {
        # Calculate the number of days left before expiration
        $DaysLeft = ($User.ExpirationDate - $Today).Days
        if ($DaysLeft -gt 1) {
            $DaysLeftText = "dans environ ${DaysLeft} jours"
        } elseif ($DaysLeft -eq 1) {
            $DaysLeftText = "dans 1 jour"
        } else {
            $DaysLeftText = "aujourd'hui"
        }
        $Templatefile = "$TemplatesPath\UserPasswordNotification.html"
        if ($DaysLeft -lt 0) {
            Write-Log "User $($User.SamAccountName) has an expired password."
            $Templatefile = "$TemplatesPath\UserPasswordExpired.html"
        }
        $MailBody = Render-Template -TemplatePath $Templatefile -Variables @{
            ExpirationRange = $ExpirationDate
            UserPrincipalName = $User.UserPrincipalName
            ExpirationDate    = $User.ExpirationDate.ToString("dd MMMM yyyy HH:mm")
            emailSupport      = $emailSupport
            phoneSupport      = $phoneSupport
            phoneSupportHref  = $phoneSupportHref
            urlSupport        = $urlSupport
            ScriptName        = $ScriptName
            PortalSupport     = $PortalSupport
            DaysLeftText      = $DaysLeftText

        }
        Send-SecureMail -To $User.EmailAddress -From $EmailFrom -Logo $LogoPath `
            -Subject "Password Expiration Reminder" -Body $MailBody `
            -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password -SmtpSSL:$SmtpSSL -DryRun:$DryRun -DebugMode:$DebugMode
    } else {
        Write-Log "User $($User.SamAccountName) has no email address."
        $UsersWithoutEmail += $User
    }
}

# Build Users HTML Table
$UserTableHtml = ""
if ($DebugMode) {
    Write-Host "[DEBUG] Expiring users:"
    Write-Host $ExpiringUsers
}
foreach ($User in $ExpiringUsers) {
    $UserTableHtml += "<tr>" +
        "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($User.DisplayName))</td>" +
        "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($User.GivenName))</td>" +
        "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($User.Surname))</td>" +
        "<td style='padding: 10px; border: 1px solid #ddd;'><a href='mailto:$([System.Web.HttpUtility]::HtmlEncode($User.EmailAddress))'>$([System.Web.HttpUtility]::HtmlEncode($User.EmailAddress))</a></td>" +
        "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($User.UserPrincipalName))</td>" +
        "<td style='padding: 10px; border: 1px solid #ddd;'>$([System.Web.HttpUtility]::HtmlEncode($User.ExpirationDate.ToString("yyyy-MM-dd HH:mm")))</td>" +
        "</tr>"
}

if ($DebugMode) {
    Write-Host "[DEBUG] Following Users will be notified (ExpiringUsers):"
    $ExpiringUsers | Format-Table -AutoSize
}    

# Render the summary email for administrators
$AdminBody = Render-Template -TemplatePath "$TemplatesPath\AdminPasswordSummary.html" -Variables @{
    ExpirationRange = $ExpirationDate
    UserTable = $UserTableHtml
    ScriptName = $ScriptName
    CurrentDate = $CurrentDate
}

Send-SecureMail -To $AdminEmails -From $EmailFrom `
    -Subject "Password Expiration Summary" -Body $AdminBody -Logo $LogoPath `
    -SmtpServer $SmtpServer -SmtpPort $SmtpPort -Username $Username -Password $Password -SmtpSSL:$SmtpSSL -DryRun:$DryRun -DebugMode:$DebugMode

Write-Log "Script completed successfully."
